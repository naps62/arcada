defmodule Arcada.Summarizer.Adapters.Api do
  @moduledoc """
  Anthropic (Claude) Messages API adapter — `provider.kind == :anthropic`. One
  call produces the plain-language summary and the life-domain classification,
  constrained to `Prompt.schema/0` via structured outputs so the domains stay
  within the fixed taxonomy. Uses `provider.api_key` (falls back to
  `ANTHROPIC_API_KEY`).

  Pure transport: the prompt shape and reply parsing live in
  `Arcada.Summarizer.Prompt`; this module only speaks the Claude HTTP protocol.
  `request/2` and `text_block/1` are also used by `Arcada.Summarizer.Extractor`
  so a Claude model can be the omnibus extractor.
  """
  @behaviour Arcada.Summarizer.Adapter

  require Logger

  alias Arcada.Register.Act
  alias Arcada.Providers.Provider
  alias Arcada.Summarizer.Prompt

  @endpoint "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"
  @default_model "claude-opus-5-5"
  # Bump when the prompt/schema change so summaries record which version produced them.
  @prompt_version "2026-07-01.1"

  # Thinking is on by default on current models and counts against max_tokens.
  @max_tokens 16_000

  # Published per-million-token prices ({input, output}), longest model-id prefix
  # wins; unknown models record a nil cost. Haiku 5.5's higher rate past 100K
  # input tokens is not modelled.
  @prices %{
    "claude-fable-" => {10.0, 50.0},
    "claude-opus-5-5" => {4.0, 20.0},
    "claude-opus-" => {5.0, 25.0},
    "claude-sonnet-5" => {2.0, 10.0},
    "claude-sonnet-" => {3.0, 15.0},
    "claude-haiku-5" => {0.1, 0.5},
    "claude-haiku-" => {1.0, 5.0}
  }

  @impl true
  def summarize(%Act{} = act, %Provider{} = provider, model, text, opts \\ []) do
    model = model || @default_model
    started = System.monotonic_time(:millisecond)

    with {:ok, resp} <- request(provider, request_body(act, model, text, opts)),
         {:ok, raw} <- text_block(resp),
         {:ok, parsed} <- Prompt.parse(raw) do
      {:ok,
       parsed
       |> Map.merge(%{model: model, prompt_version: @prompt_version})
       |> Map.merge(usage_attrs(resp, model, started))}
    end
  end

  @doc """
  POST a Messages API `body` with `provider`'s key. `{:ok, response_body}` on a
  200, else `{:error, reason}` (`:missing_api_key`, `{:http_status, status}`, or
  a transport error).
  """
  def request(%Provider{} = provider, body) do
    with {:ok, key} <- api_key(provider) do
      case post(key, body) do
        {:ok, %{status: 200, body: resp}} ->
          {:ok, resp}

        {:ok, %{status: status, body: resp}} ->
          Logger.warning("Claude API returned #{status}: #{inspect(resp)}")
          {:error, {:http_status, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp request_body(act, model, text, opts) do
    %{
      "model" => model,
      "max_tokens" => @max_tokens,
      "system" => Prompt.system(opts),
      "messages" => [%{"role" => "user", "content" => Prompt.act_body(act, text)}],
      "output_config" => %{"format" => %{"type" => "json_schema", "schema" => Prompt.schema()}}
    }
  end

  # Long acts plus thinking can take minutes; Req's 15s default would cut them off.
  defp post(key, body) do
    Req.post(
      @endpoint,
      [
        json: body,
        headers: [{"x-api-key", key}, {"anthropic-version", @anthropic_version}],
        retry: :transient,
        receive_timeout: 300_000
      ] ++ req_options()
    )
  end

  defp req_options do
    Application.get_env(:arcada, __MODULE__, [])[:req_options] || []
  end

  @doc """
  Pull the first text content block out of a Messages response. A refusal or a
  reply cut off at `max_tokens` is an error, since its text isn't the full JSON.
  Structured outputs guarantee the text is valid JSON for the requested schema;
  callers still decode it with the tolerant `Prompt` parsers.
  """
  def text_block(%{"stop_reason" => "refusal"}), do: {:error, :refusal}
  def text_block(%{"stop_reason" => "max_tokens"}), do: {:error, :max_tokens}

  def text_block(%{"content" => content}) when is_list(content) do
    case Enum.find(content, &(&1["type"] == "text")) do
      %{"text" => text} -> {:ok, text}
      _ -> {:error, :no_text_block}
    end
  end

  def text_block(_), do: {:error, :unexpected_response}

  # Pull exact token counts from the response `usage` block and price them.
  # cache_creation/cache_read tokens aren't billed at the base rate, so cost is
  # computed from the plain input/output counts only.
  defp usage_attrs(body, model, started) do
    usage = (is_map(body) && body["usage"]) || %{}
    input = usage["input_tokens"]
    output = usage["output_tokens"]

    %{
      input_tokens: input,
      output_tokens: output,
      cost_usd: cost(model, input, output),
      cost_source: "api",
      duration_ms: System.monotonic_time(:millisecond) - started
    }
  end

  @doc false
  def cost(model, input, output) when is_integer(input) and is_integer(output) do
    @prices
    |> Enum.filter(fn {prefix, _} -> String.starts_with?(model, prefix) end)
    |> Enum.max_by(fn {prefix, _} -> String.length(prefix) end, fn -> nil end)
    |> case do
      {_prefix, {in_price, out_price}} ->
        Decimal.from_float((input * in_price + output * out_price) / 1_000_000)
        |> Decimal.round(6)

      nil ->
        nil
    end
  end

  def cost(_model, _input, _output), do: nil

  defp api_key(%Provider{api_key: key}) when is_binary(key) and key != "", do: {:ok, key}

  defp api_key(_provider) do
    case System.get_env("ANTHROPIC_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end
end
