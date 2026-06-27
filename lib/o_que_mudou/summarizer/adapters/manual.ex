defmodule OQueMudou.Summarizer.Adapters.Manual do
  @moduledoc """
  The escape-hatch adapter: produces no automatic summary. Acts stay
  unsummarized until a human backfills one via `OQueMudou.Summarizer.create_summary/2`
  (SSH/console). This is the MVP default — it never calls an external service.
  """
  @behaviour OQueMudou.Summarizer.Adapter

  @impl true
  def summarize(_act), do: {:async, :manual}
end
