defmodule Arcada.Subscriptions.DispatchWorker do
  @moduledoc """
  Daily cron that picks the subscriptions whose cadence has come round and
  enqueues one `DeliverWorker` per row (issue #95).

  Split in two on purpose: one search + one email per job, so a single failing
  subscription retries alone instead of taking a whole batch's worth of mail
  down with it, and Oban's queue concurrency — not this worker — sets the pace.

  `max_sends_per_run` caps how many go out per tick. Scaleway TEM allows 100
  messages a day, so an uncapped tick on a larger list would simply start
  failing partway through; the overflow instead waits and, because
  `due_subscriptions/2` orders by the oldest clock, goes out first tomorrow.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias Arcada.Subscriptions
  alias Arcada.Subscriptions.DeliverWorker

  @max_sends_per_run 80

  @impl Oban.Worker
  def perform(_job) do
    due = Subscriptions.due_subscriptions(max_sends_per_run())

    Enum.each(due, fn subscription ->
      %{subscription_id: subscription.id}
      |> DeliverWorker.new()
      |> Oban.insert()
    end)

    if due != [], do: Logger.info("Subscriptions: enqueued #{length(due)} deliveries")

    :ok
  end

  @doc "How many subscription emails one tick may enqueue."
  def max_sends_per_run do
    Application.get_env(:arcada, Arcada.Subscriptions, [])[:max_sends_per_run] ||
      @max_sends_per_run
  end
end
