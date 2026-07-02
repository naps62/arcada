defmodule OQueMudou.Search do
  @moduledoc """
  Hybrid search over summaries: fuse semantic ranking (issue #27) with Postgres
  full-text search (issue #28) so both meaning and exact terms surface the act.

  - **Semantic** (`OQueMudou.Search.Index`): embed the query, cosine-rank against
    every indexed summary embedding. Great on topics, weak on law numbers and
    rare tokens. No pgvector — brute-force cosine is plenty at this scale.
  - **FTS** (`OQueMudou.Search.FTS`): `portuguese` `tsvector` over the act header
    + summary body. Catches "Lei 23/2023" and other exact identifiers embeddings
    blur.

  The two run in parallel and merge with Reciprocal Rank Fusion (`score =
  Σ 1/(k+rank)`, `k = #{60}`) — rank-only, so no score calibration or weight
  tuning. Either half may be empty (embeddings server down → FTS-only; no text
  match → semantic-only), so search degrades gracefully instead of failing.
  """
  import Ecto.Query

  alias OQueMudou.{Admin, Repo}
  alias OQueMudou.Register.Act
  alias OQueMudou.Search.{FTS, Index}
  alias OQueMudou.Summarizer.Embeddings

  @default_limit 20
  # Reciprocal Rank Fusion constant. 60 is the value from the original RRF paper
  # (Cormack et al.); it damps the top ranks so a strong hit in one list can't
  # wholly dominate a solid pair of mid hits in both.
  @rrf_k 60

  @doc "The page size used by paginated callers (see `ranked_ids/1` + `load_page/3`)."
  def page_size, do: @default_limit

  @doc """
  Rank acts by how close their best-matching summary is to `query`. `opts[:limit]`
  caps the result count (default 20).

  Returns `[]` for a blank query, a disabled/unreachable embeddings server, or
  no indexed summaries — search degrades to "no results", never a crash.
  """
  def search(query, opts \\ [])
  def search(query, _opts) when not is_binary(query), do: []

  def search(query, opts) do
    query
    |> ranked_ids()
    |> Enum.take(Keyword.get(opts, :limit, @default_limit))
    |> load_acts()
  end

  @doc """
  The *full* fused ranked list of act ids for `query`, best match first — no
  result cap and no act loading. Callers paginating over the results (infinite
  scroll) run this once, cache the list, then page it with `load_page/3`.

  Runs semantic + FTS concurrently and merges them with RRF. Returns `[]` only
  when *both* halves are empty (blank query, or the embeddings server is down
  *and* nothing matches the text) — a down embeddings server degrades to
  FTS-only, a no-text-match query to semantic-only, neither crashes.

  `opts[:semantic?]` (default `true`) gates the expensive embedding leg. Pass
  `false` to run FTS-only — this is how a rate-limited caller (#32) still gets
  results without spending the GPU. FTS-only is the same graceful degradation the
  fusion already does when the embeddings server is down.
  """
  def ranked_ids(query, opts \\ [])
  def ranked_ids(query, _opts) when not is_binary(query), do: []

  def ranked_ids(query, opts) do
    query = String.trim(query)

    if query == "" do
      []
    else
      if Keyword.get(opts, :semantic?, true) do
        # Semantic is the slow leg (embed the query over the network); run it in a
        # task while FTS hits Postgres in this process. The task only touches the
        # in-memory index + embeddings client — no Repo — so it's sandbox-safe.
        cfg = Admin.embeddings_config()
        semantic = Task.async(fn -> semantic_ids(query, cfg) end)
        fts = FTS.ranked_ids(query)

        rrf([Task.await(semantic, 35_000), fts])
      else
        FTS.ranked_ids(query)
      end
    end
  end

  defp semantic_ids(query, cfg) do
    with true <- Embeddings.enabled?(cfg),
         {:ok, query_vec} <- Index.embed_query(query, cfg) do
      rank_ids(query_vec)
    else
      _ -> []
    end
  end

  # Reciprocal Rank Fusion: each list votes 1/(k+rank) (rank 1-based) for the
  # ids it ranks; sum the votes, best total first. Ids in both lists compound;
  # a stable id tiebreak keeps the order deterministic.
  defp rrf(ranked_lists) do
    ranked_lists
    |> Enum.reduce(%{}, fn ids, scores ->
      ids
      |> Enum.with_index(1)
      |> Enum.reduce(scores, fn {id, rank}, scores ->
        Map.update(scores, id, 1.0 / (@rrf_k + rank), &(&1 + 1.0 / (@rrf_k + rank)))
      end)
    end)
    |> Enum.sort_by(fn {id, score} -> {-score, id} end)
    |> Enum.map(fn {id, _score} -> id end)
  end

  @doc """
  Load the acts for one window of an already-ranked id list (from `ranked_ids/1`),
  preserving rank order. `offset`/`limit` slice the window; out-of-range slices
  return `[]`.
  """
  def load_page(ranked_ids, offset, limit) do
    ranked_ids |> Enum.slice(offset, limit) |> load_acts()
  end

  defp rank_ids(query_vec) do
    Index.all()
    |> Enum.map(fn {_summary_id, act_id, vec} -> {act_id, Embeddings.cosine(query_vec, vec)} end)
    |> Enum.sort_by(fn {_act_id, score} -> score end, :desc)
    # An act can have several (re-run) summaries indexed; keep its best score.
    |> Enum.uniq_by(fn {act_id, _score} -> act_id end)
    |> Enum.map(fn {act_id, _score} -> act_id end)
  end

  defp load_acts([]), do: []

  defp load_acts(ids) do
    by_id =
      from(a in Act, where: a.id in ^ids, preload: [:edition, :summaries])
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    ids |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1)
  end
end
