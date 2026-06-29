defmodule OQueMudou.Summarizer.Adapters.OpenAI do
  @moduledoc """
  OpenAI-compatible Chat Completions adapter — `provider.kind == :openai`. Works
  with any server exposing `POST {base_url}/chat/completions` (llmbase, ollama,
  synthetic.new, …). Uses `provider.base_url` + `provider.api_key` (Bearer).

  JSON-schema support varies across these servers, so we take the robust path:
  instruct strict JSON in the prompt and parse tolerantly (like the SSH adapter),
  plus send `response_format: {type: "json_object"}` (widely supported, harmless
  if ignored). Domains are validated against the fixed taxonomy after the fact.
  """
  @behaviour OQueMudou.Summarizer.Adapter

  require Logger

  alias OQueMudou.Register
  alias OQueMudou.Register.Act
  alias OQueMudou.Providers.Provider

  @prompt_version "2026-06-28.openai.1"

  @json_format """
  Responde APENAS com um objeto JSON válido, sem texto antes ou depois, no formato:
  {"plain_text": "<resumo>", "domains": ["<dominio>", ...]}
  Os domínios válidos são EXATAMENTE: #{Enum.join(OQueMudou.Register.life_domains(), ", ")}.
  """

  @impl true
  def summarize(%Act{} = act, %Provider{} = provider, model, text) do
    with {:ok, url} <- endpoint(provider),
         body = request_body(act, model, text),
         {:ok, %{status: 200, body: resp}} <- post(url, provider.api_key, body),
         {:ok, obj} <- parse(resp) do
      {:ok,
       %{
         plain_text: obj["plain_text"],
         domains: valid_domains(obj["domains"]),
         model: model,
         prompt_version: @prompt_version
       }}
    else
      {:ok, %{status: status, body: body}} ->
        Logger.warning("OpenAI-compatible API returned #{status}: #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_body(act, model, text) do
    %{
      "model" => model,
      "messages" => [
        %{"role" => "system", "content" => OQueMudou.Summarizer.base_system_prompt()},
        %{"role" => "user", "content" => act_prompt(act, text)}
      ],
      "response_format" => %{"type" => "json_object"},
      "temperature" => 0.2
    }
  end

  defp act_prompt(act, text) do
    """
    #{@json_format}
    ---
    Tipo: #{act.tipo}
    Emissor: #{act.emitter}
    Título: #{act.title}

    Texto:
    #{text}
    """
  end

  defp post(url, api_key, body) do
    headers =
      [{"content-type", "application/json"}] ++
        if(api_key in [nil, ""], do: [], else: [{"authorization", "Bearer #{api_key}"}])

    Req.post(url, json: body, headers: headers, retry: :transient, receive_timeout: 120_000)
  end

  # choices[0].message.content is the (possibly fenced) JSON string we asked for.
  defp parse(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content) do
    content |> strip_fences() |> Jason.decode()
  end

  defp parse(_), do: {:error, :unexpected_response}

  defp endpoint(%Provider{base_url: base}) when is_binary(base) and base != "" do
    {:ok, String.trim_trailing(base, "/") <> "/chat/completions"}
  end

  defp endpoint(_), do: {:error, :missing_base_url}

  defp strip_fences(str) do
    str
    |> String.trim()
    |> String.replace(~r/^```(?:json)?\s*/i, "")
    |> String.replace(~r/\s*```$/, "")
    |> String.trim()
  end

  defp valid_domains(domains) when is_list(domains) do
    domains
    |> Enum.flat_map(fn d ->
      case Register.fetch_domain(d) do
        {:ok, atom} -> [atom]
        :error -> []
      end
    end)
    |> Enum.uniq()
  end

  defp valid_domains(_), do: []
end
