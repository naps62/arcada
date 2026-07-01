defmodule OQueMudou.Summarizer.Adapters.Api do
  @moduledoc """
  Anthropic (Claude) Messages API adapter — `provider.kind == :anthropic`. One
  call produces the plain-language summary and the life-domain classification,
  constrained to a JSON schema via structured outputs so the domains stay within
  the fixed taxonomy. Uses `provider.api_key` (falls back to `ANTHROPIC_API_KEY`).
  """
  @behaviour OQueMudou.Summarizer.Adapter

  require Logger

  alias OQueMudou.Register
  alias OQueMudou.Register.Act
  alias OQueMudou.Providers.Provider

  @endpoint "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"
  @default_model "claude-sonnet-4-6"
  # Bump when the prompt/schema change so summaries record which version produced them.
  @prompt_version "2026-07-01.1"

  # Published per-million-token prices ({input, output}), matched by model-id
  # prefix so minor version bumps don't need a table update. Turns the response's
  # exact token counts into a dollar cost; unknown models record tokens with a
  # nil cost rather than guessing.
  @prices %{
    "claude-opus-" => {5.0, 25.0},
    "claude-sonnet-" => {3.0, 15.0},
    "claude-haiku-" => {1.0, 5.0}
  }

  @impl true
  def summarize(%Act{} = act, %Provider{} = provider, model, text) do
    model = model || @default_model
    started = System.monotonic_time(:millisecond)

    with {:ok, key} <- api_key(provider),
         body = request_body(act, model, text),
         {:ok, %{status: 200} = resp} <- post(key, body),
         {:ok, parsed} <- parse(resp.body) do
      {:ok,
       %{
         plain_text: parsed["plain_text"],
         headline: parsed["headline"],
         domains: Enum.map(parsed["domains"] || [], &String.to_existing_atom/1),
         model: model,
         prompt_version: @prompt_version
       }
       |> Map.merge(usage_attrs(resp.body, model, started))}
    else
      {:ok, %{status: status, body: body}} ->
        Logger.warning("Claude API returned #{status}: #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_body(act, model, text) do
    %{
      "model" => model,
      "max_tokens" => 1024,
      "system" => OQueMudou.Summarizer.base_system_prompt(),
      "messages" => [%{"role" => "user", "content" => act_prompt(act, text)}],
      "output_config" => %{"format" => %{"type" => "json_schema", "schema" => schema()}}
    }
  end

  defp act_prompt(act, text) do
    """
    Tipo: #{act.tipo}
    Emissor: #{act.emitter}
    Título: #{act.title}

    Texto:
    #{text}
    """
  end

  defp schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["plain_text", "headline", "domains"],
      "properties" => %{
        "plain_text" => %{"type" => "string"},
        "headline" => %{"type" => "string"},
        "domains" => %{
          "type" => "array",
          "items" => %{"type" => "string", "enum" => Register.life_domains()}
        }
      }
    }
  end

  defp post(key, body) do
    Req.post(@endpoint,
      json: body,
      headers: [{"x-api-key", key}, {"anthropic-version", @anthropic_version}],
      retry: :transient
    )
  end

  # Structured outputs guarantee the first text block is valid JSON for our schema.
  defp parse(%{"content" => content}) do
    case Enum.find(content, &(&1["type"] == "text")) do
      %{"text" => text} -> Jason.decode(text)
      _ -> {:error, :no_text_block}
    end
  end

  defp parse(_), do: {:error, :unexpected_response}

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

  defp cost(model, input, output) when is_integer(input) and is_integer(output) do
    case Enum.find(@prices, fn {prefix, _} -> String.starts_with?(model, prefix) end) do
      {_prefix, {in_price, out_price}} ->
        Decimal.from_float((input * in_price + output * out_price) / 1_000_000)
        |> Decimal.round(6)

      nil ->
        nil
    end
  end

  defp cost(_model, _input, _output), do: nil

  defp api_key(%Provider{api_key: key}) when is_binary(key) and key != "", do: {:ok, key}

  defp api_key(_provider) do
    case System.get_env("ANTHROPIC_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end
end
