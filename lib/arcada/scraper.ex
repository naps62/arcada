defmodule Arcada.Scraper do
  @moduledoc """
  Ingests a day of Diário da República Série I into the register.

  Pipeline (see `docs/PLAN.md` / `docs/endpoints.md`):

      bootstrap session → list editions+acts for a date → upsert (idempotent)
                        → best-effort per-act detail enrichment (full_text/pdf_url)

  Idempotent: re-running a date upserts by `(serie, number)` / `dre_id`, so a
  second run is a no-op on counts and never clobbers enrichment with `nil`.
  """

  require Logger

  alias Arcada.Register
  alias Arcada.Scraper.{Parser, Session}

  @doc """
  Scrape and persist one date. Returns
  `{:ok, %{editions: n, acts: m, enriched: k}}` or `{:error, reason}`.

  Options:
    * `:client` — a pre-built/bootstrapped `Client` (tests inject a stubbed one)
    * `:enrich` — fetch per-act detail (default `true`)
  """
  def ingest_date(%Date{} = date, opts \\ []) do
    case Session.start_link(opts) do
      {:ok, session} ->
        try do
          with {:ok, raw} <- Session.list_editions(session, date) do
            editions = Parser.parse_editions(raw)
            {:ok, persist(editions, session, Keyword.get(opts, :enrich, true))}
          end
        after
          Session.stop(session)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Enqueue a historical **ingest** job per business day in the range (inclusive),
  newest day first — Série I doesn't publish on weekends. Ingest-only: the acts
  land without summaries, and `Arcada.Summarizer.SummarySweeper` summarizes them
  gradually. Safe to run repeatedly — each day's ingest is idempotent.

  Returns the list of `Oban.insert/1` results, newest date first.
  """
  def backfill(%Date.Range{} = range) do
    range
    |> Enum.filter(&business_day?/1)
    |> Enum.reverse()
    |> Enum.map(fn date ->
      %{date: Date.to_iso8601(date), summarize: false}
      |> Arcada.Scraper.IngestWorker.new()
      |> Oban.insert()
    end)
  end

  def backfill(%Date{} = from, %Date{} = to), do: backfill(Date.range(from, to))

  @doc """
  Backfill from `from` up to today (inclusive) — the one-shot "ingest the last N
  days/months of the register" call. The sweeper takes it from there.
  """
  def backfill_since(%Date{} = from), do: backfill(from, Date.utc_today())

  defp business_day?(%Date{} = date), do: Date.day_of_week(date) in 1..5

  # The self-healed apiVersion lives in the `session` process, so persistence no
  # longer threads any transport state — it just upserts and asks the session to
  # enrich each act.
  defp persist(editions, session, enrich?) do
    Enum.reduce(editions, %{editions: 0, acts: 0, enriched: 0}, fn ed_attrs, acc ->
      {acts_attrs, ed_attrs} = Map.pop(ed_attrs, :acts)
      ed_attrs = Map.put(ed_attrs, :scraped_at, now())

      case Register.upsert_edition(ed_attrs) do
        {:ok, edition} ->
          {n_acts, n_enriched} = persist_acts(acts_attrs, edition, session, enrich?)

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

  defp persist_acts(acts_attrs, edition, session, enrich?) do
    Enum.reduce(acts_attrs, {0, 0}, fn act_attrs, {n, enr} ->
      act_attrs =
        act_attrs
        |> Map.put(:edition_id, edition.id)
        |> maybe_enrich(session, enrich?)

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

  # Best-effort: the session self-heals a rotated detail apiVersion internally;
  # any remaining error just leaves the act un-enriched. The skeleton from the
  # list call is the load-bearing data.
  defp maybe_enrich(act_attrs, _session, false), do: act_attrs

  defp maybe_enrich(act_attrs, session, true) do
    with {:ok, tipo, key} <- Parser.split_link_sitemap(act_attrs[:source_url]),
         {:ok, enrichment} <- Session.act_detail(session, tipo, key) do
      Map.merge(act_attrs, enrichment)
    else
      _ -> act_attrs
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
