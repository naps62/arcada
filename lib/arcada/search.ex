defmodule Arcada.Search do
  @moduledoc """
  Hybrid search over summaries: fuse semantic ranking (issue #27) with Postgres
  full-text search (issue #28) so both meaning and exact terms surface the act.

  - **Semantic** (`Arcada.Search.Index`): embed the query, cosine-rank against
    every indexed summary embedding. Great on topics, weak on law numbers and
    rare tokens. No pgvector — brute-force cosine is plenty at this scale.
  - **FTS** (`Arcada.Search.FTS`): `portuguese` `tsvector` over the act header
    + summary body. Catches "Lei 23/2023" and other exact identifiers embeddings
    blur.

  The two run in parallel and merge with Reciprocal Rank Fusion (`score =
  Σ 1/(k+rank)`, `k = #{60}`) — rank-only, so no score calibration or weight
  tuning. Either half may be empty (embeddings server down → FTS-only; no text
  match → semantic-only), so search degrades gracefully instead of failing.
  """
  import Ecto.Query

  alias Arcada.{Admin, RateLimit, Repo}
  alias Arcada.Register.Act
  alias Arcada.Search.{FTS, Index}
  alias Arcada.Summarizer.Embeddings

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
  The visitor-facing search entry point (#32, #50): the whole "rate-limited
  callers degrade to FTS-only" policy in one place, so it lives in the context
  instead of inline in a LiveView and is testable as a plain function call.

  Charges `identity`'s semantic-search budget; on an over-budget deny it degrades
  to FTS-only (still useful, no GPU spend) and flags it. Then runs the fused
  ranking, loads the first result window, and emits the `[:arcada, :search,
  :query]` telemetry event tagged by tier + degradation.

  `identity` is a `{tier, key}` rate-limit bucket (see `Arcada.RateLimit`).
  Returns `{results, ids, degraded?}`:

    * `ids` — the full fused ranked id list; callers cache it and page it with
      `load_page/3` (infinite scroll re-pages the cache — it neither re-charges
      the limit nor re-embeds)
    * `results` — the first loaded window (`page_size/0` acts)
    * `degraded?` — true when the rate limit forced FTS-only, so the caller can
      show the "sign in for smarter search" nudge

  The caller derives the identity (which tier a visitor earns is a product rule)
  and renders what it gets back.
  """
  @spec for_visitor(term(), RateLimit.identity()) :: {[Act.t()], [term()], boolean()}
  def for_visitor(query, {tier, _key} = identity) do
    degraded? =
      case RateLimit.search_semantic(identity) do
        :ok -> false
        {:deny, _retry_ms} -> true
      end

    ids = ranked_ids(query, semantic?: not degraded?)
    results = load_page(ids, 0, page_size())

    :telemetry.execute(
      [:arcada, :search, :query],
      %{count: 1},
      %{tier: tier, degraded: degraded?}
    )

    {results, ids, degraded?}
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
  # ids it ranks; sum the votes, best total first. Ids in both lists compound.
  # A bounded recency boost then breaks near-ties toward fresher acts, and a
  # stable id tiebreak keeps the order deterministic.
  defp rrf(ranked_lists) do
    ranked_lists
    |> Enum.reduce(%{}, fn ids, scores ->
      ids
      |> Enum.with_index(1)
      |> Enum.reduce(scores, fn {id, rank}, scores ->
        Map.update(scores, id, 1.0 / (@rrf_k + rank), &(&1 + 1.0 / (@rrf_k + rank)))
      end)
    end)
    |> apply_recency()
    |> Enum.sort_by(fn {id, score} -> {-score, id} end)
    |> Enum.map(fn {id, _score} -> id end)
  end

  # Multiply each fused score by a bounded recency factor in `[1, 1+β]`: the
  # newest acts get `1+β`, older ones decay toward the neutral `1.0` with a
  # configurable half-life. Because the factor is bounded, recency only reorders
  # near-ties — a relevance gap wider than a factor of `(1+β)` still wins, and a
  # recent-but-irrelevant act (deep in the list) can't be lifted into the page.
  # `β = 0` (the default) short-circuits to the pre-recency behaviour exactly.
  # Acts with an unknown `published_at` take the neutral factor.
  defp apply_recency(scores) do
    case recency_config() do
      {beta, _half_life} when beta <= 0.0 or map_size(scores) == 0 ->
        scores

      {beta, half_life} ->
        dates = published_ats(Map.keys(scores))
        today = Date.utc_today()

        Map.new(scores, fn {id, score} ->
          {id, score * recency_factor(dates[id], today, beta, half_life)}
        end)
    end
  end

  defp recency_factor(%Date{} = published, today, beta, half_life) do
    age_days = max(Date.diff(today, published), 0)
    1.0 + beta * :math.pow(0.5, age_days / half_life)
  end

  defp recency_factor(_no_date, _today, _beta, _half_life), do: 1.0

  # `β` (max fractional boost for a brand-new act, 0.0 = off) and the half-life in
  # days over which that boost decays. Tunable live via `config :arcada, #{inspect(__MODULE__)}`.
  defp recency_config do
    cfg = Application.get_env(:arcada, __MODULE__, [])
    {cfg[:recency_beta] || 0.0, cfg[:recency_half_life_days] || 180}
  end

  defp published_ats(ids) do
    from(a in Act, where: a.id in ^ids, select: {a.id, a.published_at})
    |> Repo.all()
    |> Map.new()
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
    |> above_relevance_floor()
    |> Enum.map(fn {act_id, _score} -> act_id end)
  end

  # Drop the long tail of weakly-related acts: keep only those whose cosine clears
  # `max(min_score, ratio × top_score)`. The floor is *relative to the top hit*
  # because bge-m3's absolute scores swing by query (a weak query like "ronaldo"
  # tops out ~0.39, a broad one ~0.64), so no fixed cutoff fits both — a fixed 0.40
  # wipes the weak query yet leaves hundreds for the broad one. The small absolute
  # `min_score` still floors out nonsense (nothing clears it → no results). FTS
  # matches are unaffected: they re-enter through the FTS list in `rrf/1`, so
  # exact-term hits survive a low cosine. `ratio <= 0` (default) disables the floor,
  # preserving the show-everything behaviour. Expects `scored` sorted best-first.
  defp above_relevance_floor([]), do: []

  defp above_relevance_floor([{_id, top} | _] = scored) do
    {ratio, min_score} = relevance_config()

    if ratio <= 0.0 do
      scored
    else
      floor = max(min_score, ratio * top)
      Enum.take_while(scored, fn {_id, score} -> score >= floor end)
    end
  end

  # `ratio` (keep acts within this fraction of the top cosine, 0.0 = floor off) and
  # the absolute `min_score` (nonsense-query backstop). Tunable live via
  # `config :arcada, #{inspect(__MODULE__)}`.
  defp relevance_config do
    cfg = Application.get_env(:arcada, __MODULE__, [])
    {cfg[:relevance_ratio] || 0.0, cfg[:min_relevance_score] || 0.0}
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
