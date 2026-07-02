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

  # A summary with real body text (so FTS can match it), also indexed for
  # semantic search under `vector`.
  defp indexed_summary(act, text, vector) do
    summary =
      %Summary{}
      |> Summary.changeset(%{act_id: act.id, plain_text: text, embedding: vector})
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

  test "ranked_ids returns every match ranked, uncapped, without loading acts" do
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    close = act_fixture()
    far = act_fixture()
    indexed_summary(close, [1.0, 0.0])
    indexed_summary(far, [0.0, 1.0])

    assert Search.ranked_ids(unique_query()) == [close.id, far.id]
  end

  test "ranked_ids dedupes an act to its best-scoring summary" do
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    act = act_fixture()
    indexed_summary(act, [0.0, 1.0])
    indexed_summary(act, [1.0, 0.0])

    assert Search.ranked_ids(unique_query()) == [act.id]
  end

  test "ranked_ids degrades to [] on blank/disabled/failed embeds" do
    assert Search.ranked_ids("") == []
    assert Search.ranked_ids(nil) == []

    set_embeddings([])
    assert Search.ranked_ids(unique_query()) == []
  end

  test "load_page windows a ranked id list, preserving order" do
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    acts = for _ <- 1..5, do: act_fixture()
    for a <- acts, do: indexed_summary(a, [1.0, 0.0])
    ids = Search.ranked_ids(unique_query())

    first = Search.load_page(ids, 0, 2)
    second = Search.load_page(ids, 2, 2)

    assert length(first) == 2
    assert length(second) == 2
    assert Enum.map(first, & &1.id) == Enum.take(ids, 2)
    assert Enum.map(second, & &1.id) == Enum.slice(ids, 2, 2)
    # Windows don't overlap and stay in rank order.
    assert Enum.map(first ++ second, & &1.id) == Enum.take(ids, 4)
    # Past the end is empty, never a crash.
    assert Search.load_page(ids, 99, 2) == []
  end

  # --- Hybrid fusion (issue #28) -------------------------------------------

  test "an exact law number in the title surfaces the act even when semantic ranks it last" do
    target = act_fixture(%{title: "Lei n.º 23/2023 das finanças públicas"})
    noise = act_fixture(%{title: "Outro diploma qualquer"})

    # Query embeds to [1.0, 0.0]: semantic puts `noise` (cosine 1) above `target`
    # (cosine 0). FTS matches only `target` on the exact number, so RRF lifts it
    # to the top of the fused list.
    indexed_summary(target, "corpo do resumo", [0.0, 1.0])
    indexed_summary(noise, "corpo do resumo", [1.0, 0.0])
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)

    ids = Search.ranked_ids("Lei 23/2023")

    assert hd(ids) == target.id
    assert noise.id in ids
  end

  test "FTS matches the summary body, not just the act header" do
    target = act_fixture(%{title: "Act sem pistas"})
    indexed_summary(target, "novo apoio ao arrendamento jovem", [0.0, 1.0])
    set_embeddings([])

    assert Search.ranked_ids("arrendamento") == [target.id]
  end

  test "degrades to FTS-only when the embeddings server is down" do
    set_embeddings([])
    target = act_fixture(%{title: "Decreto-Lei n.º 10-A/2022"})
    indexed_summary(target, "texto do resumo", [1.0, 0.0])

    # Semantic can't run (server disabled) yet the exact number still lands it.
    assert Search.ranked_ids("10-A/2022") == [target.id]
    assert [%Act{id: id}] = Search.search("10-A/2022")
    assert id == target.id
  end

  test "semantic?: false runs FTS-only without touching the embedder (#32)" do
    # The rate-limited path: the embedder must not be called at all, yet FTS
    # still returns the exact-term match so search stays useful.
    set_embeddings(embed_fn: fn _ -> raise "embedder must not run when semantic?: false" end)
    target = act_fixture(%{title: "Lei n.º 42/2026 do arrendamento"})
    indexed_summary(target, "texto do resumo com arrendamento", [1.0, 0.0])

    assert Search.ranked_ids("arrendamento", semantic?: false) == [target.id]
  end

  test "an exact-term match still ranks when its summary has no embedding at all" do
    set_embeddings(embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end)
    target = act_fixture(%{title: "Portaria n.º 99/2026"})

    # No embedding → absent from the semantic index, but FTS still finds it.
    %Summary{}
    |> Summary.changeset(%{act_id: target.id, plain_text: "sem vetor"})
    |> Repo.insert!()

    assert Search.ranked_ids("99/2026") == [target.id]
  end

  test "a query with no text match and no embeddings server yields nothing" do
    set_embeddings([])
    act = act_fixture(%{title: "Act qualquer"})
    indexed_summary(act, "resumo sem o termo", [1.0, 0.0])

    assert Search.ranked_ids("termo-inexistente-xyz") == []
  end
end
