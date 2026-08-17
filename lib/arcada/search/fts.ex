defmodule Arcada.Search.FTS do
  @moduledoc """
  Postgres full-text search over acts + summaries (issue #28), the exact-term
  half of hybrid search. Semantic search (`Arcada.Search`) blurs law numbers
  and rare tokens; FTS catches them: `tsvector` with the `portuguese` dictionary
  tokenizes "Lei 23/2023" or "Decreto-Lei 10-A/2022" straight through.

  The searchable text is split across two tables — the act's identifying header
  (`title`/`tipo`/`emitter`, where the law numbers live) and the summary's
  plain-language body (`plain_text`/`headline`) — each backed by its own GIN
  expression index (see the `add_fts_indexes` migration). An act ranks by the
  best combined `ts_rank` across its summaries. No GPU, no pgvector, no new infra.
  """
  import Ecto.Query

  alias Arcada.Repo
  alias Arcada.Register.{Act, Summary}

  # Hard cap on the returned id list (issue #72). A common Portuguese word
  # matches most of the corpus, so an uncapped FTS ranks and returns the whole
  # id list on every debounced keystroke — held in each LiveView's assigns, and
  # re-expanded into a same-size `IN` list by `Arcada.Search`'s recency lookup.
  # FTS is deliberately not rate-limited, so this is also a cheap-DoS surface.
  # RRF only needs enough depth to fuse, and the relevance floor already argues
  # against the long tail. Tunable live via `config :arcada, #{inspect(__MODULE__)}`.
  @default_limit 200

  @doc """
  Act ids whose header or summary text matches `query`, best match first, capped
  at the configured limit (default #{@default_limit}).

  `opts[:from]` / `opts[:to]` (both `Date`, inclusive) restrict the result to
  acts published in that window — how a subscription searches only what is new
  since its last run (issue #95). Acts with no `published_at` fall outside any
  window and so are invisible to a bounded search.

  Empty for a blank query or one that reduces to only stopwords/punctuation
  (`websearch_to_tsquery` yields an empty query, which matches nothing). User
  input is passed straight to `websearch_to_tsquery`, which never raises on junk.
  """
  def ranked_ids(query, opts \\ [])

  def ranked_ids(query, opts) when is_binary(query) do
    case String.trim(query) do
      "" -> []
      q -> q |> ranked_query(limit()) |> filter_window(opts[:from], opts[:to]) |> Repo.all()
    end
  end

  def ranked_ids(_query, _opts), do: []

  @doc """
  One keyset page of matching act ids, newest `editions.date` first (issue #104).

  The chronological half of search deliberately skips ranking altogether: no
  `ts_rank`, no `@default_limit` top-N, no semantic leg. A date-ordered list must
  be able to reach every match, so capping it by relevance first would silently
  hide recent weak matches with no visible reason.

  Ordered and keyset-paged on `editions.date` — the date the UI prints beside each
  result — not `acts.published_at`, so a strictly-ordered list never looks
  unsorted. `opts[:before]` is a `{Date, act_id}` cursor from the last row of the
  previous page (exclusive); omit it for the first page. `opts[:limit]` caps the
  page.

  Matching is `candidate_ids/1`, same as `ranked_ids/2`, and the `exists` on
  summaries keeps the "summary-less acts are invisible" semantics the ranking
  query gets from its inner join.
  """
  def chronological_ids(query, opts \\ [])

  def chronological_ids(query, opts) when is_binary(query) do
    case String.trim(query) do
      "" ->
        []

      q ->
        q
        |> chronological_query(Keyword.fetch!(opts, :limit))
        |> filter_before(opts[:before])
        |> Repo.all()
    end
  end

  def chronological_ids(_query, _opts), do: []

  defp chronological_query(q, limit) do
    has_summary = from(s in Summary, where: s.act_id == parent_as(:act).id, select: 1)

    from a in Act,
      as: :act,
      join: e in assoc(a, :edition),
      as: :ed,
      where: a.id in subquery(candidate_ids(q)) and exists(has_summary),
      # `id` is the tiebreak *and* the second keyset key: `date` alone is
      # day-granular, so without it a page boundary inside a busy day would
      # repeat or skip acts.
      order_by: [desc: e.date, desc: a.id],
      limit: ^limit,
      select: a.id
  end

  defp filter_before(query, nil), do: query

  defp filter_before(query, {%Date{} = date, id}) do
    from([act: a, ed: e] in query,
      where: e.date < ^date or (e.date == ^date and a.id < ^id)
    )
  end

  # Applied to the outer ranking query, not to `candidate_ids/1`: the candidate
  # halves must each stay a single-table tsvector scan so their GIN indexes are
  # usable. Narrowing here also keeps the LIMIT a true top-N *within* the window.
  defp filter_window(query, nil, nil), do: query

  defp filter_window(query, window_from, window_to) do
    query
    |> then(fn q ->
      if window_from, do: from(a in q, where: a.published_at >= ^window_from), else: q
    end)
    |> then(fn q ->
      if window_to, do: from(a in q, where: a.published_at <= ^window_to), else: q
    end)
  end

  defp limit do
    Application.get_env(:arcada, __MODULE__, [])[:limit] || @default_limit
  end

  # The tsvector expressions must stay byte-for-byte identical to the ones in the
  # `add_fts_indexes` migration, or the GIN indexes won't be used for the match.
  #
  # Candidate acts come from `candidate_ids/1` — an index-friendly UNION. The
  # match itself (`a.id in subquery(...)`) is kept out of this join's WHERE on
  # purpose: an `acts_tsvector @@ q OR summaries_tsvector @@ q` here spans both
  # sides of the acts⋈summaries join, so Postgres can use neither GIN index and
  # materializes the whole join per keystroke. This ranking join now runs only
  # over the pre-filtered candidates; its ORDER BY (max header+body ts_rank
  # across an act's summaries) is unchanged, so ranking is identical.
  defp ranked_query(q, limit) do
    from a in Act,
      join: s in assoc(a, :summaries),
      where: a.id in subquery(candidate_ids(q)),
      group_by: a.id,
      # Cap after ORDER BY so this is the true top-N by rank, not an arbitrary
      # slice — the LIMIT must stay on the outer ranking query, never pushed
      # into `candidate_ids` (which is unordered).
      limit: ^limit,
      # Best combined header+body rank across the act's summaries; a non-matching
      # tsvector contributes ts_rank 0, so this is just the matching side's score.
      order_by: [
        desc:
          max(
            fragment(
              "ts_rank(to_tsvector('portuguese', coalesce(?, '') || ' ' || coalesce(?, '') || ' ' || coalesce(?, '')), websearch_to_tsquery('portuguese', ?)) + ts_rank(to_tsvector('portuguese', coalesce(?, '') || ' ' || coalesce(?, '')), websearch_to_tsquery('portuguese', ?))",
              a.title,
              a.tipo,
              a.emitter,
              ^q,
              s.plain_text,
              s.headline,
              ^q
            )
          ),
        # Stable tiebreak so equal-ranked acts keep a deterministic order.
        asc: a.id
      ],
      select: a.id
  end

  # Ids of acts that match on the header OR the body, as a UNION of two
  # single-table subqueries. Each half touches one table's tsvector only, so
  # each can be answered by its own `add_fts_indexes` GIN index (acts_fts_idx /
  # summaries_fts_idx) with a bitmap index scan — the whole point of the split.
  #
  # The header half can surface a summary-less act, but the ranking join's inner
  # `assoc(:summaries)` drops those again, so the original inner-join semantics
  # (summary-less acts are invisible) are preserved.
  defp candidate_ids(q) do
    header =
      from a in Act,
        where:
          fragment(
            "to_tsvector('portuguese', coalesce(?, '') || ' ' || coalesce(?, '') || ' ' || coalesce(?, '')) @@ websearch_to_tsquery('portuguese', ?)",
            a.title,
            a.tipo,
            a.emitter,
            ^q
          ),
        select: a.id

    body =
      from s in Summary,
        where:
          fragment(
            "to_tsvector('portuguese', coalesce(?, '') || ' ' || coalesce(?, '')) @@ websearch_to_tsquery('portuguese', ?)",
            s.plain_text,
            s.headline,
            ^q
          ),
        select: s.act_id

    union(header, ^body)
  end
end
