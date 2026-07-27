defmodule Arcada.Subscriptions do
  @moduledoc """
  Standing email subscriptions: "mail me what's new about X, every Y" (issue #95).

  Two shapes, one row. A subscription with a `query` searches its window and
  only mails when something clears the relevance floor; a subscription without
  one is the **digest** — everything published in the window, no search. Daily
  is offered only for the query shape (a daily digest of everything is the
  firehose the product exists to filter).

  `last_sent_at` is the cadence clock, not a delivery log. A run that finds
  nothing advances it too, so the next window is fresh instead of re-scanning
  the same days forever.

  Delivery lives in `Arcada.Subscriptions.DispatchWorker` (a daily cron that
  picks due rows) and `Arcada.Subscriptions.DeliverWorker` (one job per row).
  """
  import Ecto.Query

  alias Arcada.Accounts.User

  alias Arcada.Repo
  alias Arcada.Subscriptions.Subscription

  # How far back a dormant subscription may reach on its first run back, in
  # periods. See `window/2`.
  @catch_up_periods 3

  defdelegate periods, to: Subscription
  defdelegate digest_periods, to: Subscription
  defdelegate period_label(period), to: Subscription
  defdelegate period_days(period), to: Subscription

  @doc """
  Maximum standing subscriptions per account, from
  `config :arcada, :max_subscriptions_per_user` (see `config/config.exs`).

  Read at call time, never cached in a module attribute, so the cap can be
  changed by config alone.
  """
  def max_per_user, do: Application.get_env(:arcada, :max_subscriptions_per_user, 1)

  @doc """
  `n` subscriptions in Portuguese, with the noun agreeing: `1 subscrição`,
  `3 subscrições`. Single source for every place the cap is shown to a user.
  """
  def subscription_count_label(1), do: "1 subscrição"
  def subscription_count_label(n) when is_integer(n), do: "#{n} subscrições"

  @doc "Validate a period string/atom against the fixed set. Returns the atom, or `nil`."
  def fetch_period(nil), do: nil
  def fetch_period(p) when is_atom(p), do: if(p in periods(), do: p, else: nil)

  def fetch_period(p) when is_binary(p),
    do: Enum.find(periods(), &(Atom.to_string(&1) == p))

  @doc "A user's subscriptions, the digest first, then query subscriptions oldest first."
  def list_user_subscriptions(%User{id: user_id}) do
    from(s in Subscription,
      where: s.user_id == ^user_id,
      order_by: [asc_nulls_first: s.query, asc: s.id]
    )
    |> Repo.all()
  end

  @doc """
  Fetch a subscription by id with its owner preloaded, or `nil`. Used by the
  delivery job, which holds only an id and must tolerate the row having been
  deleted between dispatch and delivery.
  """
  def get_subscription(id), do: Repo.get(Subscription, id) |> Repo.preload(:user)

  @doc """
  May this subscription be mailed right now? Guards the delivery job against a
  row that was paused, or whose owner lost confirmed status, after dispatch.
  """
  def deliverable?(%Subscription{active: true, user: %User{confirmed_at: %DateTime{}}}), do: true
  def deliverable?(_subscription), do: false

  @doc "Fetch one of `user`'s subscriptions. Raises if it belongs to someone else."
  def get_user_subscription!(%User{id: user_id}, id) do
    Repo.get_by!(Subscription, id: id, user_id: user_id)
  end

  @doc """
  Create a subscription for `user`. Returns `{:error, changeset}` when the
  account is already at `max_per_user/0`, so the cap surfaces as a form error
  rather than a raise.
  """
  def create_subscription(%User{} = user, attrs) do
    changeset =
      %Subscription{user_id: user.id}
      |> Subscription.changeset(attrs)

    max = max_per_user()

    if count_for_user(user) >= max do
      {:error,
       Ecto.Changeset.add_error(
         changeset,
         :query,
         "atingiu o limite de #{subscription_count_label(max)}"
       )}
    else
      Repo.insert(changeset)
    end
  end

  @doc "Update a subscription's query/period/active flag."
  def update_subscription(%Subscription{} = subscription, attrs) do
    subscription
    |> Subscription.changeset(attrs)
    |> Repo.update()
  end

  @doc "Pause or resume a subscription without losing it."
  def set_active(%Subscription{} = subscription, active?) when is_boolean(active?) do
    update_subscription(subscription, %{active: active?})
  end

  @doc "Delete a subscription."
  def delete_subscription(%Subscription{} = subscription), do: Repo.delete(subscription)

  @doc "Form changeset for a new or existing subscription."
  def change_subscription(%Subscription{} = subscription, attrs \\ %{}) do
    Subscription.changeset(subscription, attrs)
  end

  defp count_for_user(%User{id: user_id}) do
    Repo.aggregate(from(s in Subscription, where: s.user_id == ^user_id), :count)
  end

  ## Cadence

  @doc """
  Is `subscription` due to run on `today`? True once a full period has elapsed
  since the last run — and always true for a subscription that has never run.
  Paused subscriptions are never due.
  """
  def due?(subscription, today \\ Date.utc_today())
  def due?(%Subscription{active: false}, _today), do: false
  def due?(%Subscription{last_sent_at: nil}, _today), do: true

  def due?(%Subscription{last_sent_at: sent_at, period: period}, today) do
    Date.diff(today, DateTime.to_date(sent_at)) >= period_days(period)
  end

  @doc """
  The publication-date window this run covers, as `{from, to}` (both inclusive).

  Starts the day after the last run so no act is mailed twice, and ends today.
  A subscription that has been paused or stuck for a long time would otherwise
  come back with months of acts in one email, so the window is clamped to
  #{@catch_up_periods} periods — the older backlog is skipped, not queued.
  """
  def window(subscription, today \\ Date.utc_today())

  def window(%Subscription{last_sent_at: nil, period: period}, today) do
    {Date.add(today, -(period_days(period) - 1)), today}
  end

  def window(%Subscription{last_sent_at: sent_at, period: period}, today) do
    earliest = Date.add(today, -(@catch_up_periods * period_days(period)))
    from = sent_at |> DateTime.to_date() |> Date.add(1)

    {Enum.max([from, earliest], Date), today}
  end

  @doc """
  Active subscriptions due to run on `today`, oldest clock first, capped at
  `limit`. Only confirmed accounts are included — an unverified address must
  never receive bulk mail.
  """
  def due_subscriptions(limit, today \\ Date.utc_today()) do
    from(s in Subscription,
      join: u in assoc(s, :user),
      where: s.active and not is_nil(u.confirmed_at),
      where: ^due_clause(today),
      order_by: [asc_nulls_first: s.last_sent_at, asc: s.id],
      limit: ^limit,
      preload: [user: u]
    )
    |> Repo.all()
  end

  # `due?/2` as SQL: never run, or the clock is at least one period old. Built
  # per-period from `period_days/1` rather than a CASE fragment so the cadence
  # table stays defined in exactly one place.
  defp due_clause(today) do
    Enum.reduce(periods(), dynamic(false), fn period, acc ->
      cutoff = Date.add(today, -period_days(period))

      dynamic(
        [s],
        ^acc or (s.period == ^period and fragment("?::date", s.last_sent_at) <= ^cutoff)
      )
    end)
    |> then(&dynamic([s], is_nil(s.last_sent_at) or ^&1))
  end

  @doc """
  Advance the cadence clock. Called after every run, delivered or not — see the
  module doc on why a silent run still moves the clock.
  """
  def mark_sent(%Subscription{} = subscription, at \\ DateTime.utc_now()) do
    subscription
    |> Ecto.Changeset.change(last_sent_at: DateTime.truncate(at, :second))
    |> Repo.update()
  end

  ## Unsubscribe

  @unsubscribe_salt "subscription unsubscribe"

  @doc """
  Signed, login-free token for the unsubscribe link in every email. No expiry:
  an unsubscribe link must keep working in a mailbox read a year later.
  """
  def unsubscribe_token(%Subscription{id: id}) do
    Phoenix.Token.sign(ArcadaWeb.Endpoint, @unsubscribe_salt, id)
  end

  @doc """
  Resolve an unsubscribe token to its subscription. Returns `{:ok, subscription}`,
  or `:error` for a forged/garbled token or one whose subscription is gone.
  """
  def fetch_by_unsubscribe_token(token) when is_binary(token) do
    case Phoenix.Token.verify(ArcadaWeb.Endpoint, @unsubscribe_salt, token, max_age: :infinity) do
      {:ok, id} ->
        case Repo.get(Subscription, id) do
          nil -> :error
          subscription -> {:ok, subscription}
        end

      {:error, _reason} ->
        :error
    end
  end

  def fetch_by_unsubscribe_token(_token), do: :error
end
