defmodule OQueMudou.Scraper.IngestWorkerTest do
  # async: false — mutates global app env (summarizer adapter + injected client).
  use OQueMudou.DataCase, async: false
  use Oban.Testing, repo: OQueMudou.Repo

  import OQueMudou.SummarizerHelpers

  alias OQueMudou.{Admin, Repo}
  alias OQueMudou.Scraper
  alias OQueMudou.Scraper.{Client, IngestWorker}
  alias OQueMudou.Register.{Edition, Act, Summary}

  @list_fixture Path.join([__DIR__, "..", "..", "support", "fixtures", "dre_list_2026-06-24.json"])

  setup do
    # Active SSH provider + stubbed runner so the inline summarize jobs persist
    # summaries without hitting the network.
    stub_ssh_runner(fn _ -> {:ok, claude_envelope("...", ["fiscal"])} end)
    provider = ssh_provider()

    {:ok, _} =
      Admin.update_settings(%{"active_provider_id" => provider.id, "active_model" => "claude-cli"})

    fixture = @list_fixture |> File.read!() |> Jason.decode!()

    Req.Test.stub(OQueMudou.IngestStub, fn conn ->
      if String.contains?(conn.request_path, "WB_Serie1_List"),
        do: Req.Test.json(conn, fixture),
        else: Req.Test.json(conn, %{})
    end)

    client = %{
      Client.new(req_options: [plug: {Req.Test, OQueMudou.IngestStub}])
      | module_version: "test",
        crf: "x",
        cookie: "c"
    }

    prev_client = Application.get_env(:o_que_mudou, :ingest_client)
    # enrich: false — the stub only serves the list call; skip per-act detail.
    Application.put_env(:o_que_mudou, :ingest_client, %{client | detail_api_version: nil})

    on_exit(fn ->
      if prev_client,
        do: Application.put_env(:o_que_mudou, :ingest_client, prev_client),
        else: Application.delete_env(:o_que_mudou, :ingest_client)
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
end
