defmodule Arcada.Repo.Migrations.AddTruncatedToSummaries do
  use Ecto.Migration

  def change do
    # True when the act's full text was capped before summarising (huge diploma),
    # so the summary reflects only the opening of the document, not its annexes.
    alter table(:summaries) do
      add :truncated, :boolean, null: false, default: false
    end
  end
end
