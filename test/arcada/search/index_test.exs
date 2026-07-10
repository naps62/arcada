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

  defp uq(p), do: "#{p}-#{System.unique_integer([:positive])}"

  defp set_index_cfg(kw) do
    prev = Application.get_env(:arcada, Index, [])
    Application.put_env(:arcada, Index, kw)
    on_exit(fn -> Application.put_env(:arcada, Index, prev) end)
  end

  test "concurrent embed_query calls run in parallel, not serialized through one process" do
    # The embed HTTP call must not run inside the single Index GenServer, or one
    # slow request blocks every other search (#69). Two callers must be able to
    # be inside `embed_fn` at the same time — impossible if the work serializes
    # through one process. Each call announces itself and blocks until released.
    test_pid = self()

    cfg = [
      embed_fn: fn texts ->
        send(test_pid, {:in_flight, self()})

        receive do
          :proceed -> :ok
        after
          2_000 -> :ok
        end

        {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)}
      end
    ]

    t1 = Task.async(fn -> Index.embed_query(uq("c1"), cfg) end)
    t2 = Task.async(fn -> Index.embed_query(uq("c2"), cfg) end)

    assert_receive {:in_flight, p1}, 1_000
    assert_receive {:in_flight, p2}, 1_000
    assert p1 != p2

    send(p1, :proceed)
    send(p2, :proceed)

    assert Task.await(t1) == {:ok, [1.0, 0.0]}
    assert Task.await(t2) == {:ok, [1.0, 0.0]}
  end

  test "a raising embedder crashes only its own task, never the Index process" do
    # The embed HTTP runs in the caller's process, so a raise must not crash the
    # shared Index GenServer (which would cascade to every concurrent search).
    # Run it the way search does — an unlinked supervised task — and confirm the
    # crash stays contained and the index keeps serving.
    cfg = [embed_fn: fn _ -> raise "boom" end]
    index_pid = Process.whereis(Index)

    task =
      Task.Supervisor.async_nolink(Arcada.Search.TaskSupervisor, fn ->
        Index.embed_query(uq("raise"), cfg)
      end)

    assert {:exit, _} = Task.yield(task, 1_000) || Task.shutdown(task)
    assert Process.whereis(Index) == index_pid
    assert Process.alive?(index_pid)
    assert is_list(Index.all())
  end

  test "saturated embed concurrency degrades extra callers to :busy instead of queueing" do
    set_index_cfg(max_concurrent_embeds: 1)
    test_pid = self()

    cfg = [
      embed_fn: fn texts ->
        send(test_pid, {:holding, self()})

        receive do
          :proceed -> :ok
        after
          2_000 -> :ok
        end

        {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)}
      end
    ]

    holder = Task.async(fn -> Index.embed_query(uq("hold"), cfg) end)
    assert_receive {:holding, hpid}, 1_000

    # With the only slot taken, a second query returns :busy immediately rather
    # than blocking behind the in-flight one (which is how the old design piled
    # up queued callers into GenServer.call timeouts).
    assert {:error, :busy} = Index.embed_query(uq("overflow"), cfg)

    send(hpid, :proceed)
    assert {:ok, [1.0, 0.0]} = Task.await(holder)

    # Slot is released after the holder finishes: the next query succeeds.
    assert {:ok, [1.0, 0.0]} = Index.embed_query(uq("after"), cfg)
  end

  test "a killed embed caller frees its concurrency slot" do
    set_index_cfg(max_concurrent_embeds: 1)
    test_pid = self()

    cfg = [
      embed_fn: fn _ ->
        send(test_pid, {:holding, self()})
        Process.sleep(5_000)
        {:ok, [[1.0, 0.0]]}
      end
    ]

    holder = Task.async(fn -> Index.embed_query(uq("killme"), cfg) end)
    assert_receive {:holding, _}, 1_000

    # Brutally kill the in-flight caller (mirrors Task.shutdown on a search
    # timeout). The slot must free via the monitor, or the index wedges forever.
    Task.shutdown(holder, :brutal_kill)

    ok_cfg = [embed_fn: fn texts -> {:ok, Enum.map(texts, fn _ -> [1.0, 0.0] end)} end]

    assert eventually(fn -> Index.embed_query(uq("recovered"), ok_cfg) == {:ok, [1.0, 0.0]} end)
  end

  defp eventually(fun, tries \\ 20) do
    cond do
      fun.() ->
        true

      tries <= 0 ->
        false

      true ->
        Process.sleep(25)
        eventually(fun, tries - 1)
    end
  end
end
