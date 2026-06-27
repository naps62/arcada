defmodule OQueMudou.Scraper do
  @moduledoc """
  Ingests a day of Diário da República Série I into the register.

  Pipeline (see `docs/PLAN.md` / `docs/endpoints.md`):

      bootstrap session → list editions+acts for a date → upsert (idempotent)
                        → best-effort per-act detail enrichment (full_text/pdf_url)

  Idempotent: re-running a date upserts by `(serie, number)` / `dre_id`, so a
  second run is a no-op on counts and never clobbers enrichment with `nil`.
  """

  require Logger

  alias OQueMudou.Register
  alias OQueMudou.Scraper.{Client, Parser}

  @doc """
  Scrape and persist one date. Returns
  `{:ok, %{editions: n, acts: m, enriched: k}}` or `{:error, reason}`.

  Options:
    * `:client` — a pre-built/bootstrapped `Client` (tests inject a stubbed one)
    * `:enrich` — fetch per-act detail (default `true`)
  """
  def ingest_date(%Date{} = date, opts \\ []) do
    with {:ok, client} <- ensure_client(opts),
         {:ok, raw} <- Client.list_editions(client, date) do
      editions = Parser.parse_editions(raw)
      {:ok, persist(editions, client, Keyword.get(opts, :enrich, true))}
    end
  end

  @doc """
  Enqueue an `IngestWorker` job for each date in a range (inclusive). Backfill
  helper — safe to run repeatedly since each day's ingest is idempotent.
  Returns the list of `Oban.insert/1` results.
  """
  def backfill(%Date.Range{} = range) do
    Enum.map(range, fn date ->
      %{date: Date.to_iso8601(date)}
      |> OQueMudou.Scraper.IngestWorker.new()
      |> Oban.insert()
    end)
  end

  def backfill(%Date{} = from, %Date{} = to), do: backfill(Date.range(from, to))

  defp ensure_client(opts) do
    case Keyword.get(opts, :client) do
      nil -> Client.new() |> Client.bootstrap()
      %Client{module_version: nil} = c -> Client.bootstrap(c)
      %Client{} = c -> {:ok, c}
    end
  end

  defp persist(editions, client, enrich?) do
    Enum.reduce(editions, %{editions: 0, acts: 0, enriched: 0}, fn ed_attrs, acc ->
      {acts_attrs, ed_attrs} = Map.pop(ed_attrs, :acts)
      ed_attrs = Map.put(ed_attrs, :scraped_at, now())

      case Register.upsert_edition(ed_attrs) do
        {:ok, edition} ->
          {n_acts, n_enriched} = persist_acts(acts_attrs, edition, client, enrich?)

          %{
            acc
            | editions: acc.editions + 1,
              acts: acc.acts + n_acts,
              enriched: acc.enriched + n_enriched
          }

        {:error, changeset} ->
          Logger.warning(
            "skipping edition #{inspect(ed_attrs[:number])}: #{inspect(changeset.errors)}"
          )

          acc
      end
    end)
  end

  defp persist_acts(acts_attrs, edition, client, enrich?) do
    Enum.reduce(acts_attrs, {0, 0}, fn act_attrs, {n, enr} ->
      act_attrs =
        act_attrs
        |> Map.put(:edition_id, edition.id)
        |> maybe_enrich(client, enrich?)

      case Register.upsert_act(act_attrs) do
        {:ok, _act} ->
          enriched? = not is_nil(act_attrs[:full_text]) or not is_nil(act_attrs[:pdf_url])
          {n + 1, enr + if(enriched?, do: 1, else: 0)}

        {:error, changeset} ->
          Logger.warning(
            "skipping act #{inspect(act_attrs[:dre_id])}: #{inspect(changeset.errors)}"
          )

          {n, enr}
      end
    end)
  end

  # Best-effort: a rotated detail apiVersion (or any error) just leaves the act
  # un-enriched. The skeleton from the list call is the load-bearing data.
  defp maybe_enrich(act_attrs, _client, false), do: act_attrs

  defp maybe_enrich(act_attrs, client, true) do
    with {:ok, tipo, key} <- Parser.split_link_sitemap(act_attrs[:source_url]),
         {:ok, enrichment} <- Client.act_detail(client, tipo, key) do
      Map.merge(act_attrs, enrichment)
    else
      _ -> act_attrs
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
