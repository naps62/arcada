defmodule OQueMudou.Register do
  @moduledoc """
  The private register of what changed in Diário da República Série I.

  Groups the core data model — `Edition`, `Act`, `Summary` — and the fixed
  vocabularies (life-domain taxonomy, provenance status) shared across them.
  See `docs/PLAN.md`.
  """

  alias OQueMudou.Repo
  alias OQueMudou.Register.{Edition, Act}

  @life_domains ~w(fiscal trabalho saúde família habitação educação transportes justiça ambiente administração)

  @doc "The fixed life-domain taxonomy used to tag summaries."
  def life_domains, do: @life_domains

  @doc "The provenance-ladder statuses a summary can hold (MVP ships only `:unreviewed`)."
  def statuses, do: [:unreviewed, :community_reviewed, :verified]

  @doc """
  Idempotently insert-or-update an edition, keyed on `(serie, number)`.
  Re-scraping the same day updates mutable fields and returns the same row.
  """
  def upsert_edition(attrs) do
    %Edition{}
    |> Edition.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:date, :sumario_url, :scraped_at, :updated_at]},
      conflict_target: [:serie, :number],
      returning: true
    )
  end

  @doc """
  Idempotently insert-or-update an act, keyed on `dre_id` (the scraper's
  idempotency key). `nil` enrichment fields (full_text/pdf_url) never clobber
  an already-populated value.
  """
  def upsert_act(attrs) do
    %Act{}
    |> Act.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, replaceable_act_fields(attrs)},
      conflict_target: [:dre_id],
      returning: true
    )
  end

  # Only overwrite columns we actually have a value for, so a skeleton re-scrape
  # doesn't wipe full_text/pdf_url captured by an earlier detail pass.
  @act_mutable ~w(edition_id tipo emitter title full_text source_url pdf_url published_at)a
  defp replaceable_act_fields(attrs) do
    present = Enum.filter(@act_mutable, fn key -> not is_nil(Map.get(attrs, key)) end)
    [:updated_at | present]
  end
end
