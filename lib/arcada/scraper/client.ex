defmodule Arcada.Scraper.Client do
  @moduledoc """
  Req-based client for the DRE OutSystems `screenservices` endpoints.

  The OutSystems contract (reverse-engineered in `docs/endpoints.md`):

    1. POST any screenservices path once to be issued `nr1Users`/`nr2Users`
       cookies; the `crf` inside `nr2Users` is the `X-CSRFToken` for every call.
    2. `moduleVersion` comes from `/dr/moduleservices/moduleversioninfo` and
       rotates on each DRE deploy, so we fetch it live per session.
    3. Data actions take `screenData.variables` + `clientVariables`
       (a self-generated `Session_GUID` is accepted).

  `apiVersion` hashes also rotate; they're read from config with the
  last-known-good values as defaults. This module is a dumb transport: each
  data-action is one request that reports rotation via `{:rotated, raw}` when
  DRE sets `versionInfo.hasApiVersionChanged: true`. Detecting that, re-deriving
  the fresh hash, and retrying is owned by `Arcada.Scraper.Session` — keeping the
  self-heal in one place and this module free of the `ApiVersionResolver` cycle.
  """

  alias Arcada.Scraper.Parser

  @list_path "/dr/screenservices/dr/Home/WB_Serie1_List/DataActionGetDataAndApplicationSettings"
  @detail_path "/dr/screenservices/dr/Legislacao_Conteudos/Conteudo_Detalhe/DataActionGetAllConteudoDetalheData"
  @moduleversion_path "/dr/moduleservices/moduleversioninfo"

  defstruct [
    :base_url,
    :cookie,
    :crf,
    :module_version,
    :session_guid,
    :list_api_version,
    :detail_api_version,
    req_options: []
  ]

  @type t :: %__MODULE__{}

  @doc "Build an un-bootstrapped client from config (+ overrides, e.g. `:req_options` for tests)."
  def new(opts \\ []) do
    cfg = Application.get_env(:arcada, __MODULE__, [])

    %__MODULE__{
      base_url: opts[:base_url] || cfg[:base_url] || "https://diariodarepublica.pt",
      list_api_version: opts[:list_api_version] || cfg[:list_api_version],
      detail_api_version: opts[:detail_api_version] || cfg[:detail_api_version],
      session_guid: opts[:session_guid] || uuid4(),
      req_options: opts[:req_options] || []
    }
  end

  @doc "Acquire cookies + CSRF token + module version. Returns `{:ok, client}` or `{:error, reason}`."
  def bootstrap(%__MODULE__{} = client) do
    with {:ok, resp} <- request(client, :post, @list_path, json: %{}),
         cookies = extract_cookies(resp),
         crf when is_binary(crf) <- Parser.parse_crf(cookies["nr2Users"]),
         {:ok, mv_resp} <-
           request(%{client | cookie: cookie_header(cookies)}, :get, @moduleversion_path),
         mv when is_binary(mv) <- get_in(mv_resp.body, ["versionToken"]) do
      {:ok, %{client | cookie: cookie_header(cookies), crf: crf, module_version: mv}}
    else
      nil -> {:error, :bootstrap_no_token}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List the Série I edition(s) (with their acts) published on `date`. One request,
  no heal — `Session` owns the retry.

  Returns `{:ok, raw_json}`, `{:rotated, raw_json}` (DRE reports the list
  `apiVersion` rotated; `raw` carried for graceful fallback), or `{:error, reason}`.
  """
  def list(%__MODULE__{} = client, %Date{} = date) do
    iso = Date.to_iso8601(date)

    variables = %{
      "DataSelecionada" => iso,
      "IsSumarioCompleto" => false,
      "IsPageTracked" => false,
      "_dataSelecionadaInDataFetchStatus" => 1,
      "_isSumarioCompletoInDataFetchStatus" => 1,
      "_isPageTrackedInDataFetchStatus" => 1
    }

    body = envelope(client, client.list_api_version, "Home.home", variables, %{"Data" => iso})
    post(client, @list_path, body)
  end

  @doc """
  Fetch an act's raw detail response by `tipo` slug + `key`. One request, no heal.

  Returns `{:ok, raw_json}`, `{:rotated, raw_json}`, or `{:error, reason}`. The
  caller (`Session`) parses the enrichment out of `raw`.
  """
  def detail(%__MODULE__{} = client, tipo, key) do
    variables = %{
      "Tipo" => tipo,
      "Key" => key,
      "_tipoInDataFetchStatus" => 1,
      "_keyInDataFetchStatus" => 1
    }

    body =
      envelope(
        client,
        client.detail_api_version,
        "Legislacao_Conteudos.Conteudo_Detalhe",
        variables,
        %{}
      )

    post(client, @detail_path, body)
  end

  @doc "Plain GET returning the (Req-decoded) response body — used by the resolver."
  def http_get(%__MODULE__{} = client, path) do
    case request(client, :get, path) do
      {:ok, resp} -> {:ok, resp.body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Read the current `apiVersion` hash for a data-action (`:list` / `:detail`)."
  def api_version(%__MODULE__{list_api_version: v}, :list), do: v
  def api_version(%__MODULE__{detail_api_version: v}, :detail), do: v

  @doc "Return a client with the `apiVersion` hash for `:list` / `:detail` swapped."
  def put_api_version(%__MODULE__{} = client, :list, v), do: %{client | list_api_version: v}
  def put_api_version(%__MODULE__{} = client, :detail, v), do: %{client | detail_api_version: v}

  # --- internals ---

  # Single POST; the sole place a rotated apiVersion is detected from the body.
  defp post(client, path, body) do
    with {:ok, resp} <- request(client, :post, path, json: body) do
      if rotated?(resp.body), do: {:rotated, resp.body}, else: {:ok, resp.body}
    end
  end

  defp rotated?(%{"versionInfo" => %{"hasApiVersionChanged" => true}}), do: true
  defp rotated?(_), do: false

  defp envelope(client, api_version, view_name, variables, client_variables) do
    %{
      "versionInfo" => %{
        "moduleVersion" => client.module_version,
        "apiVersion" => api_version
      },
      "viewName" => view_name,
      "screenData" => %{"variables" => variables},
      "clientVariables" => Map.put(client_variables, "Session_GUID", client.session_guid)
    }
  end

  defp request(client, method, path, opts \\ []) do
    req =
      [
        base_url: client.base_url,
        url: path,
        method: method,
        headers: headers(client),
        redirect: false,
        retry: :transient
      ]
      |> Keyword.merge(opts)
      |> Keyword.merge(client.req_options)
      |> Req.new()

    case Req.request(req) do
      {:ok, resp} -> {:ok, resp}
      {:error, reason} -> {:error, reason}
    end
  end

  defp headers(client) do
    base = %{
      "content-type" => "application/json; charset=UTF-8",
      "x-requested-with" => "XMLHttpRequest"
    }

    base
    |> maybe_put("cookie", client.cookie)
    |> maybe_put("x-csrftoken", client.crf)
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  # Req normalizes header names to lowercase; set-cookie is a list of cookie strings.
  defp extract_cookies(resp) do
    resp
    |> Map.get(:headers, %{})
    |> Map.get("set-cookie", [])
    |> List.wrap()
    |> Enum.flat_map(&String.split(&1, ~r/,(?=[^;]+=)/))
    |> Enum.reduce(%{}, fn cookie, acc ->
      case cookie |> String.split(";", parts: 2) |> hd() |> String.split("=", parts: 2) do
        [name, value] -> Map.put(acc, String.trim(name), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp cookie_header(cookies) when map_size(cookies) == 0, do: nil

  defp cookie_header(cookies) do
    cookies |> Enum.map_join("; ", fn {k, v} -> "#{k}=#{v}" end)
  end

  # A self-generated UUID-shaped string is accepted as the OutSystems Session_GUID
  # (see endpoints.md) — it's an opaque session tag, not validated for RFC version bits.
  defp uuid4 do
    hex = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

    [
      String.slice(hex, 0, 8),
      String.slice(hex, 8, 4),
      String.slice(hex, 12, 4),
      String.slice(hex, 16, 4),
      String.slice(hex, 20, 12)
    ]
    |> Enum.join("-")
  end
end
