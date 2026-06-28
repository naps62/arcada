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
  @prompt_version "2026-06-28.2"
  # Cap act text so oversized diplomas don't exceed the model's context limit.
  @max_text_chars 80_000

  @impl true
  def summarize(%Act{} = act, %Provider{} = provider, model) do
    model = model || @default_model

    with {:ok, key} <- api_key(provider),
         body = request_body(act, model),
         {:ok, %{status: 200} = resp} <- post(key, body),
         {:ok, parsed} <- parse(resp.body) do
      {:ok,
       %{
         plain_text: parsed["plain_text"],
         domains: Enum.map(parsed["domains"] || [], &String.to_existing_atom/1),
         model: model,
         prompt_version: @prompt_version,
         truncated: OQueMudou.Summarizer.truncated?(act.full_text || act.title, @max_text_chars)
       }}
    else
      {:ok, %{status: status, body: body}} ->
        Logger.warning("Claude API returned #{status}: #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_body(act, model) do
    %{
      "model" => model,
      "max_tokens" => 1024,
      "system" => OQueMudou.Summarizer.base_system_prompt(),
      "messages" => [%{"role" => "user", "content" => act_prompt(act)}],
      "output_config" => %{"format" => %{"type" => "json_schema", "schema" => schema()}}
    }
  end

  defp act_prompt(act) do
    """
    Tipo: #{act.tipo}
    Emissor: #{act.emitter}
    Título: #{act.title}

    Texto:
    #{OQueMudou.Summarizer.cap_text(act.full_text || act.title, @max_text_chars)}
    """
  end

  defp schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["plain_text", "domains"],
      "properties" => %{
        "plain_text" => %{"type" => "string"},
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

  defp api_key(%Provider{api_key: key}) when is_binary(key) and key != "", do: {:ok, key}

  defp api_key(_provider) do
    case System.get_env("ANTHROPIC_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end
end
