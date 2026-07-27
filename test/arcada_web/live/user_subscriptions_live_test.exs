defmodule ArcadaWeb.UserSubscriptionsLiveTest do
  # async: false — `set_max_per_user/1` moves an application env, which is global.
  use ArcadaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Arcada.AccountsFixtures
  import Arcada.SubscriptionsFixtures

  alias Arcada.Subscriptions

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "redirects if the visitor is not logged in" do
    assert {:error, {:redirect, %{to: "/users/log_in"}}} =
             live(build_conn(), ~p"/users/subscriptions")
  end

  test "creates a query subscription", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/subscriptions")

    lv
    |> form("#subscription_form", %{
      "kind" => "tema",
      "subscription" => %{"query" => "renda de casa", "period" => "semanal"}
    })
    |> render_submit()

    assert [subscription] = Subscriptions.list_user_subscriptions(user)
    assert subscription.query == "renda de casa"
    assert subscription.period == :semanal
    assert render(lv) =~ "renda de casa"
  end

  # "Tudo o que sai" *is* a blank query, so a stale query in the form must not
  # leak into the digest the user actually asked for.
  test "creating the digest ignores whatever is in the query box", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/subscriptions")

    lv
    |> form("#subscription_form", %{
      "kind" => "tudo",
      "subscription" => %{"query" => "sobra do formulário", "period" => "mensal"}
    })
    |> render_submit()

    assert [subscription] = Subscriptions.list_user_subscriptions(user)
    assert subscription.query == nil
    assert subscription.period == :mensal
  end

  test "the digest form does not offer the daily cadence", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/subscriptions")

    html =
      lv
      |> form("#subscription_form", %{
        "kind" => "tudo",
        "subscription" => %{"query" => "", "period" => "semanal"}
      })
      |> render_change()

    refute html =~ ~s(value="diaria")
  end

  test "shows the error when the same subscription already exists", %{conn: conn, user: user} do
    set_max_per_user(2)
    subscription_fixture(user, %{query: "renda", period: :semanal})
    {:ok, lv, _html} = live(conn, ~p"/users/subscriptions")

    html =
      lv
      |> form("#subscription_form", %{
        "kind" => "tema",
        "subscription" => %{"query" => "renda", "period" => "semanal"}
      })
      |> render_submit()

    assert html =~ "já tem uma subscrição igual"
  end

  test "shows when a subscription last went out", %{conn: conn, user: user} do
    user
    |> subscription_fixture(%{query: "renda", period: :semanal})
    |> with_last_sent(~D[2026-07-20])

    {:ok, _lv, html} = live(conn, ~p"/users/subscriptions")

    assert html =~ "20 de julho de 2026"
  end

  test "pauses and resumes a subscription", %{conn: conn, user: user} do
    subscription = subscription_fixture(user, %{query: "renda", period: :semanal})
    {:ok, lv, _html} = live(conn, ~p"/users/subscriptions")

    lv |> element("#subscription-#{subscription.id} button", "Pausar") |> render_click()
    refute Subscriptions.get_subscription(subscription.id).active

    lv |> element("#subscription-#{subscription.id} button", "Retomar") |> render_click()
    assert Subscriptions.get_subscription(subscription.id).active
  end

  test "deletes a subscription", %{conn: conn, user: user} do
    subscription = subscription_fixture(user, %{query: "renda", period: :semanal})
    {:ok, lv, _html} = live(conn, ~p"/users/subscriptions")

    lv |> element("#subscription-#{subscription.id} button", "Apagar") |> render_click()

    assert Subscriptions.list_user_subscriptions(user) == []
  end

  test "hides the form once the account is at the limit", %{conn: conn, user: user} do
    subscription = subscription_fixture(user, %{query: "renda", period: :semanal})

    {:ok, lv, html} = live(conn, ~p"/users/subscriptions")

    refute html =~ ~s(id="subscription_form")
    assert html =~ "Atingiu o limite de 1 subscrição."

    html = lv |> element("#subscription-#{subscription.id} button", "Apagar") |> render_click()

    assert html =~ ~s(id="subscription_form")
    assert html =~ "Pode ter até 1 subscrição."
  end

  # Accounts predating the lower cap (issue #97) keep their rows; the page must
  # still render and let them delete their way back under it.
  test "an account over the limit still renders and can delete", %{conn: conn, user: user} do
    set_max_per_user(3)

    subscriptions =
      for n <- 1..3, do: subscription_fixture(user, %{query: "tema #{n}", period: :semanal})

    set_max_per_user(1)

    {:ok, lv, html} = live(conn, ~p"/users/subscriptions")

    refute html =~ ~s(id="subscription_form")
    assert html =~ "Atingiu o limite de 1 subscrição."

    [first | _rest] = subscriptions
    lv |> element("#subscription-#{first.id} button", "Apagar") |> render_click()

    assert length(Subscriptions.list_user_subscriptions(user)) == 2
    refute render(lv) =~ ~s(id="subscription_form")
  end

  # The id comes from the client, so a hand-crafted event must not reach someone
  # else's row. The lookup is scoped to the current user and raises instead.
  @tag :capture_log
  test "cannot touch another user's subscription", %{conn: conn} do
    other = subscription_fixture(user_fixture(), %{query: "renda", period: :semanal})
    {:ok, lv, _html} = live(conn, ~p"/users/subscriptions")

    Process.flag(:trap_exit, true)
    catch_exit(render_click(lv, "delete", %{"id" => other.id}))

    assert Subscriptions.get_subscription(other.id)
  end
end
