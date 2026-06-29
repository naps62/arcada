defmodule OQueMudou.Summarizer.SummarizeWorker do
  @moduledoc """
  Async write path for summaries. Loads the act and runs either the active
  provider (auto) or a pinned provider+model (manual run, via job args), then
  persists the summary. A `{:async, _}` result is a no-op success. Re-running
  just inserts another summary, which the UI treats as a regeneration.
  """
  use Oban.Worker, queue: :summarize, max_attempts: 3

  alias OQueMudou.{Providers, Repo}
  alias OQueMudou.Register.Act
  alias OQueMudou.Summarizer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"act_id" => act_id} = args}) do
    case Repo.get(Act, act_id) do
      nil ->
        # Act was deleted before the job ran — nothing to do, don't retry.
        :ok

      %Act{} = act ->
        act |> run(args) |> handle()
    end
  end

  # A manual run pins a provider (+ optional model); otherwise use the active one.
  defp run(act, %{"provider_id" => pid} = args) when not is_nil(pid) do
    case Providers.get_provider(pid) do
      nil ->
        {:error, :provider_not_found}

      provider ->
        Summarizer.summarize(act, provider, args["model"], text_strategy: args["text_strategy"])
    end
  end

  defp run(act, _args), do: Summarizer.summarize(act)

  defp handle({:ok, _summary}), do: :ok
  defp handle({:async, _ref}), do: :ok
  defp handle({:error, reason}), do: {:error, reason}
end
