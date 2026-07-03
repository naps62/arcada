defmodule Arcada.Scraper.IngestWorker do
  @moduledoc """
  Oban worker that scrapes one day of Diário da República Série I. Runs daily on a
  cron (business-day mornings, after publication) and is also the unit
  `Arcada.Scraper.backfill/1` enqueues per date.

  For the daily run it also enqueues summarization for the day's new acts, so
  today's diplomas summarize immediately. A **backfill** run (`summarize: false`)
  ingests only — `Arcada.Summarizer.SummarySweeper` drains those summaries at its
  own pace rather than flooding the queue with a whole archive at once.

  Idempotent and retry-safe: ingestion upserts by `dre_id`, and summaries are
  only enqueued for acts that don't already have one — so a retry (or a re-run
  of the same date) neither duplicates acts nor re-summarizes.

  Args: `%{"date" => "YYYY-MM-DD"}` (defaults to today), `%{"summarize" => false}`
  to skip the eager summary enqueue.
  """
  use Oban.Worker, queue: :scrape, max_attempts: 3

  require Logger

  alias Arcada.{Register, Scraper, Summarizer}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    date = parse_date(args["date"])

    case Scraper.ingest_date(date, ingest_opts()) do
      {:ok, summary} ->
        enqueued = if args["summarize"] == false, do: 0, else: enqueue_summaries(date)

        Logger.info(
          "Ingested #{Date.to_iso8601(date)}: #{inspect(summary)}, #{enqueued} to summarize"
        )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enqueue_summaries(date) do
    date
    |> Register.acts_without_summary()
    |> Enum.map(&Summarizer.enqueue/1)
    |> length()
  end

  defp parse_date(nil), do: Date.utc_today()
  defp parse_date(iso) when is_binary(iso), do: Date.from_iso8601!(iso)

  # Tests inject a stubbed Scraper.Client via :ingest_client; production builds one.
  defp ingest_opts do
    case Application.get_env(:arcada, :ingest_client) do
      nil -> []
      client -> [client: client]
    end
  end
end
