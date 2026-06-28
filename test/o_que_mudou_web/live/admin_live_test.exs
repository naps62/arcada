defmodule OQueMudouWeb.AdminLiveTest do
  use OQueMudouWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias OQueMudou.Admin

  # Force the in-app group check on (config.exs default is bypass: false, but the
  # test env may inherit dev's bypass). Restore afterwards.
  setup do
    prev = Application.get_env(:o_que_mudou, :admin, [])
    Application.put_env(:o_que_mudou, :admin, group: "oqm-admin", bypass: false)
    on_exit(fn -> Application.put_env(:o_que_mudou, :admin, prev) end)
    :ok
  end

  defp as_admin(conn), do: put_req_header(conn, "remote-groups", "users,oqm-admin")

  test "403s without the oqm-admin group header", %{conn: conn} do
    conn = get(conn, ~p"/admin/summarizer")
    assert conn.status == 403
  end

  test "403s when the header lists other groups but not oqm-admin", %{conn: conn} do
    conn = conn |> put_req_header("remote-groups", "users,staff") |> get(~p"/admin/summarizer")
    assert conn.status == 403
  end

  test "renders for an oqm-admin member", %{conn: conn} do
    {:ok, _lv, html} = conn |> as_admin() |> live(~p"/admin/summarizer")
    assert html =~ "Resumidor"
    assert html =~ "Adaptador"
  end

  test "saving persists the settings", %{conn: conn} do
    {:ok, lv, _html} = conn |> as_admin() |> live(~p"/admin/summarizer")

    lv
    |> form("#summarizer-form", setting: %{summarizer_adapter: "ssh", ssh_host: "10.0.0.5"})
    |> render_submit()

    assert Admin.summarizer_adapter() == :ssh
    assert Admin.get_settings().ssh_host == "10.0.0.5"
  end
end
