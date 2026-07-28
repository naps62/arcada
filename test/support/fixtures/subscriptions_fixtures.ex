defmodule Arcada.SubscriptionsFixtures do
  @moduledoc """
  Test helpers for `Arcada.Subscriptions`.
  """
  alias Arcada.Subscriptions
  alias Arcada.Subscriptions.Subscription

  @doc "A query subscription (weekly by default). Pass `query: nil` for the digest."
  def subscription_fixture(user, attrs \\ %{}) do
    {:ok, subscription} =
      Subscriptions.create_subscription(
        user,
        Enum.into(attrs, %{query: "arrendamento", period: :semanal})
      )

    subscription
  end

  @doc """
  Insert a subscription straight to the DB, ignoring `max_per_user/0`.

  Models the accounts that already held several rows when the cap dropped to 1
  (issue #97) — they keep them. Use only where the point of the test is an
  account over the cap; anything else must go through `subscription_fixture/2`
  so the cap is exercised.
  """
  def over_cap_subscription_fixture(user, attrs \\ %{}) do
    %Subscription{user_id: user.id}
    |> Subscription.changeset(Enum.into(attrs, %{query: "arrendamento", period: :semanal}))
    |> Arcada.Repo.insert!()
  end

  @doc """
  Override the per-account subscription cap for one test, restored on exit.

  MUST only be called from an `async: false` module: `Application.put_env` is
  global, so an async test asserting the shipped default would see this value.
  """
  def set_max_per_user(max) when is_integer(max) do
    previous = Application.fetch_env(:arcada, :max_subscriptions_per_user)
    Application.put_env(:arcada, :max_subscriptions_per_user, max)

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:arcada, :max_subscriptions_per_user, value)
        :error -> Application.delete_env(:arcada, :max_subscriptions_per_user)
      end
    end)

    max
  end

  @doc "Move a subscription's cadence clock, e.g. to make it due (or not)."
  def with_last_sent(subscription, %Date{} = date) do
    {:ok, subscription} =
      Subscriptions.mark_sent(subscription, DateTime.new!(date, ~T[09:00:00], "Etc/UTC"))

    subscription
  end
end
