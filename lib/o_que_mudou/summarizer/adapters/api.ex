defmodule OQueMudou.Summarizer.Adapters.Api do
  @moduledoc """
  Claude API adapter. One call produces both the plain-language summary and the
  life-domain classification (see `docs/PLAN.md`: classification shares the
  summary call), constrained to a JSON schema via structured outputs so the
  domains are guaranteed to be members of the fixed taxonomy.

  Config (`config/runtime.exs`):

      config :o_que_mudou, OQueMudou.Summarizer.Adapters.Api,
        api_key: System.get_env("ANTHROPIC_API_KEY"),
        model: "claude-sonnet-4-6"
  """
  @behaviour OQueMudou.Summarizer.Adapter

  require Logger

  alias OQueMudou.Register
  alias OQueMudou.Register.Act

  @endpoint "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"
  @default_model "claude-sonnet-4-6"
  # Bump when the prompt/schema change so summaries record which version produced them.
  @prompt_version "2026-06-27.1"

  @system """
  És um assistente que resume diplomas legais do Diário da República em português \
  claro e acessível, para uma pessoa comum perceber o que mudou, para quem, e a \
  partir de quando. Não dês aconselhamento jurídico. Sê conciso (2-4 frases) e \
  factual. Classifica o diploma em um ou mais domínios de vida da taxonomia fixa.
  """

  @impl true
  def summarize(%Act{} = act) do
    with {:ok, key} <- api_key(),
         body = request_body(act),
         {:ok, %{status: 200} = resp} <- post(key, body),
         {:ok, parsed} <- parse(resp.body) do
      {:ok,
       %{
         plain_text: parsed["plain_text"],
         domains: Enum.map(parsed["domains"] || [], &String.to_existing_atom/1),
         model: model(),
         prompt_version: @prompt_version
       }}
    else
      {:ok, %{status: status, body: body}} ->
        Logger.warning("Claude API returned #{status}: #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_body(act) do
    %{
      "model" => model(),
      "max_tokens" => 1024,
      "system" => @system,
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
    #{act.full_text || act.title}
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
      headers: [
        {"x-api-key", key},
        {"anthropic-version", @anthropic_version}
      ],
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

  defp model do
    config()[:model] || @default_model
  end

  defp api_key do
    case config()[:api_key] || System.get_env("ANTHROPIC_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp config, do: Application.get_env(:o_que_mudou, __MODULE__, [])
end
