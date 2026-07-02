defmodule Arcada.Repo.Migrations.AddHeadlineToSummaries do
  use Ecto.Migration

  def change do
    # Short plain-language headline ("what changed", ~6-10 words) the summarizer
    # emits alongside plain_text. Null on legacy rows — the UI falls back to the
    # act's formal designation until re-summarized.
    alter table(:summaries) do
      add :headline, :string
    end
  end
end
