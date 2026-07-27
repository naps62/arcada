defmodule Arcada.SubscriptionsFixtures do
  @moduledoc """
  Test helpers for `Arcada.Subscriptions`.
  """
  alias Arcada.Subscriptions

  @doc "A query subscription (weekly by default). Pass `query: nil` for the digest."
  def subscription_fixture(user, attrs \\ %{}) do
    {:ok, subscription} =
      Subscriptions.create_subscription(
        user,
        Enum.into(attrs, %{query: "arrendamento", period: :semanal})
      )

    subscription
  end

  @doc "Move a subscription's cadence clock, e.g. to make it due (or not)."
  def with_last_sent(subscription, %Date{} = date) do
    {:ok, subscription} =
      Subscriptions.mark_sent(subscription, DateTime.new!(date, ~T[09:00:00], "Etc/UTC"))

    subscription
  end
end
