defmodule Mix.Tasks.Dre.Scrape do
  @shortdoc "Scrape Diário da República Série I for a date into the register"
  @moduledoc """
  Ingest one day of Diário da República Série I.

      mix dre.scrape 2026-06-24       # a specific publication date
      mix dre.scrape                  # today
      mix dre.scrape 2026-06-24 --no-enrich   # skip per-act detail fetch

  Idempotent: re-running the same date upserts and is a no-op on counts.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: [enrich: :boolean])

    date =
      case args do
        [d | _] -> Date.from_iso8601!(d)
        [] -> Date.utc_today()
      end

    Mix.shell().info("Scraping DRE Série I for #{Date.to_iso8601(date)}...")

    case OQueMudou.Scraper.ingest_date(date, enrich: Keyword.get(opts, :enrich, true)) do
      {:ok, %{editions: e, acts: a, enriched: k}} ->
        Mix.shell().info("Done: #{e} edition(s), #{a} act(s) upserted, #{k} enriched.")

      {:error, reason} ->
        Mix.shell().error("Scrape failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
