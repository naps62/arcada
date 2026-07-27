defmodule Arcada.Subscriptions.Subscription do
  @moduledoc """
  A standing request for act updates by email: a query and a cadence.

  `query` nil is the *digest* — "everything published in the window", no search
  run at all. A query subscription instead searches its window and only mails
  when something clears the relevance floor (see `Arcada.Subscriptions.Matcher`).

  `last_sent_at` is the clock, not a delivery log: a run that finds nothing
  advances it too, so the next window starts fresh instead of re-scanning.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Arcada.Accounts.User

  @type t :: %__MODULE__{}

  # The cadence taxonomy lives here rather than in the context: the Ecto.Enum
  # values are needed at *compile* time, and reaching into `Arcada.Subscriptions`
  # for them would make the schema and its context compile-depend on each other.
  # The context re-exports these (`Arcada.Subscriptions.periods/0` and friends).
  @periods [:diaria, :semanal, :mensal]

  @doc "The cadences a subscription can run at."
  def periods, do: @periods

  @doc "Cadences offered for the digest (no query). Daily is deliberately absent."
  def digest_periods, do: @periods -- [:diaria]

  @doc "Human (Portuguese) label for a cadence."
  def period_label(:diaria), do: "Diária"
  def period_label(:semanal), do: "Semanal"
  def period_label(:mensal), do: "Mensal"

  @doc """
  Days between runs of a cadence. `:mensal` is 30 days rather than a calendar
  month — the cadence is "roughly monthly", and a fixed day count keeps the
  due check and the window a single subtraction.
  """
  def period_days(:diaria), do: 1
  def period_days(:semanal), do: 7
  def period_days(:mensal), do: 30

  schema "subscriptions" do
    field :query, :string
    field :period, Ecto.Enum, values: @periods
    field :active, :boolean, default: true
    field :last_sent_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating/updating a subscription. `:user_id` is set by the
  context, never cast from user params.
  """
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:query, :period, :active])
    |> update_change(:query, &normalize_query/1)
    |> validate_required([:period])
    |> validate_length(:query, min: 2, max: 120)
    # The query is interpolated into an email subject. Today's mailer posts JSON
    # to an API, where a newline is just a character — but an adapter that ever
    # speaks SMTP would turn one into a header break.
    |> validate_format(:query, ~r/^[^\p{Cc}]*$/u, message: "não pode conter quebras de linha")
    |> validate_no_daily_digest()
    |> assoc_constraint(:user)
    # Both indexes are on `(user_id, …)`, but the error belongs on the field the
    # user can actually change — the query for a duplicate topic, the cadence for
    # a second digest.
    |> unique_constraint(:query,
      name: :subscriptions_user_query_period_index,
      message: "já tem uma subscrição igual"
    )
    |> unique_constraint(:period,
      name: :subscriptions_user_digest_period_index,
      message: "já tem um resumo com esta frequência"
    )
    |> check_constraint(:period,
      name: :subscriptions_no_daily_digest,
      message: "o resumo de tudo não está disponível na frequência diária"
    )
  end

  defp normalize_query(query) when is_binary(query) do
    case String.trim(query) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_query(query), do: query

  # A daily digest of everything would mail on every publication day, which is
  # the firehose the product exists to filter. Mirrored by a DB check constraint.
  defp validate_no_daily_digest(changeset) do
    query = get_field(changeset, :query)
    period = get_field(changeset, :period)

    if is_nil(query) and period == :diaria do
      add_error(
        changeset,
        :period,
        "o resumo de tudo não está disponível na frequência diária"
      )
    else
      changeset
    end
  end
end
