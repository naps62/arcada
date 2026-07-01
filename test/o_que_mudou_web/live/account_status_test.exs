defmodule OQueMudouWeb.AccountStatusTest do
  use OQueMudouWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import OQueMudou.AccountsFixtures

  alias OQueMudou.Accounts
  alias OQueMudou.Repo

  describe "unconfirmed-account banner" do
    test "shows for a logged-in, unconfirmed user", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/")

      assert html =~ "ainda não está confirmada"
      assert html =~ ~p"/users/confirm"
    end

    test "hides once the account is confirmed", %{conn: conn} do
      user = user_fixture()
      {:ok, _} = Repo.update(Accounts.User.confirm_changeset(user))

      {:ok, _lv, html} =
        conn
        |> log_in_user(Accounts.get_user!(user.id))
        |> live(~p"/")

      refute html =~ "ainda não está confirmada"
    end

    test "hides for anonymous visitors", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ "ainda não está confirmada"
    end
  end
end
