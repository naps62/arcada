defmodule Arcada.Repo.Migrations.AddProviderMaxConcurrency do
  use Ecto.Migration

  # Per-provider summarize parallelism (issue #22). SSH must stay at one
  # concurrent session; API-style providers can fan out. Backfill existing rows
  # by kind so the gate has a value before the admin form is touched.
  def change do
    alter table(:providers) do
      add :max_concurrency, :integer
    end

    execute(
      "UPDATE providers SET max_concurrency = CASE WHEN kind = 'ssh' THEN 1 ELSE 5 END",
      "UPDATE providers SET max_concurrency = NULL"
    )
  end
end
