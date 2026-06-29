defmodule OQueMudou.Repo.Migrations.AddUsageToSummaries do
  use Ecto.Migration

  def change do
    # Per-summary token usage + cost, captured from the adapter's response.
    #   input_tokens / output_tokens — prompt / completion tokens for this run.
    #   cost_usd      — dollar cost. Meaning depends on `cost_source`.
    #   cost_source   — "api"          (exact tokens × published price table) or
    #                   "subscription" (SSH CLI's notional total_cost_usd; the
    #                                   run is actually covered by a Claude
    #                                   subscription, so this is not real spend).
    #                   Null when the backend reports no usable cost (e.g. a
    #                   self-hosted OpenAI-compatible server) or on legacy rows.
    #   duration_ms   — wall-clock the summarization call took.
    alter table(:summaries) do
      add :input_tokens, :integer
      add :output_tokens, :integer
      add :cost_usd, :decimal
      add :cost_source, :string
      add :duration_ms, :integer
    end
  end
end
