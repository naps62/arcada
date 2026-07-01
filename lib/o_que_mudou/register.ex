defmodule OQueMudou.Register do
  @moduledoc """
  The private register of what changed in Diário da República Série I.

  Groups the core data model — `Edition`, `Act`, `Summary` — and the fixed
  life-domain taxonomy shared across them.
  See `docs/PLAN.md`.
  """

  import Ecto.Query, warn: false

  alias OQueMudou.Repo
  alias OQueMudou.Register.{Edition, Act, Summary}

  @life_domains ~w(fiscal trabalho saúde família habitação educação transportes justiça ambiente administração)

  @doc "The fixed life-domain taxonomy used to tag summaries."
  def life_domains, do: @life_domains

  @periods [:semana, :mes, :ano]

  @doc "Date-range filter options, each a window from some past point up to today."
  def periods, do: @periods

  @doc "Validate a period string/atom against the fixed set. Returns the atom, or `nil` for all-time."
  def fetch_period(nil), do: nil
  def fetch_period(p) when is_atom(p), do: if(p in @periods, do: p, else: nil)

  def fetch_period(p) when is_binary(p),
    do: Enum.find(@periods, &(Atom.to_string(&1) == p))

  # First day of each window, relative to `today`. Nested by design: `:ano`
  # contains `:mes` contains `:semana`, so counts grow as the window widens.
  defp period_start(period), do: period_start(period, Date.utc_today())
  defp period_start(:semana, today), do: Date.beginning_of_week(today)
  defp period_start(:mes, today), do: Date.beginning_of_month(today)
  defp period_start(:ano, today), do: Date.new!(today.year, 1, 1)

  @doc "Validate a domain string/atom against the fixed taxonomy. Returns `{:ok, atom}` or `:error`."
  def fetch_domain(domain) when is_atom(domain), do: fetch_domain(Atom.to_string(domain))

  def fetch_domain(domain) when is_binary(domain) do
    if domain in @life_domains, do: {:ok, String.to_existing_atom(domain)}, else: :error
  end

  @doc """
  Count acts tagged with each life-domain (via their summaries) — drives the
  UI's domain filter badges. Returns a map of `domain_string => count`,
  including domains with zero acts so the filter always shows the full taxonomy.

  `opts[:period]` restricts the count to acts published within that window, so
  the domain badges track whatever date filter is active.
  """
  def domain_counts(opts \\ []) do
    counted =
      from(s in Summary,
        select: {fragment("unnest(?)", s.domains), count(s.act_id, :distinct)},
        group_by: fragment("unnest(?)", s.domains)
      )
      |> join_summary_period(fetch_period(opts[:period]))
      |> Repo.all()
      |> Map.new()

    Map.new(@life_domains, fn d -> {d, Map.get(counted, d, 0)} end)
  end

  @doc """
  Count acts falling in each date window — drives the date filter badges.
  Returns a map keyed by `:tudo` (all time) plus each period in `periods/0`.

  `opts[:domain]` restricts the counts to a single life-domain, so the date
  badges track whatever domain filter is active (the mirror of `domain_counts/1`).
  """
  def period_counts(opts \\ []) do
    base =
      from(a in Act, select: count(a.id, :distinct))
      |> join_domain(opts[:domain])

    Map.new([:tudo | @periods], fn
      :tudo -> {:tudo, Repo.one(base)}
      period -> {period, base |> join_period(period) |> Repo.one()}
    end)
  end

  @doc """
  List acts, newest first, optionally filtered by life-domain and/or date window.
  `opts`: `:domain` (string|atom, validated against the taxonomy — an unknown
  domain yields no results), `:period` (see `fetch_period/1`) and `:limit`.
  """
  def list_acts(opts \\ []) do
    base =
      from(a in Act,
        order_by: [desc: a.published_at, desc: a.id],
        preload: [:edition, :summaries]
      )

    base
    |> filter_domain(opts[:domain])
    |> join_period(fetch_period(opts[:period]))
    |> maybe_limit(opts[:limit])
    |> Repo.all()
  end

  # An act can carry the same domain across several summaries; dedupe the rows.
  defp filter_domain(query, nil), do: query
  defp filter_domain(query, domain), do: from(q in join_domain(query, domain), distinct: true)

  # Inner-join the domain predicate without forcing DISTINCT, so callers that
  # already aggregate (counts) compose cleanly with those that don't (listing).
  defp join_domain(query, nil), do: query

  defp join_domain(query, domain) do
    case fetch_domain(domain) do
      {:ok, atom} ->
        d = Atom.to_string(atom)

        from(a in query,
          join: s in assoc(a, :summaries),
          where: fragment("? = ANY(?)", ^d, s.domains)
        )

      :error ->
        # Unknown domain → match nothing rather than ignoring the filter.
        from(a in query, where: false)
    end
  end

  # Restrict acts to those whose edition was published on/after the window start.
  defp join_period(query, nil), do: query

  defp join_period(query, period) do
    start = period_start(period)
    from(a in query, join: e in assoc(a, :edition), where: e.date >= ^start)
  end

  # Same window, reached from the summary side (summary → act → edition).
  defp join_summary_period(query, nil), do: query

  defp join_summary_period(query, period) do
    start = period_start(period)

    from(s in query,
      join: a in assoc(s, :act),
      join: e in assoc(a, :edition),
      where: e.date >= ^start
    )
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

  @doc "Acts published on `date` with no summary yet — what the daily cron enqueues for summarization."
  def acts_without_summary(%Date{} = date) do
    from(a in Act,
      join: e in assoc(a, :edition),
      left_join: s in assoc(a, :summaries),
      where: e.date == ^date and is_nil(s.id)
    )
    |> Repo.all()
  end

  @doc """
  Lean act rows for the sitemap: `{id, last_modified}` for every act that has a
  published summary (an act with no summary is a stub — nothing to index yet).
  Newest first, capped so the sitemap stays well under the 50k-URL limit.
  """
  def sitemap_acts(limit \\ 20_000) do
    from(a in Act,
      where: not is_nil(a.published_summary_id),
      order_by: [desc: a.updated_at, desc: a.id],
      limit: ^limit,
      select: {a.id, a.updated_at}
    )
    |> Repo.all()
  end

  @doc "Fetch one act with edition + summaries (each with its provider) preloaded."
  def get_act!(id) do
    Act
    |> Repo.get!(id)
    |> Repo.preload([:edition, summaries: :provider])
  end

  @doc """
  The canonical summary shown publicly for an act: the explicitly-published one
  if set, else the most recently generated. Expects `:summaries` preloaded.
  """
  def published_summary(%Act{published_summary_id: pid, summaries: summaries})
      when is_integer(pid) and is_list(summaries) do
    Enum.find(summaries, &(&1.id == pid)) || latest_summary(summaries)
  end

  def published_summary(%Act{summaries: summaries}) when is_list(summaries),
    do: latest_summary(summaries)

  def published_summary(_act), do: nil

  defp latest_summary(summaries),
    do: summaries |> Enum.sort_by(& &1.generated_at, {:desc, DateTime}) |> List.first()

  @doc "Mark `summary` as the published one for `act` (or pass nil to clear)."
  def set_published(%Act{} = act, summary) do
    act
    |> Act.changeset(%{published_summary_id: summary && summary.id})
    |> Repo.update()
  end
end
