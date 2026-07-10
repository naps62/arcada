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

  @doc """
  Act ids whose header or summary text matches `query`, best match first.

  Empty for a blank query or one that reduces to only stopwords/punctuation
  (`websearch_to_tsquery` yields an empty query, which matches nothing). User
  input is passed straight to `websearch_to_tsquery`, which never raises on junk.
  """
  def ranked_ids(query) when is_binary(query) do
    case String.trim(query) do
      "" -> []
      q -> Repo.all(ranked_query(q))
    end
  end

  def ranked_ids(_), do: []

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
  defp ranked_query(q) do
    from a in Act,
      join: s in assoc(a, :summaries),
      where: a.id in subquery(candidate_ids(q)),
      group_by: a.id,
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
