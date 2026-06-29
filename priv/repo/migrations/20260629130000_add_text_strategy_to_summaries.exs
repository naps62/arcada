defmodule OQueMudou.Repo.Migrations.AddTextStrategyToSummaries do
  use Ecto.Migration

  def change do
    # How the act text was prepared for this summary's prompt:
    #   "full"     — fit under the cap, sent whole
    #   "rank"     — oversized; most change-relevant sections kept (embeddings)
    #   "truncate" — oversized; opening kept (head-truncation)
    # Lets the per-act comparison view contrast a ranked run against a truncated
    # one for the same provider/model. Null on legacy rows.
    alter table(:summaries) do
      add :text_strategy, :string
    end
  end
end
