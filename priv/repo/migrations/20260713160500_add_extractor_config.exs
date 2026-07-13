defmodule Arcada.Repo.Migrations.AddExtractorConfig do
  use Ecto.Migration

  # Extract/render for omnibus (:rank) acts (issue #90): a strong model extracts
  # the concrete changes + headline, amalia renders the body. Config lives on the
  # settings singleton; the extractor model that ran is recorded per summary.
  def change do
    alter table(:settings) do
      add :extractor_provider_id, references(:providers, on_delete: :nilify_all)
      add :extractor_model, :string
      add :extractor_text_chars, :integer
    end

    alter table(:summaries) do
      # The strong model that extracted the changes (preprocessor), set only when
      # the extract/render path ran. Distinct from `model` (the renderer) and
      # `ranker_model` (the embedder that coarse-trimmed the input).
      add :extractor_model, :string
    end
  end
end
