defmodule OQueMudou.Summarizer.Adapter do
  @moduledoc """
  Behaviour for turning an `Act` into a plain-language summary + life-domain tags.

  The pipeline must not assume a synchronous API call (see `docs/PLAN.md`), so
  `summarize/1` may return `{:async, ref}` — meaning "no summary now; it'll be
  filled in later" (e.g. the `manual` SSH/console backfill adapter). Implementations:

    * `:api`    — `OQueMudou.Summarizer.Adapters.Api` (Claude API, Sonnet 4.6)
    * `:manual` — `OQueMudou.Summarizer.Adapters.Manual` (human/console backfill)
    * `:local`  — `OQueMudou.Summarizer.Adapters.Local` (local model; stub for now)
  """

  alias OQueMudou.Register.Act

  @typedoc """
  A synchronous result carries everything `Register.Summary` needs:
  `plain_text`, `domains`, `model`, `prompt_version`.
  """
  @type result :: %{
          required(:plain_text) => String.t(),
          required(:domains) => [atom()],
          required(:model) => String.t(),
          required(:prompt_version) => String.t()
        }

  @callback summarize(Act.t()) :: {:ok, result} | {:async, term} | {:error, term}
end
