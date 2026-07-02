defmodule Arcada.Repo.Migrations.CreateActs do
  use Ecto.Migration

  def change do
    create table(:acts) do
      add :edition_id, references(:editions, on_delete: :delete_all), null: false
      add :dre_id, :string, null: false
      add :tipo, :string
      add :emitter, :string
      add :title, :text
      add :full_text, :text
      add :source_url, :string
      add :pdf_url, :string
      add :published_at, :date

      timestamps(type: :utc_datetime)
    end

    # dre_id (the DRE DbId) is the idempotency key for the scraper's upserts.
    create unique_index(:acts, [:dre_id])
    create index(:acts, [:edition_id])
  end
end
