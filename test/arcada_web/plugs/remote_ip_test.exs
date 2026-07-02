defmodule ArcadaWeb.Plugs.RemoteIpTest do
  # async: false — this plug reads/mutates the shared :remote_ip app env and a
  # :persistent_term cache, so specs must not run concurrently.
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias ArcadaWeb.Plugs.RemoteIp, as: Plug

  @peer {172, 18, 0, 5}

  setup do
    prev = Application.get_env(:arcada, :remote_ip)

    on_exit(fn ->
      case prev do
        nil -> Application.delete_env(:arcada, :remote_ip)
        val -> Application.put_env(:arcada, :remote_ip, val)
      end
    end)

    :ok
  end

  defp conn_from(headers) do
    conn = %{conn(:get, "/") | remote_ip: @peer}
    Enum.reduce(headers, conn, fn {k, v}, acc -> put_req_header(acc, k, v) end)
  end

  defp run(conn), do: Plug.call(conn, Plug.init([]))

  describe "disabled (config nil)" do
    test "is a no-op, leaving the socket peer as remote_ip" do
      Application.delete_env(:arcada, :remote_ip)
      conn = run(conn_from([{"x-forwarded-for", "203.0.113.7"}]))
      assert conn.remote_ip == @peer
    end
  end

  describe "x-forwarded-for strategy" do
    setup do
      Application.put_env(:arcada, :remote_ip,
        headers: ["x-forwarded-for"],
        proxies: ArcadaWeb.RemoteIpProxies.default(),
        clients: []
      )

      :ok
    end

    test "recovers the real client, walking back past the Traefik peer" do
      # XFF as seen at the origin: real client, then the Cloudflare edge.
      conn = run(conn_from([{"x-forwarded-for", "203.0.113.7, 172.68.0.1"}]))
      assert conn.remote_ip == {203, 0, 113, 7}
    end

    test "trusts a single-value XFF from a private proxy peer" do
      conn = run(conn_from([{"x-forwarded-for", "198.51.100.23"}]))
      assert conn.remote_ip == {198, 51, 100, 23}
    end

    test "keeps the peer when there is no forwarded header" do
      conn = run(conn_from([]))
      assert conn.remote_ip == @peer
    end

    test "ignores an untrusted (non-Cloudflare, non-private) forwarding hop" do
      # 8.8.8.8 is neither a configured proxy nor private, so RemoteIp treats it
      # as the client and stops there — a direct-to-origin spoof can't inject an
      # arbitrary client past an untrusted hop.
      conn = run(conn_from([{"x-forwarded-for", "203.0.113.7, 8.8.8.8"}]))
      assert conn.remote_ip == {8, 8, 8, 8}
    end
  end

  describe "cf-connecting-ip strategy" do
    setup do
      Application.put_env(:arcada, :remote_ip,
        headers: ["cf-connecting-ip"],
        proxies: [],
        clients: []
      )

      :ok
    end

    test "trusts Cloudflare's single-value client header" do
      conn = run(conn_from([{"cf-connecting-ip", "203.0.113.42"}]))
      assert conn.remote_ip == {203, 0, 113, 42}
    end
  end

  describe "config change" do
    test "recompiles cached options when the config value changes" do
      Application.put_env(:arcada, :remote_ip, headers: ["x-real-ip"], proxies: [])
      conn = run(conn_from([{"x-real-ip", "203.0.113.1"}, {"x-forwarded-for", "198.51.100.9"}]))
      assert conn.remote_ip == {203, 0, 113, 1}

      # Swap the header set: the cache must not serve the stale compiled opts.
      Application.put_env(:arcada, :remote_ip, headers: ["x-forwarded-for"], proxies: [])
      conn = run(conn_from([{"x-real-ip", "203.0.113.1"}, {"x-forwarded-for", "198.51.100.9"}]))
      assert conn.remote_ip == {198, 51, 100, 9}
    end
  end
end
