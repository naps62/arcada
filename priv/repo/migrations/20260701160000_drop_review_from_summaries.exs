defmodule Arcada.Repo.Migrations.DropReviewFromSummaries do
  use Ecto.Migration

  # The provenance/review feature (unreviewed → community → verified, plus the
  # human `validated_at` safety net) is shelved. Drop the columns that backed it.
  def up do
    drop index(:summaries, [:status])

    alter table(:summaries) do
      remove :status
      remove :validated_at
    end
  end

  def down do
    alter table(:summaries) do
      add :status, :string, null: false, default: "unreviewed"
      add :validated_at, :utc_datetime
    end

    create index(:summaries, [:status])
  end
end
