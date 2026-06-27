defmodule OQueMudou.Summarizer.SummarizeWorker do
  @moduledoc """
  Async write path for summaries. Loads the act, runs the configured adapter,
  and persists the summary. A `{:async, _}` adapter result (e.g. `manual`) is a
  no-op success — the human backfills later. Idempotent enough for retries:
  re-running just inserts another summary, which the UI treats as a regeneration.
  """
  use Oban.Worker, queue: :summarize, max_attempts: 3

  alias OQueMudou.Repo
  alias OQueMudou.Register.Act
  alias OQueMudou.Summarizer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"act_id" => act_id}}) do
    case Repo.get(Act, act_id) do
      nil ->
        # Act was deleted before the job ran — nothing to do, don't retry.
        :ok

      %Act{} = act ->
        case Summarizer.summarize(act) do
          {:ok, _summary} -> :ok
          {:async, _ref} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
