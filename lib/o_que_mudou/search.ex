defmodule OQueMudou.Search do
  @moduledoc """
  Semantic search over summaries (issue #27): embed the query, cosine-rank
  against every indexed summary embedding (`OQueMudou.Search.Index`), and
  return the matching acts, best match first. No pgvector — brute-force
  cosine is plenty at this scale (low thousands of summaries).
  """
  import Ecto.Query

  alias OQueMudou.{Admin, Repo}
  alias OQueMudou.Register.Act
  alias OQueMudou.Search.Index
  alias OQueMudou.Summarizer.Embeddings

  @default_limit 20

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
  The *full* ranked list of act ids for `query`, best match first — no result
  cap and no act loading. Callers paginating over the results (infinite scroll)
  embed the query once, cache this list, then page through it with `load_page/3`.

  Returns `[]` for a blank query, a disabled/unreachable embeddings server, or
  no indexed summaries — same degradation contract as `search/2`.
  """
  def ranked_ids(query) when not is_binary(query), do: []

  def ranked_ids(query) do
    query = String.trim(query)
    cfg = Admin.embeddings_config()

    with true <- query != "",
         true <- Embeddings.enabled?(cfg),
         {:ok, query_vec} <- Index.embed_query(query, cfg) do
      rank_ids(query_vec)
    else
      _ -> []
    end
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
