defmodule OQueMudou.Register do
  @moduledoc """
  The private register of what changed in Diário da República Série I.

  Groups the core data model — `Edition`, `Act`, `Summary` — and the fixed
  vocabularies (life-domain taxonomy, provenance status) shared across them.
  See `docs/PLAN.md`.
  """

  @life_domains ~w(fiscal trabalho saúde família habitação educação transportes justiça ambiente administração)

  @doc "The fixed life-domain taxonomy used to tag summaries."
  def life_domains, do: @life_domains

  @doc "The provenance-ladder statuses a summary can hold (MVP ships only `:unreviewed`)."
  def statuses, do: [:unreviewed, :community_reviewed, :verified]
end
