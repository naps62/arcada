defmodule Arcada.Summarizer.SummarizeWorker do
  @moduledoc """
  Async write path for summaries. Loads the act and runs either the active
  provider (auto) or a pinned provider+model (manual run, via job args), then
  persists the summary. A `{:async, _}` result is a no-op success. Re-running
  just inserts another summary, which the UI treats as a regeneration.

  Each job is gated by its provider's `max_concurrency` (`Summarizer.Concurrency`)
  before running, so the shared queue honours per-provider limits (issue #22).
  """
  use Oban.Worker, queue: :summarize, max_attempts: 3

  alias Arcada.{Admin, Providers, Repo}
  alias Arcada.Providers.Provider
  alias Arcada.Register.Act
  alias Arcada.Summarizer
  alias Arcada.Summarizer.Concurrency

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"act_id" => act_id} = args} = job) do
    case Repo.get(Act, act_id) do
      nil ->
        # Act was deleted before the job ran — nothing to do, don't retry.
        :ok

      %Act{} = act ->
        case gate(job, args) do
          :ok -> act |> run(args) |> handle()
          {:snooze, _} = snooze -> snooze
        end
    end
  end

  # Throttle per the provider this job will actually use. With no resolvable
  # provider (auto run + no active provider, or a pinned id that's gone) there's
  # nothing to gate — `run/2` handles those as a no-op / error.
  defp gate(job, args) do
    case effective_provider(args) do
      %Provider{} = provider -> Concurrency.check(job, provider)
      nil -> :ok
    end
  end

  defp effective_provider(%{"provider_id" => pid}) when not is_nil(pid),
    do: Providers.get_provider(pid)

  defp effective_provider(_args), do: Admin.active_provider()

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
