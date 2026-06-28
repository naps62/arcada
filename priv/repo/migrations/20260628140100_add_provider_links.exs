defmodule OQueMudou.Repo.Migrations.AddProviderLinks do
  use Ecto.Migration

  def change do
    # Active provider+model used by the daily cron / auto-summarize.
    alter table(:settings) do
      add :active_provider_id, references(:providers, on_delete: :nilify_all)
      add :active_model, :string
    end

    # Each summary records which provider produced it (model is already stored).
    alter table(:summaries) do
      add :provider_id, references(:providers, on_delete: :nilify_all)
    end

    create index(:summaries, [:provider_id])

    # The canonical summary shown publicly for an act; null → fall back to latest.
    alter table(:acts) do
      add :published_summary_id, references(:summaries, on_delete: :nilify_all)
    end
  end
end
