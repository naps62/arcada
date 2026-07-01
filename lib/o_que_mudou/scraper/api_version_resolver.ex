defmodule OQueMudou.Scraper.ApiVersionResolver do
  @moduledoc """
  Re-derives the current `apiVersion` hash for a DRE `screenservices` data-action
  over plain HTTP — no headless browser required.

  Each `apiVersion` rotates on every DRE (OutSystems) deploy. The live value is
  the 3rd argument of the `callDataAction(...)` call baked into the owning
  screen's `*.mvc.js`. The tricky part — the mvc.js filename carries a rotating
  hash — is solved by the OutSystems manifest:

    1. `GET /dr/moduleservices/moduleinfo` → `manifest.urlVersions`, a map of
       every asset path (incl. each screen's `*.mvc.js`) to its `?<hash>` suffix.
    2. `GET /dr/scripts/<Module>.<Screen>.mvc.js?<hash>` → the screen bundle.
    3. Extract the 3rd `callDataAction("<Action>", "<path>", "<apiVersion>", …)`
       argument for the action we care about.

  Used by `OQueMudou.Scraper.Client` to self-heal: when a data-action reports
  `versionInfo.hasApiVersionChanged: true`, we re-resolve, swap in the fresh
  hash, and retry — so the scraper survives DRE redeploys without a config edit
  or a manual re-derivation. See `docs/endpoints.md`.
  """

  alias OQueMudou.Scraper.Client

  @manifest_path "/dr/moduleservices/moduleinfo"

  # key => {mvc.js path as it appears in the manifest, data-action name}
  @scripts %{
    list:
      {"/dr/scripts/dr.Home.WB_Serie1_List.mvc.js", "DataActionGetDataAndApplicationSettings"},
    detail:
      {"/dr/scripts/dr.Legislacao_Conteudos.Conteudo_Detalhe.mvc.js",
       "DataActionGetAllConteudoDetalheData"}
  }

  @doc """
  Resolve the current `apiVersion` for each of `keys` (`:list` / `:detail`).

  Returns `{:ok, %{list: hash | nil, detail: hash | nil}}` — a `nil` entry means
  that one action couldn't be resolved (manifest miss, fetch error, or the
  `callDataAction` pattern drifted). Returns `{:error, reason}` only when the
  manifest itself is unreachable.
  """
  def resolve(%Client{} = client, keys \\ [:list, :detail]) do
    with {:ok, url_versions} <- fetch_url_versions(client) do
      {:ok, Map.new(keys, &{&1, resolve_key(client, url_versions, &1)})}
    end
  end

  defp resolve_key(client, url_versions, key) do
    {path, action} = Map.fetch!(@scripts, key)

    with suffix when is_binary(suffix) <- url_versions[path],
         {:ok, js} when is_binary(js) <- Client.http_get(client, path <> suffix),
         [_, version] <- Regex.run(version_regex(action), js) do
      version
    else
      _ -> nil
    end
  end

  defp fetch_url_versions(client) do
    case Client.http_get(client, @manifest_path) do
      {:ok, %{"manifest" => %{"urlVersions" => %{} = uv}}} -> {:ok, uv}
      {:ok, _} -> {:error, :manifest_shape}
      {:error, reason} -> {:error, reason}
    end
  end

  # callDataAction("<Action>", "<screenservices path>", "<apiVersion>", …)
  defp version_regex(action) do
    ~r/callDataAction\(\s*"#{Regex.escape(action)}"\s*,\s*"[^"]*"\s*,\s*"([^"]+)"/
  end
end
