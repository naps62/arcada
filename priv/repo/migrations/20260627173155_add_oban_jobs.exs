defmodule Arcada.Repo.Migrations.AddObanJobs do
  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 14)

  # Roll all the way back down on rollback, regardless of which version we migrated up to.
  def down, do: Oban.Migration.down(version: 1)
end
