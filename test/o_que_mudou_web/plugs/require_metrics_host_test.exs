defmodule OQueMudouWeb.Plugs.RequireMetricsHostTest do
  use OQueMudouWeb.ConnCase, async: false

  # Public host must not expose /metrics; the private VPN host does.
  @public_host "arcada.naps.pt"
  @metrics_host "arcada.example.internal"

  setup do
    prev = Application.get_env(:o_que_mudou, :metrics, [])
    on_exit(fn -> Application.put_env(:o_que_mudou, :metrics, prev) end)
    :ok
  end

  defp put_metrics(opts), do: Application.put_env(:o_que_mudou, :metrics, opts)
  defp on_host(conn, host), do: %{conn | host: host}

  describe "with a metrics host configured" do
    setup do
      put_metrics(host: @metrics_host)
      :ok
    end

    test "404s /metrics on the public host", %{conn: conn} do
      conn = conn |> on_host(@public_host) |> get("/metrics")
      assert conn.status == 404
    end

    test "serves /metrics on the private host", %{conn: conn} do
      conn = conn |> on_host(@metrics_host) |> get("/metrics")
      assert conn.status == 200
      assert conn.resp_body =~ "# HELP" or conn.resp_body =~ "# TYPE"
    end

    test "does not guard other paths on the public host", %{conn: conn} do
      # A non-/metrics path on the public host is untouched by this plug.
      conn = conn |> on_host(@public_host) |> get("/")
      assert conn.status == 200
    end
  end

  describe "without a metrics host configured (dev/test/single-host)" do
    setup do
      put_metrics([])
      :ok
    end

    test "does not host-guard: /metrics reachable on any host", %{conn: conn} do
      conn = conn |> on_host(@public_host) |> get("/metrics")
      assert conn.status == 200
    end
  end
end
