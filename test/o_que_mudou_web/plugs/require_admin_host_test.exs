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
  defp as_admin(conn), do: put_req_header(conn, "remote-groups", "users,oqm-admin")

  describe "with an admin host configured" do
    setup do
      put_admin(group: "oqm-admin", bypass: false, host: @admin_host)
      :ok
    end

    test "404s /admin on the public host, even with the admin group", %{conn: conn} do
      conn = conn |> on_host(@public_host) |> as_admin() |> get(~p"/admin")
      assert conn.status == 404
    end

    test "404s /admin/db (Kaffy) on the public host", %{conn: conn} do
      conn = conn |> on_host(@public_host) |> as_admin() |> get("/admin/db")
      assert conn.status == 404
    end

    test "host guard wins over the group check (404, not 403) on the public host", %{conn: conn} do
      # No admin group header: without the host guard this would be a 403.
      conn = conn |> on_host(@public_host) |> get(~p"/admin")
      assert conn.status == 404
    end

    test "reaches the group check on the admin host (403 without the group)", %{conn: conn} do
      conn = conn |> on_host(@admin_host) |> get(~p"/admin")
      assert conn.status == 403
    end

    test "serves /admin on the admin host for an oqm-admin member", %{conn: conn} do
      conn = conn |> on_host(@admin_host) |> as_admin() |> get(~p"/admin")
      # LiveView dead render returns 200; the point is it's not a 404/403.
      assert conn.status == 200
    end
  end

  describe "without an admin host configured (dev/test/single-host)" do
    setup do
      put_admin(group: "oqm-admin", bypass: false)
      :ok
    end

    test "does not host-guard: /admin reaches the group check on any host", %{conn: conn} do
      conn = conn |> on_host(@public_host) |> get(~p"/admin")
      assert conn.status == 403
    end
  end
end
