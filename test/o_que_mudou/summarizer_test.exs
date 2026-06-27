defmodule OQueMudou.SummarizerTest do
  # async: false — these tests mutate global application env (the adapter).
  use OQueMudou.DataCase, async: false
  use Oban.Testing, repo: OQueMudou.Repo

  alias OQueMudou.Repo
  alias OQueMudou.Register.{Edition, Act, Summary}
  alias OQueMudou.Summarizer
  alias OQueMudou.Summarizer.SummarizeWorker

  # A fake adapter that returns a synchronous result, to exercise the write path
  # without hitting the network.
  defmodule FakeAdapter do
    @behaviour OQueMudou.Summarizer.Adapter
    @impl true
    def summarize(_act) do
      {:ok,
       %{
         plain_text: "Em linguagem simples: muda X para Y.",
         domains: [:fiscal, :trabalho],
         model: "fake-model",
         prompt_version: "test"
       }}
    end
  end

  defmodule FailingAdapter do
    @behaviour OQueMudou.Summarizer.Adapter
    @impl true
    def summarize(_act), do: {:error, :boom}
  end

  defp set_adapter(adapter) do
    prev = Application.get_env(:o_que_mudou, Summarizer, [])
    Application.put_env(:o_que_mudou, Summarizer, Keyword.put(prev, :adapter, adapter))
    on_exit(fn -> Application.put_env(:o_que_mudou, Summarizer, prev) end)
  end

  defp act_fixture do
    edition =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "120/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    %Act{}
    |> Act.changeset(%{
      edition_id: edition.id,
      dre_id: "1138160247",
      title: "Decreto-Lei n.º 1/2026"
    })
    |> Repo.insert!()
  end

  describe "adapter/0" do
    test "defaults to Manual" do
      set_adapter(:manual)
      assert Summarizer.adapter() == OQueMudou.Summarizer.Adapters.Manual
    end

    test "resolves known keys and explicit modules" do
      set_adapter(:api)
      assert Summarizer.adapter() == OQueMudou.Summarizer.Adapters.Api
      set_adapter(FakeAdapter)
      assert Summarizer.adapter() == FakeAdapter
    end
  end

  describe "summarize/1" do
    test "manual adapter defers and writes nothing" do
      set_adapter(:manual)
      assert {:async, :manual} = Summarizer.summarize(act_fixture())
      assert Repo.aggregate(Summary, :count) == 0
    end

    test "a synchronous adapter result is persisted with defaults" do
      set_adapter(FakeAdapter)
      assert {:ok, summary} = Summarizer.summarize(act_fixture())

      assert summary.plain_text =~ "linguagem simples"
      assert summary.domains == [:fiscal, :trabalho]
      assert summary.model == "fake-model"
      assert summary.prompt_version == "test"
      assert summary.status == :unreviewed
      assert summary.generated_at
      assert is_nil(summary.validated_at)
    end

    test "propagates adapter errors" do
      set_adapter(FailingAdapter)
      assert {:error, :boom} = Summarizer.summarize(act_fixture())
    end
  end

  describe "create_summary/2 (manual backfill)" do
    test "inserts and stamps generated_at" do
      act = act_fixture()

      assert {:ok, summary} =
               Summarizer.create_summary(act, %{
                 plain_text: "Resumo manual.",
                 domains: [:habitação],
                 model: "manual",
                 prompt_version: "human"
               })

      assert summary.act_id == act.id
      assert summary.generated_at
    end
  end

  describe "SummarizeWorker (async write path)" do
    test "manual adapter: job succeeds and writes nothing" do
      set_adapter(:manual)
      act = act_fixture()
      assert :ok = perform_job(SummarizeWorker, %{act_id: act.id})
      assert Repo.aggregate(Summary, :count) == 0
    end

    test "synchronous adapter: job writes a summary" do
      set_adapter(FakeAdapter)
      act = act_fixture()
      assert :ok = perform_job(SummarizeWorker, %{act_id: act.id})

      summary = Repo.one!(Summary)
      assert summary.act_id == act.id
      assert summary.domains == [:fiscal, :trabalho]
    end

    test "missing act is a no-op success (no retry)" do
      assert :ok = perform_job(SummarizeWorker, %{act_id: 999_999})
    end

    test "adapter error surfaces so the job retries" do
      set_adapter(FailingAdapter)
      act = act_fixture()
      assert {:error, :boom} = perform_job(SummarizeWorker, %{act_id: act.id})
    end
  end

  describe "enqueue/1" do
    test "enqueues a job for the act" do
      set_adapter(:manual)
      act = act_fixture()
      assert {:ok, %Oban.Job{}} = Summarizer.enqueue(act)
    end
  end
end
