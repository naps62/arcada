defmodule Arcada.Repo.Migrations.AddEmbeddingToSummaries do
  use Ecto.Migration

  def change do
    # bge-m3 embedding of `plain_text` (1024 × float32 ≈ 4KB/row), packed by
    # `Arcada.Register.Embedding`. Null when the embeddings server was
    # disabled/unreachable at generation time — see issue #27. No pgvector;
    # brute-force cosine over the in-memory index is plenty at this scale.
    alter table(:summaries) do
      add :embedding, :binary
    end
  end
end
