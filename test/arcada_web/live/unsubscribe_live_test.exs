defmodule ArcadaWeb.UnsubscribeLiveTest do
  use ArcadaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Arcada.AccountsFixtures
  import Arcada.SubscriptionsFixtures

  alias Arcada.Subscriptions

  defp token_for(subscription), do: Subscriptions.unsubscribe_token(subscription)

  test "works without a session — the token is the authorization", %{conn: conn} do
    subscription = subscription_fixture(user_fixture(), %{query: "renda", period: :semanal})

    {:ok, _lv, html} = live(conn, ~p"/subscricoes/cancelar/#{token_for(subscription)}")

    assert html =~ "«renda»"
    assert html =~ "Confirmar cancelamento"
  end

  # Mail clients and link scanners fetch every URL in an email; a page that
  # unsubscribed on load would cancel subscriptions nobody clicked.
  test "loading the page changes nothing", %{conn: conn} do
    subscription = subscription_fixture(user_fixture(), %{query: "renda", period: :semanal})

    {:ok, _lv, _html} = live(conn, ~p"/subscricoes/cancelar/#{token_for(subscription)}")

    assert Subscriptions.get_subscription(subscription.id).active
  end

  test "confirming pauses the subscription", %{conn: conn} do
    subscription = subscription_fixture(user_fixture(), %{query: "renda", period: :semanal})

    {:ok, lv, _html} = live(conn, ~p"/subscricoes/cancelar/#{token_for(subscription)}")
    html = lv |> element("button", "Confirmar cancelamento") |> render_click()

    refute Subscriptions.get_subscription(subscription.id).active
    assert html =~ "Subscrição cancelada"
  end

  test "a forged token explains itself instead of crashing", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/subscricoes/cancelar/nao-e-um-token")

    assert html =~ "já não é válida"
  end
end
