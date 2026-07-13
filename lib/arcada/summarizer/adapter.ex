defmodule Arcada.Summarizer.Adapter do
  @moduledoc """
  Behaviour for turning an `Act` into a plain-language summary + life-domain tags
  using a specific `Provider` instance and model. Selected by `provider.kind`:

    * `:anthropic` — `Arcada.Summarizer.Adapters.Api` (Claude Messages API)
    * `:openai`    — `Arcada.Summarizer.Adapters.OpenAI` (OpenAI-compatible)
    * `:ssh`       — `Arcada.Summarizer.Adapters.Ssh` (CLI over SSH)
  """

  alias Arcada.Register.Act
  alias Arcada.Providers.Provider

  @typedoc """
  A synchronous result — everything `Register.Summary` needs.

  The usage keys are optional: an adapter includes whichever its backend
  reports. `cost_source` is `"api"` (exact tokens × published price table) or
  `"subscription"` (the SSH CLI's notional cost — covered by a Claude
  subscription, not real spend).
  """
  @type result :: %{
          required(:plain_text) => String.t(),
          required(:headline) => String.t(),
          required(:domains) => [atom()],
          required(:model) => String.t(),
          required(:prompt_version) => String.t(),
          optional(:input_tokens) => non_neg_integer(),
          optional(:output_tokens) => non_neg_integer(),
          optional(:cost_usd) => Decimal.t() | float() | nil,
          optional(:cost_source) => String.t(),
          optional(:duration_ms) => non_neg_integer()
        }

  @doc """
  Summarize an act. `text` is the already-prepared act body (capped / section-
  ranked by `Arcada.Summarizer` — adapters don't re-prepare it); the adapter
  builds its prompt from `act`'s metadata plus this text. Truncation/strategy
  bookkeeping is handled by the caller, so the result need not include it.

  `opts` carries prompt-shaping context — currently `:strategy` (`:full | :rank |
  :truncate`), forwarded to `Arcada.Summarizer.Prompt.system/1` so omnibus acts
  get the theme-level note. Adapters default it to `[]`.
  """
  @callback summarize(Act.t(), Provider.t(), String.t(), text :: String.t(), opts :: keyword) ::
              {:ok, result} | {:async, term} | {:error, term}
end
