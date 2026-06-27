defmodule OQueMudou.Register do
  @moduledoc """
  The private register of what changed in Diário da República Série I.

  Groups the core data model — `Edition`, `Act`, `Summary` — and the fixed
  vocabularies (life-domain taxonomy, provenance status) shared across them.
  See `docs/PLAN.md`.
  """

  import Ecto.Query, warn: false

  alias OQueMudou.Repo
  alias OQueMudou.Register.{Edition, Act, Summary}

  @life_domains ~w(fiscal trabalho saúde família habitação educação transportes justiça ambiente administração)

  @doc "The fixed life-domain taxonomy used to tag summaries."
  def life_domains, do: @life_domains

  @doc "The provenance-ladder statuses a summary can hold (MVP ships only `:unreviewed`)."
  def statuses, do: [:unreviewed, :community_reviewed, :verified]

  @doc "Validate a domain string/atom against the fixed taxonomy. Returns `{:ok, atom}` or `:error`."
  def fetch_domain(domain) when is_atom(domain), do: fetch_domain(Atom.to_string(domain))

  def fetch_domain(domain) when is_binary(domain) do
    if domain in @life_domains, do: {:ok, String.to_existing_atom(domain)}, else: :error
  end

  @doc """
  Count acts tagged with each life-domain (via their summaries) — drives the
  UI's domain filter badges. Returns a map of `domain_string => count`,
  including domains with zero acts so the filter always shows the full taxonomy.
  """
  def domain_counts do
    counted =
      from(s in Summary,
        select: {fragment("unnest(?)", s.domains), count(s.act_id, :distinct)},
        group_by: fragment("unnest(?)", s.domains)
      )
      |> Repo.all()
      |> Map.new()

    Map.new(@life_domains, fn d -> {d, Map.get(counted, d, 0)} end)
  end

  @doc """
  List acts, newest first, optionally filtered to those whose summary carries a
  given life-domain. `opts`: `:domain` (string|atom, validated against the
  taxonomy — an unknown domain yields no results) and `:limit`.
  """
  def list_acts(opts \\ []) do
    base =
      from(a in Act,
        order_by: [desc: a.published_at, desc: a.id],
        preload: [:edition, :summaries]
      )

    base
    |> maybe_filter_domain(opts[:domain])
    |> maybe_limit(opts[:limit])
    |> Repo.all()
  end

  defp maybe_filter_domain(query, nil), do: query

  defp maybe_filter_domain(query, domain) do
    case fetch_domain(domain) do
      {:ok, atom} ->
        d = Atom.to_string(atom)

        from(a in query,
          join: s in assoc(a, :summaries),
          where: fragment("? = ANY(?)", ^d, s.domains),
          distinct: true
        )

      :error ->
        # Unknown domain → match nothing rather than ignoring the filter.
        from(a in query, where: false)
    end
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) when is_integer(limit), do: from(q in query, limit: ^limit)

  @doc """
  Idempotently insert-or-update an edition, keyed on `(serie, number)`.
  Re-scraping the same day updates mutable fields and returns the same row.
  """
  def upsert_edition(attrs) do
    %Edition{}
    |> Edition.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:date, :sumario_url, :scraped_at, :updated_at]},
      conflict_target: [:serie, :number],
      returning: true
    )
  end

  @doc """
  Idempotently insert-or-update an act, keyed on `dre_id` (the scraper's
  idempotency key). `nil` enrichment fields (full_text/pdf_url) never clobber
  an already-populated value.
  """
  def upsert_act(attrs) do
    %Act{}
    |> Act.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, replaceable_act_fields(attrs)},
      conflict_target: [:dre_id],
      returning: true
    )
  end

  # Only overwrite columns we actually have a value for, so a skeleton re-scrape
  # doesn't wipe full_text/pdf_url captured by an earlier detail pass.
  @act_mutable ~w(edition_id tipo emitter title full_text source_url pdf_url published_at)a
  defp replaceable_act_fields(attrs) do
    present = Enum.filter(@act_mutable, fn key -> not is_nil(Map.get(attrs, key)) end)
    [:updated_at | present]
  end
end
