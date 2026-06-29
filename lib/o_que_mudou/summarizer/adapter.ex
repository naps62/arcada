defmodule OQueMudou.Summarizer.Adapter do
  @moduledoc """
  Behaviour for turning an `Act` into a plain-language summary + life-domain tags
  using a specific `Provider` instance and model. Selected by `provider.kind`:

    * `:anthropic` — `OQueMudou.Summarizer.Adapters.Api` (Claude Messages API)
    * `:openai`    — `OQueMudou.Summarizer.Adapters.OpenAI` (OpenAI-compatible)
    * `:ssh`       — `OQueMudou.Summarizer.Adapters.Ssh` (CLI over SSH)
  """

  alias OQueMudou.Register.Act
  alias OQueMudou.Providers.Provider

  @typedoc "A synchronous result — everything `Register.Summary` needs."
  @type result :: %{
          required(:plain_text) => String.t(),
          required(:domains) => [atom()],
          required(:model) => String.t(),
          required(:prompt_version) => String.t()
        }

  @doc """
  Summarize an act. `text` is the already-prepared act body (capped / section-
  ranked by `OQueMudou.Summarizer` — adapters don't re-prepare it); the adapter
  builds its prompt from `act`'s metadata plus this text. Truncation/strategy
  bookkeeping is handled by the caller, so the result need not include it.
  """
  @callback summarize(Act.t(), Provider.t(), String.t(), text :: String.t()) ::
              {:ok, result} | {:async, term} | {:error, term}
end
