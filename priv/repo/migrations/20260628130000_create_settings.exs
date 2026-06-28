defmodule OQueMudou.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    # Single-row table holding runtime-editable summarizer config. Every column is
    # nullable: a null falls back to the env-var default (config/runtime.exs).
    create table(:settings) do
      add :summarizer_adapter, :string
      add :api_model, :string
      add :api_key, :string
      add :ssh_host, :string
      add :ssh_user, :string
      add :ssh_claude_cmd, :string
      add :ssh_model, :string

      timestamps(type: :utc_datetime)
    end
  end
end
