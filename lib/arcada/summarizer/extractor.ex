defmodule Arcada.Summarizer.Extractor do
  @moduledoc """
  The **judgment step** for omnibus (`:rank`) acts (issue #90). A strong model
  reads the (coarse-trimmed) act and returns the concrete changes + a headline;
  `Arcada.Summarizer` then hands the changes to the renderer (amalia), which only
  writes.

  This exists because a small local model can neither *rank* nor *judge* a big
  diploma: the operative change is often buried in an article class both retrieval
  and the 9B deprioritize (a "Norma transitória" granting a new right). A stronger
  model reading the whole thing catches it. Keeping the renderer local preserves
  the tuned voice and keeps output tokens off the paid model.

  OpenAI-compatible transport only (`provider.kind == :openai`) — that's what the
  configured extractor (synthetic/GLM) is. Any other kind returns
  `{:error, :unsupported_extractor}` so the caller falls back to the umbrella
  summary. All failures are non-fatal to the caller by design.
  """

  require Logger

  alias Arcada.Register.Act
  alias Arcada.Providers.Provider
  alias Arcada.Summarizer.Prompt

  @doc """
  Extract `%{headline, changes}` from `text` (the coarse-trimmed act) using
  `provider` + `model`. `{:error, reason}` on transport/HTTP/parse failure or an
  unsupported provider kind — the caller treats any error as "fall back to the
  umbrella summary", so extraction never blocks a summary.
  """
  def extract(%Act{} = act, text, %Provider{} = provider, model) when is_binary(text) do
    with {:ok, content} <- fetch(provider, model, act, text),
         {:ok, extracted} <- Prompt.parse_extraction(content) do
      {:ok, extracted}
    end
  end

  # `:runner` (test injection) takes precedence over the real HTTP call; it
  # receives the request context and returns `{:ok, raw_content}` (still parsed by
  # `Prompt.parse_extraction/1`) or `{:error, reason}`.
  defp fetch(provider, model, act, text) do
    case Application.get_env(:arcada, __MODULE__, [])[:runner] do
      fun when is_function(fun, 1) ->
        fun.(%{provider: provider, model: model, act: act, text: text})

      _ ->
        default_fetch(provider, model, act, text)
    end
  end

  defp default_fetch(%Provider{kind: :openai} = provider, model, act, text) do
    with {:ok, url} <- endpoint(provider),
         body = request_body(model, act, text),
         {:ok, %{status: 200, body: resp}} <- post(url, provider.api_key, body),
         {:ok, content} <- content(resp) do
      {:ok, content}
    else
      {:ok, %{status: status, body: body}} ->
        Logger.warning("extractor API returned #{status}: #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_fetch(%Provider{}, _model, _act, _text), do: {:error, :unsupported_extractor}

  defp request_body(model, act, text) do
    %{
      "model" => model,
      "messages" => [
        %{"role" => "system", "content" => Prompt.extraction_system()},
        %{"role" => "user", "content" => Prompt.extraction_prompt(act, text)}
      ],
      "response_format" => %{"type" => "json_object"},
      "temperature" => 0.2
    }
  end

  defp post(url, api_key, body) do
    headers =
      [{"content-type", "application/json"}] ++
        if(api_key in [nil, ""], do: [], else: [{"authorization", "Bearer #{api_key}"}])

    Req.post(url, json: body, headers: headers, retry: :transient, receive_timeout: 180_000)
  end

  defp content(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content),
       do: {:ok, content}

  defp content(_), do: {:error, :unexpected_response}

  defp endpoint(%Provider{base_url: base}) when is_binary(base) and base != "",
    do: {:ok, String.trim_trailing(base, "/") <> "/chat/completions"}

  defp endpoint(_), do: {:error, :missing_base_url}
end
