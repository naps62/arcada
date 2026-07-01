defmodule OQueMudou.Summarizer.ContextWindow do
  @moduledoc """
  Derives the char cap for act text fed to the summarizer prompt from the target
  model's context window, instead of a fixed constant (issue #18).

  The old defensive **80k-char** cap (~20k tokens) was set when acts 72/73
  overflowed the model at ~1.7M tokens. It was far too conservative: only those
  two are genuine giants — every act up to ~1M tokens summarised whole in
  production — yet ~18% of acts were silently truncated purely because the cap
  didn't use the available context. This derives the cap from the model's window
  instead:

      cap_chars = round(window_tokens * (1 - reserve_fraction) * chars_per_token)

  `chars_per_token` is deliberately a **low** estimate (Portuguese legal text is
  dense) so a cap-length prompt corresponds to *fewer* tokens than the budget —
  we under-fill rather than overflow. `reserve_fraction` holds back room for the
  system prompt, the JSON output, and token-estimation error.

  Everything is app-config driven (`config :o_que_mudou, #{inspect(__MODULE__)}`)
  so operators can retune without a deploy:

    * `:default_window`   — context window (tokens) for models not in `:windows`
    * `:windows`          — model-id prefix → context window (tokens); longest
                            matching prefix wins
    * `:reserve_fraction` — fraction of the window held back (0.0–1.0)
    * `:chars_per_token`  — tokens→chars ratio (a low estimate is the safe one)

  The DB `max_text_chars` setting and the `OQueMudou.Summarizer`
  `:max_text_chars` config still win as explicit overrides (see
  `OQueMudou.Admin.max_text_chars/1`); this only replaces the hard-coded
  fallback.
  """

  # Conservative default: unknown / local / OpenAI-compatible endpoints often
  # have small windows (8k–128k), so anything not known to be large stays here.
  @default_window 200_000

  # Known windows by model-id prefix (tokens), longest match wins. Claude 4.x and
  # the SSH `claude -p` CLI expose ~1M tokens in this deployment — acts up to ~1M
  # tokens summarised whole in prod; only the ~1.7M-token giants overflowed.
  @default_windows %{
    "claude-sonnet-4" => 1_000_000,
    "claude-opus-4" => 1_000_000,
    "claude-cli" => 1_000_000
  }

  # Hold back 20% of the window for the system prompt + output + estimation error.
  @default_reserve_fraction 0.2

  # Chars per token — a low estimate so we under-fill (PT legal text is dense).
  @default_chars_per_token 3.5

  @doc """
  Char cap for act text targeting `model` (a model-id string, or `nil` for the
  conservative default window). Derived from the model's context window with a
  reserve and a conservative tokens→chars ratio.
  """
  def cap_for(model \\ nil) do
    window = window_for(model)
    usable = window * (1 - reserve_fraction())
    round(usable * chars_per_token())
  end

  @doc "Context window (tokens) for `model` — the longest matching prefix, else the default."
  def window_for(model) when is_binary(model) do
    windows()
    |> Enum.filter(fn {prefix, _} -> String.starts_with?(model, prefix) end)
    |> Enum.max_by(fn {prefix, _} -> String.length(prefix) end, fn -> {nil, default_window()} end)
    |> elem(1)
  end

  def window_for(_model), do: default_window()

  defp windows, do: cfg(:windows, @default_windows)
  defp default_window, do: cfg(:default_window, @default_window)
  defp reserve_fraction, do: cfg(:reserve_fraction, @default_reserve_fraction)
  defp chars_per_token, do: cfg(:chars_per_token, @default_chars_per_token)

  defp cfg(key, default),
    do: Keyword.get(Application.get_env(:o_que_mudou, __MODULE__, []), key, default)
end
