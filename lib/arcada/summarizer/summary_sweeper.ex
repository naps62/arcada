defmodule Arcada.Summarizer.SummarySweeper do
  @moduledoc """
  Cron worker that keeps the summarize queue topped up until every act has a
  summary. Each tick it takes up to `batch` acts with no summary (newest first)
  and enqueues a `SummarizeWorker` for each, low-priority and deduped by act.

  This is the whole backfill engine and a permanent safety net in one. It doesn't
  care *why* an act lacks a summary — a historical act just ingested, or a daily
  summary whose job failed out its retries — it simply re-enqueues it. So the
  system self-heals: a summary that fails (embeddings/LLM server down, a restart)
  is retried on a later tick, with no dead-ends, until `acts_without_summary` is
  empty. When it is, the tick is a single cheap indexed query returning nothing.

  Throttling is deliberately dumb: the per-provider `Concurrency` limit
  (amalia/SSH = 1) sets the real pace, `batch` bounds how many jobs a tick adds,
  and `unique` stops ticks from stacking duplicates on an act already in flight.
  Daily summaries (enqueued at the default priority by `IngestWorker`) always
  dispatch ahead of the low-priority backlog.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias Arcada.{Register, Summarizer}

  # Acts enqueued per tick. A ceiling on how fast the queue fills, not a cap on
  # the backlog — the next tick picks up where this one left off.
  @batch 100
  # Low Oban priority (0 highest, 9 lowest) so daily summaries jump the backlog.
  @priority 9

  @impl Oban.Worker
  def perform(_job) do
    acts = Register.acts_without_summary(batch())

    Enum.each(acts, &Summarizer.enqueue(&1, priority: @priority, unique: true))

    if acts != [], do: Logger.info("SummarySweeper: enqueued #{length(acts)} summaries")

    :ok
  end

  defp batch, do: Application.get_env(:arcada, __MODULE__, [])[:batch] || @batch
end
