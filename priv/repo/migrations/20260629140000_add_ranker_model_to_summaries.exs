defmodule OQueMudou.Repo.Migrations.AddRankerModelToSummaries do
  use Ecto.Migration

  def change do
    # The embeddings model that ranked this act's sections (preprocessor), set
    # only when text_strategy = "rank". Null when ranking didn't run (full /
    # truncate) or on legacy rows. Distinct from `model` (the LLM that wrote it).
    alter table(:summaries) do
      add :ranker_model, :string
    end
  end
end
