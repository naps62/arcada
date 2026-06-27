defmodule OQueMudou.Repo.Migrations.CreateSummaries do
  use Ecto.Migration

  def change do
    create table(:summaries) do
      add :act_id, references(:acts, on_delete: :delete_all), null: false
      add :plain_text, :text
      add :domains, {:array, :string}, null: false, default: []
      add :model, :string
      add :prompt_version, :string
      add :status, :string, null: false, default: "unreviewed"
      add :generated_at, :utc_datetime
      add :validated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:summaries, [:act_id])
    create index(:summaries, [:status])
    # GIN index so we can filter the register by life-domain.
    create index(:summaries, [:domains], using: "GIN")
  end
end
