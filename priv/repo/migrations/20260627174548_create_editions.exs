defmodule Arcada.Repo.Migrations.CreateEditions do
  use Ecto.Migration

  def change do
    create table(:editions) do
      add :serie, :string, null: false
      add :number, :string, null: false
      add :date, :date, null: false
      add :sumario_url, :string
      add :scraped_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # A Série I issue is uniquely identified by its number (e.g. "118/2026") within a série.
    create unique_index(:editions, [:serie, :number])
    create index(:editions, [:date])
  end
end
