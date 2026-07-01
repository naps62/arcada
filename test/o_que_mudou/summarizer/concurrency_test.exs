defmodule OQueMudou.Summarizer.ConcurrencyTest do
  use OQueMudou.DataCase, async: false

  import OQueMudou.SummarizerHelpers

  alias OQueMudou.Admin
  alias OQueMudou.Repo
  alias OQueMudou.Summarizer.Concurrency

  @worker "OQueMudou.Summarizer.SummarizeWorker"

  # Insert a summarize job straight into oban_jobs in the given state, so the gate
  # (which counts executing rows) has something to count without actually running.
  # Ids ascend with insertion order, which is what the id-ordered gate keys on.
  defp job(state, args), do: Repo.insert!(%Oban.Job{worker: @worker, queue: "summarize", state: state, args: args})

  defp pinned(provider, act_id), do: %{"act_id" => act_id, "provider_id" => provider.id}

  defp set_active(provider) do
    {:ok, _} = Admin.update_settings(%{"active_provider_id" => provider.id})
    provider
  end

  describe "check/2 — pinned (manual) jobs" do
    test "runs while under the provider's limit" do
      provider = ssh_provider(%{"max_concurrency" => "2"})
      job("executing", pinned(provider, 1))
      me = job("executing", pinned(provider, 2))

      assert Concurrency.check(me, provider) == :ok
    end

    test "snoozes once the provider is at its limit" do
      provider = ssh_provider(%{"max_concurrency" => "2"})
      job("executing", pinned(provider, 1))
      job("executing", pinned(provider, 2))
      me = job("executing", pinned(provider, 3))

      assert {:snooze, _} = Concurrency.check(me, provider)
    end

    test "SSH defaults to a single concurrent session" do
      provider = ssh_provider()
      assert provider.max_concurrency == 1

      job("executing", pinned(provider, 1))
      me = job("executing", pinned(provider, 2))

      assert {:snooze, _} = Concurrency.check(me, provider)
    end

    test "only counts jobs ahead (lower id) of the caller" do
      provider = ssh_provider()
      # Caller inserted first (lowest id); the executing job after it is behind it.
      me = job("executing", pinned(provider, 1))
      job("executing", pinned(provider, 2))

      assert Concurrency.check(me, provider) == :ok
    end

    test "ignores other providers and non-executing states" do
      provider = ssh_provider()
      other = ssh_provider()

      job("executing", pinned(other, 9))
      job("available", pinned(provider, 1))
      job("completed", pinned(provider, 2))
      me = job("executing", pinned(provider, 3))

      assert Concurrency.check(me, provider) == :ok
    end
  end

  describe "check/2 — auto jobs vs the active provider" do
    test "auto jobs (no provider_id) count toward the active provider" do
      provider = ssh_provider() |> set_active()

      job("executing", %{"act_id" => 1})
      me = job("executing", pinned(provider, 2))

      assert {:snooze, _} = Concurrency.check(me, provider)
    end

    test "auto jobs don't count toward a provider that isn't active" do
      ssh_provider() |> set_active()
      other = ssh_provider()

      job("executing", %{"act_id" => 1})
      me = job("executing", pinned(other, 2))

      assert Concurrency.check(me, other) == :ok
    end
  end
end
