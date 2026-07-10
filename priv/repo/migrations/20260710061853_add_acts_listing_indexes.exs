defmodule Arcada.Repo.Migrations.AddActsListingIndexes do
  use Ecto.Migration

  # Indexes for the act listing / sitemap query paths (issue #73). Table is small
  # today, so no CONCURRENTLY.
  def change do
    # list_acts / day-page: ORDER BY published_at DESC, id DESC.
    create index(:acts, [:published_at, :id])
    # FK: nilify_all on summary delete + sitemap WHERE published_summary_id IS NOT NULL.
    create index(:acts, [:published_summary_id])
    # sitemap: ORDER BY updated_at DESC, id DESC over published acts.
    create index(:acts, [:updated_at, :id])
  end
end
