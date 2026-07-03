defmodule Arcada.Scraper.IngestWorkerTest do
  # async: false — mutates global app env (summarizer adapter + injected client).
  use Arcada.DataCase, async: false
  use Oban.Testing, repo: Arcada.Repo

  import Arcada.SummarizerHelpers

  alias Arcada.{Admin, Repo}
  alias Arcada.Scraper
  alias Arcada.Scraper.{Client, IngestWorker}
  alias Arcada.Register.{Edition, Act, Summary}

  @list_fixture Path.join([__DIR__, "..", "..", "support", "fixtures", "dre_list_2026-06-24.json"])

  setup do
    # Active SSH provider + stubbed runner so the inline summarize jobs persist
    # summaries without hitting the network.
    stub_ssh_runner(fn _ -> {:ok, claude_envelope("...", ["fiscal"])} end)
    provider = ssh_provider()

    {:ok, _} =
      Admin.update_settings(%{"active_provider_id" => provider.id, "active_model" => "claude-cli"})

    fixture = @list_fixture |> File.read!() |> Jason.decode!()

    Req.Test.stub(Arcada.IngestStub, fn conn ->
      if String.contains?(conn.request_path, "WB_Serie1_List"),
        do: Req.Test.json(conn, fixture),
        else: Req.Test.json(conn, %{})
    end)

    client = %{
      Client.new(req_options: [plug: {Req.Test, Arcada.IngestStub}])
      | module_version: "test",
        crf: "x",
        cookie: "c"
    }

    prev_client = Application.get_env(:arcada, :ingest_client)
    # enrich: false — the stub only serves the list call; skip per-act detail.
    Application.put_env(:arcada, :ingest_client, %{client | detail_api_version: nil})

    on_exit(fn ->
      if prev_client,
        do: Application.put_env(:arcada, :ingest_client, prev_client),
        else: Application.delete_env(:arcada, :ingest_client)
    end)

    :ok
  end

  test "ingests the date and enqueues summarization for new acts" do
    assert :ok = perform_job(IngestWorker, %{date: "2026-06-24"})

    assert Repo.aggregate(Edition, :count) == 1
    assert Repo.aggregate(Act, :count) == 17
    # SummarizeWorker jobs ran inline (testing: :inline) → 17 summaries.
    assert Repo.aggregate(Summary, :count) == 17
  end

  test "is idempotent and retry-safe on re-run" do
    assert :ok = perform_job(IngestWorker, %{date: "2026-06-24"})
    assert :ok = perform_job(IngestWorker, %{date: "2026-06-24"})

    assert Repo.aggregate(Act, :count) == 17
    # acts already summarized → no new summaries enqueued the second time.
    assert Repo.aggregate(Summary, :count) == 17
  end

  test "defaults to today's date when none given" do
    # No Série I edition published "today" in the stub's fixture (it's dated
    # 2026-06-24), but the call still succeeds — just persists that edition.
    assert :ok = perform_job(IngestWorker, %{})
    assert Repo.aggregate(Edition, :count) == 1
  end

  test "backfill/2 enqueues + runs a job per date" do
    # Inline Oban runs each enqueued IngestWorker against the stub client.
    results = Scraper.backfill(~D[2026-06-23], ~D[2026-06-24])
    assert length(results) == 2
    assert Enum.all?(results, &match?({:ok, _}, &1))
    # Both days resolve to the same fixture edition → idempotent upsert keeps 1.
    assert Repo.aggregate(Edition, :count) == 1
  end

  test "backfill skips weekends, runs newest-first, at low priority with the backfill flag" do
    # 2025-06-27 Fri, 28 Sat, 29 Sun, 30 Mon → only the two weekdays enqueue.
    results = Scraper.backfill(~D[2025-06-27], ~D[2025-06-30])
    jobs = Enum.map(results, fn {:ok, job} -> job end)

    assert Enum.map(jobs, & &1.args["date"]) == ["2025-06-30", "2025-06-27"]
    assert Enum.all?(jobs, &(&1.args["backfill"] == true))
    assert Enum.all?(jobs, &(&1.priority == 9))
  end
end
