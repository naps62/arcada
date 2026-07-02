defmodule OQueMudouWeb.Plugs.RemoteIp do
  @moduledoc """
  Rewrites `conn.remote_ip` to the real visitor behind the Cloudflare → Traefik
  proxy chain (issue #43).

  The socket peer Phoenix sees is Traefik, not the client — Traefik's
  `forwardedHeaders.trustedIPs` only makes it forward `X-Forwarded-For`, it does
  not rewrite the TCP source. This plug walks the forwarded headers (via the
  `remote_ip` library) to recover the real client.

  Runtime-configurable so the trusted proxy chain can be set per-environment from
  `config/runtime.exs` without a rebuild. Reads `config :o_que_mudou, :remote_ip`,
  whose value maps straight to `RemoteIp` plug options:

      config :o_que_mudou, :remote_ip,
        headers: ["x-forwarded-for"],
        proxies: ["173.245.48.0/20", ..., "10.0.0.0/8"],
        clients: []

  When unset (`nil`) the plug is a no-op, leaving `conn.remote_ip` as the socket
  peer — the right default for dev, test, and any single-host / no-proxy setup.

  `RemoteIp.init/1` parses the proxy/client CIDRs into masks, which is wasteful to
  redo per request, so the compiled options are memoised in `:persistent_term`,
  keyed by the raw config. The key includes the config value, so a config change
  (e.g. tests swapping proxies) transparently recompiles — no manual cache reset.
  """

  require Logger

  @behaviour Plug

  @cache_key {__MODULE__, :compiled}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case compiled_opts(Application.get_env(:o_que_mudou, :remote_ip)) do
      nil -> conn
      opts -> conn |> RemoteIp.call(opts) |> debug_log(conn)
    end
  end

  # TEMP (issue #43 verification): log the resolved client IP alongside the raw
  # peer + forwarded headers so we can confirm the XFF walk end-to-end via Loki.
  # Remove once verified.
  defp debug_log(new_conn, old_conn) do
    fmt = fn ip -> ip |> :inet.ntoa() |> to_string() end

    Logger.info(
      "remote_ip debug: resolved=#{fmt.(new_conn.remote_ip)} peer=#{fmt.(old_conn.remote_ip)} " <>
        "xff=#{inspect(Plug.Conn.get_req_header(old_conn, "x-forwarded-for"))} " <>
        "cf=#{inspect(Plug.Conn.get_req_header(old_conn, "cf-connecting-ip"))} " <>
        "host=#{old_conn.host} path=#{old_conn.request_path}"
    )

    new_conn
  end

  # nil config → plug disabled. Otherwise compile once per distinct config and
  # cache; RemoteIp.init/1 is what parses the CIDR masks.
  defp compiled_opts(nil), do: nil

  defp compiled_opts(config) do
    case :persistent_term.get(@cache_key, :none) do
      {^config, opts} ->
        opts

      _ ->
        opts = RemoteIp.init(config)
        :persistent_term.put(@cache_key, {config, opts})
        opts
    end
  end
end
