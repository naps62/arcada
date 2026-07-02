defmodule OQueMudouWeb.Plugs.RequireAdminHostTest do
  use OQueMudouWeb.ConnCase, async: false

  # Public host must not expose /admin at all; the private VPN host does.
  @public_host "arcada.naps.pt"
  @admin_host "arcada.example.internal"

  setup do
    prev = Application.get_env(:o_que_mudou, :admin, [])
    on_exit(fn -> Application.put_env(:o_que_mudou, :admin, prev) end)
    :ok
  end

  defp put_admin(opts), do: Application.put_env(:o_que_mudou, :admin, opts)
  defp on_host(conn, host), do: %{conn | host: host}

  describe "with an admin host configured" do
    setup do
      put_admin(host: @admin_host)
      :ok
    end

    test "404s /admin on the public host", %{conn: conn} do
      conn = conn |> on_host(@public_host) |> get(~p"/admin")
      assert conn.status == 404
    end

    test "404s /admin/db (Kaffy) on the public host", %{conn: conn} do
      conn = conn |> on_host(@public_host) |> get("/admin/db")
      assert conn.status == 404
    end

    test "serves /admin on the admin host — no extra auth", %{conn: conn} do
      conn = conn |> on_host(@admin_host) |> get(~p"/admin")
      # LiveView dead render returns 200; the point is it's not a 404.
      assert conn.status == 200
    end
  end

  describe "without an admin host configured (dev/test/single-host)" do
    setup do
      put_admin([])
      :ok
    end

    test "does not host-guard: /admin is served on any host", %{conn: conn} do
      conn = conn |> on_host(@public_host) |> get(~p"/admin")
      assert conn.status == 200
    end
  end
end
