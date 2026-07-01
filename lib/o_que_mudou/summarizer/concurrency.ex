defmodule OQueMudou.Summarizer.Concurrency do
  @moduledoc """
  Per-provider concurrency gate for the summarize queue (issue #22).

  Every summarize job shares one Oban queue (its width is just the global pool
  ceiling), but each provider declares its own `max_concurrency`. Before doing
  work, a job counts how many summarize jobs for the *same provider* are already
  executing and `{:snooze, _}`s itself when the provider is at capacity — so SSH
  stays at one concurrent session while API providers fan out, and switching the
  active provider re-tunes the limit with no restart.

  The count comes straight from `oban_jobs` (the source of truth), scoped to the
  provider and to jobs with a **lower id** than the caller. That id ordering
  makes the gate deterministic: when several jobs for one provider start at once,
  only the lowest-id ones (up to the limit) proceed and the rest snooze, instead
  of all of them mutually snoozing (livelock) or all slipping through (the
  classic semaphore race). Snoozed jobs aren't `executing`, so they never block
  others — no starvation.

  A job's effective provider is its pinned `provider_id` (manual run) or, absent
  that, the active provider (auto run). Auto jobs carry no `provider_id`, so they
  only count toward the *currently* active provider.
  """
  import Ecto.Query

  alias OQueMudou.{Admin, Repo}
  alias OQueMudou.Providers.Provider

  @worker "OQueMudou.Summarizer.SummarizeWorker"
  @snooze_seconds 5

  @doc """
  `:ok` to run now, or `{:snooze, seconds}` when `provider` already has its
  `max_concurrency` worth of summarize jobs executing ahead of this one.
  """
  def check(%Oban.Job{} = job, %Provider{} = provider) do
    if running_ahead(job, provider) >= Provider.max_concurrency(provider),
      do: {:snooze, @snooze_seconds},
      else: :ok
  end

  defp running_ahead(job, provider), do: job |> ahead_query(provider) |> Repo.aggregate(:count)

  defp ahead_query(%Oban.Job{id: id}, %Provider{id: pid}) do
    from(j in Oban.Job, where: j.state == "executing" and j.worker == @worker)
    |> ahead_of(id)
    |> for_provider(pid)
  end

  # The id-ordered tiebreak — only count jobs *ahead* of this one. A nil id (Oban's
  # inline test engine, which never persists an executing row anyway) skips it.
  defp ahead_of(query, nil), do: query
  defp ahead_of(query, id), do: where(query, [j], j.id < ^id)

  defp for_provider(query, pid) do
    if active_provider_id() == pid do
      # Auto jobs (no provider_id) run against the active provider, so they count
      # toward it alongside jobs explicitly pinned to it.
      where(
        query,
        [j],
        fragment("(?->>'provider_id')::bigint = ?", j.args, ^pid) or
          fragment("?->>'provider_id' IS NULL", j.args)
      )
    else
      where(query, [j], fragment("(?->>'provider_id')::bigint = ?", j.args, ^pid))
    end
  end

  defp active_provider_id do
    case Admin.active_provider() do
      %Provider{id: id} -> id
      _ -> nil
    end
  end
end
