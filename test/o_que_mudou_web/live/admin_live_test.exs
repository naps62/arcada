defmodule OQueMudouWeb.AdminLiveTest do
  use OQueMudouWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import OQueMudou.SummarizerHelpers

  alias OQueMudou.Admin

  test "renders the providers hub", %{conn: conn} do
    {:ok, _lv, html} = conn |> live(~p"/admin")
    assert html =~ "Summarizer"
    assert html =~ "Providers"
  end

  test "renders the admin shell sidebar with both sections", %{conn: conn} do
    {:ok, _lv, html} = conn |> live(~p"/admin")
    assert html =~ "Model settings"
    assert html =~ "Database"
    # /admin/db leaves the app shell (Kaffy chrome) via a plain href.
    assert html =~ ~s(href="/admin/db")
  end

  test "highlights the active section based on the current path", %{conn: conn} do
    {:ok, lv, _html} = conn |> live(~p"/admin")

    active =
      lv
      |> element(~s(a[aria-current="page"]))
      |> render()

    assert active =~ "Model settings"
    refute active =~ "Database"
  end

  test "saving the active provider+model persists it", %{conn: conn} do
    provider = ssh_provider()
    {:ok, lv, _html} = conn |> live(~p"/admin")

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
