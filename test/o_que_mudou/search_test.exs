defmodule OQueMudou.SearchTest do
  use OQueMudou.DataCase, async: false

  alias OQueMudou.Register.{Act, Edition, Summary}
  alias OQueMudou.Search
  alias OQueMudou.Search.Index
  alias OQueMudou.Summarizer.Embeddings

  setup do
    Index.clear()
    :ok
  end

  defp act_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    edition =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "s-#{n}/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    %Act{}
    |> Act.changeset(
      Map.merge(%{edition_id: edition.id, dre_id: "s-#{n}", title: "Act #{n}"}, attrs)
    )
    |> Repo.insert!()
  end

  defp indexed_summary(act, vector) do
    summary =
      %Summary{}
      |> Summary.changeset(%{act_id: act.id, plain_text: "resumo #{act.id}", embedding: vector})
      |> Repo.insert!()

    Index.put(summary.id, act.id, vector)
    summary
  end

  defp set_embeddings(kw) do
    prev = Application.get_env(:o_que_mudou, Embeddings, [])
    Application.put_env(:o_que_mudou, Embeddings, kw)
    on_exit(fn -> Application.put_env(:o_que_mudou, Embeddings, prev) end)
  end

  # `Index`'s query→embedding cache is a process-wide singleton that outlives
  # any one test, so every test uses its own unique query text — otherwise a
  # later test could get an earlier test's cached vector instead of exercising
  # its own stub.
  defp unique_query, do: "consulta-#{System.unique_integer([:positive])}"

  test "ranks acts by cosine similarity to the query, best match first" do
    close = act_fixture()
    far = act_fixture()
    indexed_summary(close, [1.0, 0.0])
    indexed_summary(far, [0.0, 1.0])

    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    assert [%Act{id: id}, %Act{id: id2}] = Search.search(unique_query())
    assert id == close.id
    assert id2 == far.id
  end

  test "dedupes to an act's best-scoring summary when it has several" do
    act = act_fixture()
    indexed_summary(act, [0.0, 1.0])
    indexed_summary(act, [1.0, 0.0])

    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    assert [%Act{id: id}] = Search.search(unique_query())
    assert id == act.id
  end

  test "blank query returns no results without touching the embedder" do
    set_embeddings(embed_fn: fn _ -> raise "should not be called" end)
    assert Search.search("") == []
    assert Search.search("   ") == []
  end

  test "disabled embeddings server returns no results" do
    set_embeddings([])
    act = act_fixture()
    indexed_summary(act, [1.0, 0.0])

    assert Search.search(unique_query()) == []
  end

  test "embed failures degrade to no results, never crash" do
    set_embeddings(embed_fn: fn _ -> {:error, :boom} end)
    assert Search.search(unique_query()) == []
  end

  test "limit caps the result count" do
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    for _ <- 1..3 do
      act = act_fixture()
      indexed_summary(act, [1.0, 0.0])
    end

    assert length(Search.search(unique_query(), limit: 2)) == 2
  end
end
