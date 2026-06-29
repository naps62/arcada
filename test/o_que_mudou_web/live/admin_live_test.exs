defmodule OQueMudouWeb.AdminLiveTest do
  use OQueMudouWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import OQueMudou.SummarizerHelpers

  alias OQueMudou.Admin

  setup do
    prev = Application.get_env(:o_que_mudou, :admin, [])
    Application.put_env(:o_que_mudou, :admin, group: "oqm-admin", bypass: false)
    on_exit(fn -> Application.put_env(:o_que_mudou, :admin, prev) end)
    :ok
  end

  defp as_admin(conn), do: put_req_header(conn, "remote-groups", "users,oqm-admin")

  test "403s without the oqm-admin group header", %{conn: conn} do
    conn = get(conn, ~p"/admin")
    assert conn.status == 403
  end

  test "renders the providers hub for an oqm-admin member", %{conn: conn} do
    {:ok, _lv, html} = conn |> as_admin() |> live(~p"/admin")
    assert html =~ "Summarizer"
    assert html =~ "Providers"
  end

  test "saving the active provider+model persists it", %{conn: conn} do
    provider = ssh_provider()
    {:ok, lv, _html} = conn |> as_admin() |> live(~p"/admin")

    # Picking the provider populates its model options (phx-change), then save.
    lv |> form("#active-form", setting: %{active_provider_id: provider.id}) |> render_change()

    lv
    |> form("#active-form",
      setting: %{active_provider_id: provider.id, active_model: "claude-cli"}
    )
    |> render_submit()

    assert Admin.active_provider().id == provider.id
    assert Admin.active_model() == "claude-cli"
  end
end
