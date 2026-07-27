defmodule Arcada.Subscriptions.DispatchWorkerTest do
  # async: false — Oban runs the delivery jobs inline, so this exercises the
  # whole dispatch → deliver → mail chain in one process.
  use Arcada.DataCase, async: false
  use Oban.Testing, repo: Arcada.Repo

  import Arcada.AccountsFixtures
  import Arcada.RegisterFixtures
  import Arcada.SubscriptionsFixtures
  import Swoosh.TestAssertions

  alias Arcada.Subscriptions
  alias Arcada.Subscriptions.DispatchWorker

  defp digest_for(user), do: subscription_fixture(user, %{query: nil, period: :semanal})

  defp all_subscriptions, do: Repo.all(Arcada.Subscriptions.Subscription)

  defp set_cap(cap) do
    prev = Application.get_env(:arcada, Subscriptions, [])
    Application.put_env(:arcada, Subscriptions, Keyword.put(prev, :max_sends_per_run, cap))
    on_exit(fn -> Application.put_env(:arcada, Subscriptions, prev) end)
  end

  setup do
    act_fixture(%{published_at: Date.utc_today(), title: "Portaria n.º 1/2026"})
    :ok
  end

  test "runs every due subscription" do
    digest_for(user_fixture())
    digest_for(user_fixture())

    assert :ok = perform_job(DispatchWorker, %{})

    assert_email_sent(fn email -> email.subject =~ "resumo semanal" end)
    assert Enum.all?(all_subscriptions(), & &1.last_sent_at)
  end

  test "leaves a subscription whose cadence has not come round" do
    subscription = with_last_sent(digest_for(user_fixture()), Date.utc_today())
    sent_at = subscription.last_sent_at

    assert :ok = perform_job(DispatchWorker, %{})

    assert_no_email_sent()
    assert Subscriptions.get_subscription(subscription.id).last_sent_at == sent_at
  end

  # The cap exists because the mail provider has a daily quota; the overflow has
  # to wait, not fail. The oldest clock goes first — and a subscription that has
  # never run is the oldest clock there is — so nobody starves.
  test "caps a tick and leaves the rest for the next one" do
    set_cap(1)
    never_run = digest_for(user_fixture())
    stale = with_last_sent(digest_for(user_fixture()), ~D[2026-01-01])

    assert :ok = perform_job(DispatchWorker, %{})

    assert Subscriptions.get_subscription(never_run.id).last_sent_at
    assert Subscriptions.get_subscription(stale.id).last_sent_at == stale.last_sent_at
  end
end
