defmodule OQueMudou.Summarizer.Adapters.Local do
  @moduledoc """
  Placeholder for a locally-hosted model adapter. Not implemented in the MVP —
  returns `{:error, :not_implemented}` so the pipeline degrades gracefully if
  it's selected before a local backend exists.
  """
  @behaviour OQueMudou.Summarizer.Adapter

  @impl true
  def summarize(_act), do: {:error, :not_implemented}
end
