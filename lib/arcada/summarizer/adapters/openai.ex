defmodule Arcada.Summarizer.Adapters.OpenAI do
  @moduledoc """
  OpenAI-compatible Chat Completions adapter — `provider.kind == :openai`. Works
  with any server exposing `POST {base_url}/chat/completions` (llmbase, ollama,
  synthetic.new, …). Uses `provider.base_url` + `provider.api_key` (Bearer).

  JSON-schema support varies across these servers, so we take the robust path:
  instruct strict JSON in the prompt (`Prompt.instructed_prompt/2`) and let
  `Prompt.parse/1` decode tolerantly, plus send
  `response_format: {type: "json_object"}` (widely supported, harmless if
  ignored). Pure transport — the prompt shape and reply parsing live in
  `Arcada.Summarizer.Prompt`.
  """
  @behaviour Arcada.Summarizer.Adapter

  require Logger

  alias Arcada.Register.Act
  alias Arcada.Providers.Provider
  alias Arcada.Summarizer.Prompt

  @prompt_version "2026-07-01.openai.1"

  @impl true
  def summarize(%Act{} = act, %Provider{} = provider, model, text, opts \\ []) do
    started = System.monotonic_time(:millisecond)

    with {:ok, url} <- endpoint(provider),
         body = request_body(act, model, text, opts),
         {:ok, %{status: 200, body: resp}} <- post(url, provider.api_key, body),
         {:ok, content} <- content(resp),
         {:ok, parsed} <- Prompt.parse(content) do
      {:ok,
       parsed
       |> Map.merge(%{model: model, prompt_version: @prompt_version})
       |> Map.merge(usage_attrs(resp, started))}
    else
      {:ok, %{status: status, body: body}} ->
        Logger.warning("OpenAI-compatible API returned #{status}: #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_body(act, model, text, opts) do
    %{
      "model" => model,
      "messages" => [
        %{"role" => "system", "content" => Prompt.system(opts)},
        %{"role" => "user", "content" => Prompt.instructed_prompt(act, text)}
      ],
      "response_format" => %{"type" => "json_object"},
      "temperature" => 0.2
    }
  end

  defp post(url, api_key, body) do
    headers =
      [{"content-type", "application/json"}] ++
        if(api_key in [nil, ""], do: [], else: [{"authorization", "Bearer #{api_key}"}])

    Req.post(url, json: body, headers: headers, retry: :transient, receive_timeout: 120_000)
  end

  # choices[0].message.content is the (possibly fenced) JSON string we asked for;
  # `Prompt.parse/1` decodes and validates it.
  defp content(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content),
       do: {:ok, content}

  defp content(_), do: {:error, :unexpected_response}

  # Record token counts when the server reports them (OpenAI `usage` shape).
  # These are typically self-hosted / variably-priced backends, so we don't
  # guess a dollar cost — tokens + duration are still useful on their own.
  defp usage_attrs(resp, started) do
    usage = (is_map(resp) && resp["usage"]) || %{}

    %{
      input_tokens: usage["prompt_tokens"],
      output_tokens: usage["completion_tokens"],
      duration_ms: System.monotonic_time(:millisecond) - started
    }
  end

  defp endpoint(%Provider{base_url: base}) when is_binary(base) and base != "" do
    {:ok, String.trim_trailing(base, "/") <> "/chat/completions"}
  end

  defp endpoint(_), do: {:error, :missing_base_url}
end
