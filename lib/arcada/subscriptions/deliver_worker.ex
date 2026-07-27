defmodule Arcada.Subscriptions.DeliverWorker do
  @moduledoc """
  One subscription's run: search its window, mail what it found, advance its
  clock (issue #95).

  A run that finds nothing still advances the clock — the alternative is a
  window that grows without bound until something finally matches, and then one
  email covering months. So "no matches" is a completed run, not a skipped one.

  The clock moves only *after* a successful send, so a bounced/failed delivery
  retries against the same window rather than silently losing it. That ordering
  is why `unique` is set: it stops a second dispatch from queueing the same
  subscription while the first attempt is still in flight.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: {20, :hours}]

  require Logger

  alias Arcada.Register
  alias Arcada.Subscriptions
  alias Arcada.Subscriptions.{Matcher, Notifier, Subscription}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subscription_id" => id}}) do
    case Subscriptions.get_subscription(id) do
      nil -> :ok
      subscription -> run(subscription)
    end
  end

  defp run(subscription) do
    if Subscriptions.deliverable?(subscription) do
      deliver(subscription, Subscriptions.window(subscription))
    else
      :ok
    end
  end

  defp deliver(subscription, window) do
    case Matcher.matches(subscription, window) do
      [] ->
        advance(subscription)

      acts ->
        case Notifier.deliver(
               subscription,
               subscription.user,
               acts,
               window,
               total(subscription, window)
             ) do
          {:ok, _email} ->
            advance(subscription)

          {:error, reason} ->
            Logger.warning("Subscription #{subscription.id} delivery failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  # Only the digest is capped, so only the digest needs the window's true size.
  defp total(%Subscription{query: nil}, {window_from, window_to}),
    do: Register.count_acts_published_between(window_from, window_to)

  defp total(_subscription, _window), do: nil

  defp advance(subscription) do
    with {:ok, _subscription} <- Subscriptions.mark_sent(subscription), do: :ok
  end
end
