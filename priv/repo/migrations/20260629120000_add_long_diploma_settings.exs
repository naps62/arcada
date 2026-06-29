defmodule OQueMudou.Repo.Migrations.AddLongDiplomaSettings do
  use Ecto.Migration

  def change do
    # Runtime-editable handling of oversized diplomas (huge annexes). All
    # nullable → a null falls back to the env/config default. Section-relevance
    # ranking is considered enabled whenever embeddings_base_url is set.
    alter table(:settings) do
      add :max_text_chars, :integer
      add :embeddings_base_url, :string
      add :embeddings_model, :string
    end
  end
end
