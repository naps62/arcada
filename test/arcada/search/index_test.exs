defmodule Arcada.Search.IndexTest do
  use Arcada.DataCase, async: false

  alias Arcada.Register.{Act, Edition, Summary}
  alias Arcada.Search.Index

  setup do
    Index.clear()
    :ok
  end

  defp act_fixture do
    n = System.unique_integer([:positive])

    edition =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "1-#{n}/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    %Act{}
    |> Act.changeset(%{edition_id: edition.id, dre_id: "idx-#{n}", title: "Ato #{n}"})
    |> Repo.insert!()
  end

  test "put/3 and all/0 round-trip" do
    act = act_fixture()
    Index.put(1, act.id, [1.0, 0.0])
    assert Index.all() == [{1, act.id, [1.0, 0.0]}]
  end

  test "reload/0 loads every summary with a non-nil embedding, skipping nil ones" do
    act = act_fixture()

    embedded =
      %Summary{}
      |> Summary.changeset(%{act_id: act.id, plain_text: "x", embedding: [1.0, 2.0]})
      |> Repo.insert!()

    %Summary{}
    |> Summary.changeset(%{act_id: act.id, plain_text: "y"})
    |> Repo.insert!()

    Index.reload()

    assert Index.all() == [{embedded.id, act.id, [1.0, 2.0]}]
  end

  test "embed_query caches by query text" do
    test_pid = self()

    cfg = [
      embed_fn: fn texts ->
        send(test_pid, {:embed_call, texts})
        {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)}
      end
    ]

    query = "consulta-#{System.unique_integer([:positive])}"

    assert Index.embed_query(query, cfg) == {:ok, [1.0, 0.0]}
    assert Index.embed_query(query, cfg) == {:ok, [1.0, 0.0]}

    assert_received {:embed_call, _}
    refute_received {:embed_call, _}
  end

  test "embed_query applies the configured query_prefix" do
    test_pid = self()

    cfg = [
      query_prefix: "search_query: ",
      embed_fn: fn texts ->
        send(test_pid, {:embed_call, texts})
        {:ok, Enum.map(texts, fn _ -> [1.0] end)}
      end
    ]

    Index.embed_query("consulta-#{System.unique_integer([:positive])}", cfg)
    assert_received {:embed_call, ["search_query: consulta-" <> _]}
  end

  test "embed_query surfaces embed errors without caching them" do
    cfg = [embed_fn: fn _ -> {:error, :boom} end]
    query = "erro-#{System.unique_integer([:positive])}"
    assert {:error, :boom} = Index.embed_query(query, cfg)
  end
end
