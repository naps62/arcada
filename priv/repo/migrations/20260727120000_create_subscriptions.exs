defmodule Arcada.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # NULL query = the "everything" digest (no search runs). See Arcada.Subscriptions.
      add :query, :string
      add :period, :string, null: false
      add :active, :boolean, null: false, default: true
      # Last run that advanced the clock, sent or not — the next window starts
      # the day after. NULL until the first run.
      add :last_sent_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:subscriptions, [:user_id])
    # DispatchWorker scans active rows only.
    create index(:subscriptions, [:active, :last_sent_at])

    # One row per (user, query, period). NULL query needs its own partial index —
    # in a plain unique index NULLs are all distinct, so a user could stack
    # unlimited digests of the same period.
    create unique_index(:subscriptions, [:user_id, :period, :query],
             where: "query IS NOT NULL",
             name: :subscriptions_user_query_period_index
           )

    create unique_index(:subscriptions, [:user_id, :period],
             where: "query IS NULL",
             name: :subscriptions_user_digest_period_index
           )

    # A daily digest of everything would mail every publication day; the product
    # only offers daily for a query subscription (issue #95).
    create constraint(:subscriptions, :subscriptions_no_daily_digest,
             check: "query IS NOT NULL OR period <> 'diaria'"
           )
  end
end
