defmodule Mix.Tasks.Dre.Scrape do
  @shortdoc "Scrape Diário da República Série I for a date (or backfill a range)"
  @moduledoc """
  Ingest Diário da República Série I.

  One day, synchronously (blocks until done):

      mix dre.scrape 2026-06-24              # a specific publication date
      mix dre.scrape                         # today
      mix dre.scrape 2026-06-24 --no-enrich  # skip per-act detail fetch

  Historical backfill — enqueues one ingest job per business day and returns
  immediately (the SummarySweeper cron summarizes the acts afterwards):

      mix dre.scrape --backfill --since 2025-07-03   # from a date up to today
      mix dre.scrape --backfill --months 12          # the last 12 months
      mix dre.scrape --backfill --from 2025-01-01 --to 2025-06-30

  Idempotent: safe to re-run.
  """
  use Mix.Task

  @requirements ["app.start"]

  @switches [
    enrich: :boolean,
    backfill: :boolean,
    since: :string,
    from: :string,
    to: :string,
    months: :integer
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)

    if opts[:backfill], do: run_backfill(opts), else: run_one(opts, args)
  end

  defp run_one(opts, args) do
    date =
      case args do
        [d | _] -> Date.from_iso8601!(d)
        [] -> Date.utc_today()
      end

    Mix.shell().info("Scraping DRE Série I for #{Date.to_iso8601(date)}...")

    case Arcada.Scraper.ingest_date(date, enrich: Keyword.get(opts, :enrich, true)) do
      {:ok, %{editions: e, acts: a, enriched: k}} ->
        Mix.shell().info("Done: #{e} edition(s), #{a} act(s) upserted, #{k} enriched.")

      {:error, reason} ->
        Mix.shell().error("Scrape failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp run_backfill(opts) do
    to = if opts[:to], do: Date.from_iso8601!(opts[:to]), else: Date.utc_today()
    from = backfill_from(opts, to)

    results = Arcada.Scraper.backfill(from, to)

    Mix.shell().info(
      "Enqueued #{length(results)} ingest day(s) from #{Date.to_iso8601(from)} " <>
        "to #{Date.to_iso8601(to)} (business days, newest first). " <>
        "The SummarySweeper will summarize them."
    )
  end

  # `--from` wins; else `--since`; else `--months` back from `to`.
  defp backfill_from(opts, to) do
    cond do
      opts[:from] -> Date.from_iso8601!(opts[:from])
      opts[:since] -> Date.from_iso8601!(opts[:since])
      opts[:months] -> shift_months(to, -opts[:months])
      true -> Mix.raise("--backfill needs one of --from / --since / --to / --months")
    end
  end

  # Date has no built-in month arithmetic; step whole months and clamp the day
  # (e.g. Mar 31 − 1 month → Feb 28/29).
  defp shift_months(%Date{year: y, month: m, day: d}, months) do
    total = y * 12 + (m - 1) + months
    year = div(total, 12)
    month = rem(total, 12) + 1
    Date.new!(year, month, min(d, Date.days_in_month(Date.new!(year, month, 1))))
  end
end
