defmodule OQueMudou.Summarizer.Embeddings do
  @moduledoc """
  Text-embedding client used to rank a diploma's sections by how much they look
  like *changes* before sending the most relevant ones to the LLM (see
  `OQueMudou.Summarizer.prepare_text/2`).

  Speaks the **OpenAI-compatible** `POST {base_url}/v1/embeddings` API, so it
  works against [llama.cpp](https://github.com/ggml-org/llama.cpp)
  (`llama-server --embeddings`), [Ollama](https://ollama.com), vLLM, LM Studio,
  TEI, etc. — pick whichever runs on the GPU box; only `base_url` changes. Free
  at our volume and disabled by default: with no server configured the summarizer
  keeps its head-truncation behaviour, so this is a pure opt-in upgrade.

  Configured via `OQueMudou.Admin.embeddings_config/0` (DB settings overlaid on
  the app config). Tests inject `:embed_fn` (a `texts -> {:ok, [vector]} |
  {:error, term}` function) to avoid a live server. All functions take the
  resolved config explicitly so this module never touches the DB itself.
  """

  require Logger

  @default_model "nomic-embed-text"
  @default_timeout 30_000

  @doc """
  Whether section-relevance ranking is available for `cfg` — true when a server
  `base_url` is set, or a test `:embed_fn` is injected.
  """
  @spec enabled?(keyword) :: boolean
  def enabled?(cfg) do
    is_function(cfg[:embed_fn], 1) or (is_binary(cfg[:base_url]) and cfg[:base_url] != "")
  end

  @doc """
  Embed a list of texts, preserving input order. Returns `{:ok, [vector]}` where
  each vector is a list of floats, or `{:error, reason}`.
  """
  @spec embed([binary], keyword) :: {:ok, [[number]]} | {:error, term}
  def embed(texts, cfg) when is_list(texts) do
    case cfg[:embed_fn] do
      fun when is_function(fun, 1) -> fun.(texts)
      _ -> http_embed(texts, cfg)
    end
  end

  @doc "Cosine similarity of two equal-length vectors (0.0 if either is zero)."
  @spec cosine([number], [number]) :: float
  def cosine(a, b) when is_list(a) and is_list(b) do
    na = :math.sqrt(dot(a, a))
    nb = :math.sqrt(dot(b, b))
    if na == 0.0 or nb == 0.0, do: 0.0, else: dot(a, b) / (na * nb)
  end

  defp dot(a, b), do: Enum.zip(a, b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)

  @doc """
  The `/v1/embeddings` URL for a server `base_url`. Tolerates a base that already
  includes a trailing `/v1` (or trailing slashes), so both `https://h` and
  `https://h/v1` resolve to `https://h/v1/embeddings`.
  """
  @spec endpoint_url(binary) :: binary
  def endpoint_url(base) do
    base
    |> String.trim_trailing("/")
    |> String.replace_suffix("/v1", "")
    |> Kernel.<>("/v1/embeddings")
  end

  defp http_embed(texts, cfg) do
    url = endpoint_url(cfg[:base_url])
    body = %{model: cfg[:model] || @default_model, input: texts}

    case Req.post(url,
           json: body,
           headers: auth_headers(cfg[:api_key]),
           receive_timeout: cfg[:timeout] || @default_timeout,
           retry: :transient
         ) do
      {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
        # OpenAI returns objects with an `index`; sort to guarantee input order.
        {:ok, data |> Enum.sort_by(&(&1["index"] || 0)) |> Enum.map(& &1["embedding"])}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Embeddings server returned #{status}: #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.warning("Embeddings request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp auth_headers(key) when is_binary(key) and key != "",
    do: [{"authorization", "Bearer #{key}"}]

  defp auth_headers(_), do: []
end
