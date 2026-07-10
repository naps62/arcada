defmodule Arcada.Summarizer.SummarySweeperTest do
  # async: false — a stubbed global SSH runner + inline Oban execution.
  use Arcada.DataCase, async: false
  use Oban.Testing, repo: Arcada.Repo

  import Arcada.SummarizerHelpers

  alias Arcada.{Admin, Repo}
  alias Arcada.Register.{Edition, Act, Summary}
  alias Arcada.Summarizer.SummarySweeper

  setup do
    # Active SSH provider + stubbed runner, so the summarize jobs the sweeper
    # enqueues run inline (testing: :inline) and persist real summaries.
    stub_ssh_runner(fn _ -> {:ok, claude_envelope("resumo", ["fiscal"])} end)
    provider = ssh_provider()

    {:ok, _} =
      Admin.update_settings(%{
        "active_provider_id" => provider.id,
        "active_model" => "claude-cli"
      })

    edition =
      %Edition{}
      |> Edition.changeset(%{serie: "I", number: "200/2026", date: ~D[2026-06-24]})
      |> Repo.insert!()

    %{edition: edition}
  end

  defp bare_act(edition, n) do
    %Act{}
    |> Act.changeset(%{edition_id: edition.id, dre_id: "sw-#{n}", title: "Act #{n}"})
    |> Repo.insert!()
  end

  test "enqueues a summary for each un-summarized act", %{edition: edition} do
    for n <- 1..3, do: bare_act(edition, n)

    assert :ok = perform_job(SummarySweeper, %{})

    # Inline Oban ran the enqueued SummarizeWorker jobs → one summary per act.
    assert Repo.aggregate(Summary, :count) == 3
  end

  test "is a no-op when every act already has a summary", %{edition: edition} do
    act = bare_act(edition, 1)
    %Summary{} |> Summary.changeset(%{act_id: act.id, plain_text: "s"}) |> Repo.insert!()

    assert :ok = perform_job(SummarySweeper, %{})
    assert Repo.aggregate(Summary, :count) == 1
  end

  test "honours the configured batch size", %{edition: edition} do
    prev = Application.get_env(:arcada, SummarySweeper, [])
    Application.put_env(:arcada, SummarySweeper, batch: 2)
    on_exit(fn -> Application.put_env(:arcada, SummarySweeper, prev) end)

    for n <- 1..5, do: bare_act(edition, n)

    assert :ok = perform_job(SummarySweeper, %{})
    # Only the batch is summarized this tick; the rest wait for the next one.
    assert Repo.aggregate(Summary, :count) == 2
  end

  test "an act left un-summarized this tick is picked up on the next", %{edition: edition} do
    prev = Application.get_env(:arcada, SummarySweeper, [])
    Application.put_env(:arcada, SummarySweeper, batch: 2)
    on_exit(fn -> Application.put_env(:arcada, SummarySweeper, prev) end)

    for n <- 1..3, do: bare_act(edition, n)

    assert :ok = perform_job(SummarySweeper, %{})
    assert Repo.aggregate(Summary, :count) == 2

    # Next tick drains the remaining act — the sweeper keeps retrying until dry.
    assert :ok = perform_job(SummarySweeper, %{})
    assert Repo.aggregate(Summary, :count) == 3
  end
end
