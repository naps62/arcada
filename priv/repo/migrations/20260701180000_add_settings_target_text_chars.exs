defmodule OQueMudou.Repo.Migrations.AddSettingsTargetTextChars do
  use Ecto.Migration

  def change do
    # Cost target the embeddings ranker trims act text down to, distinct from the
    # safety cap (max_text_chars). Nullable → null falls back to the config/default
    # target (issue #41).
    alter table(:settings) do
      add :target_text_chars, :integer
    end
  end
end
