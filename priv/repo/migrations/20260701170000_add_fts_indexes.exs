defmodule OQueMudou.Repo.Migrations.AddFtsIndexes do
  use Ecto.Migration

  # Full-text search for hybrid search (issue #28). GIN expression indexes over
  # the `portuguese` tsvector of the searchable text, split across the two tables
  # that hold it: the act's identifying header (title/tipo/emitter — where law
  # numbers like "Lei 23/2023" live) and the summary's plain-language body.
  #
  # The expressions here must match `OQueMudou.Search.FTS`'s query fragments
  # verbatim, or Postgres can't use these indexes for the lookup.
  def change do
    execute(
      """
      CREATE INDEX acts_fts_idx ON acts USING gin (
        to_tsvector('portuguese', coalesce(title, '') || ' ' || coalesce(tipo, '') || ' ' || coalesce(emitter, ''))
      )
      """,
      "DROP INDEX acts_fts_idx"
    )

    execute(
      """
      CREATE INDEX summaries_fts_idx ON summaries USING gin (
        to_tsvector('portuguese', coalesce(plain_text, '') || ' ' || coalesce(headline, ''))
      )
      """,
      "DROP INDEX summaries_fts_idx"
    )
  end
end
