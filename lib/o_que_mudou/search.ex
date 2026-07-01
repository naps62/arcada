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

  @doc """
  Rank acts by how close their best-matching summary is to `query`. `opts[:limit]`
  caps the result count (default 20).

  Returns `[]` for a blank query, a disabled/unreachable embeddings server, or
  no indexed summaries — search degrades to "no results", never a crash.
  """
  def search(query, opts \\ [])
  def search(query, _opts) when not is_binary(query), do: []

  def search(query, opts) do
    query = String.trim(query)
    cfg = Admin.embeddings_config()

    with true <- query != "",
         true <- Embeddings.enabled?(cfg),
         {:ok, query_vec} <- Index.embed_query(query, cfg) do
      rank(query_vec, Keyword.get(opts, :limit, @default_limit))
    else
      _ -> []
    end
  end

  defp rank(query_vec, limit) do
    Index.all()
    |> Enum.map(fn {_summary_id, act_id, vec} -> {act_id, Embeddings.cosine(query_vec, vec)} end)
    |> Enum.sort_by(fn {_act_id, score} -> score end, :desc)
    # An act can have several (re-run) summaries indexed; keep its best score.
    |> Enum.uniq_by(fn {act_id, _score} -> act_id end)
    |> Enum.take(limit)
    |> load_acts()
  end

  defp load_acts([]), do: []

  defp load_acts(ranked) do
    ids = Enum.map(ranked, &elem(&1, 0))

    by_id =
      from(a in Act, where: a.id in ^ids, preload: [:edition, :summaries])
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    ids |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1)
  end
end
