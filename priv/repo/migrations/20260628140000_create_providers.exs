defmodule OQueMudou.Repo.Migrations.CreateProviders do
  use Ecto.Migration

  def change do
    create table(:providers) do
      add :name, :string, null: false
      add :kind, :string, null: false
      add :base_url, :string
      add :api_key, :string
      add :ssh_host, :string
      add :ssh_user, :string
      add :ssh_identity_file, :string
      add :ssh_claude_cmd, :string
      add :models, {:array, :string}, null: false, default: []
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:providers, [:name])
  end
end
