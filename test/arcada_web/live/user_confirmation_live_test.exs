defmodule ArcadaWeb.UserConfirmationLiveTest do
  use ArcadaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Arcada.AccountsFixtures

  alias Arcada.Accounts
  alias Arcada.Repo

  setup do
    %{user: unconfirmed_user_fixture()}
  end

  defp confirmation_token(user) do
    extract_user_token(fn url ->
      Accounts.deliver_user_confirmation_instructions(user, url)
    end)
  end

  describe "Confirm user" do
    # The security property behind confirming on connect rather than on click:
    # a mail scanner prefetching the link performs a plain GET, never opens the
    # socket, and so must not confirm anything.
    test "dead render does not confirm the account", %{conn: conn, user: user} do
      token = confirmation_token(user)

      conn = get(conn, ~p"/users/confirm/#{token}")

      assert html_response(conn, 200) =~ "A confirmar a sua conta"
      refute Accounts.get_user!(user.id).confirmed_at
    end

    test "confirms on connect and sends the user to log in", %{conn: conn, user: user} do
      token = confirmation_token(user)

      {:ok, redirected} =
        conn
        |> live(~p"/users/confirm/#{token}")
        |> follow_redirect(conn, ~p"/users/log_in")

      assert Phoenix.Flash.get(redirected.assigns.flash, :info) =~ "Conta confirmada"
      assert Accounts.get_user!(user.id).confirmed_at

      # No session is handed out — a leaked token confirms, it does not log in.
      refute get_session(redirected, :user_token)
      assert Repo.all(Accounts.UserToken) == []
    end

    test "a spent token reports an error when nobody is logged in", %{conn: conn, user: user} do
      token = confirmation_token(user)

      assert {:error, {:redirect, %{to: "/users/log_in"}}} =
               live(conn, ~p"/users/confirm/#{token}")

      {:ok, redirected} =
        conn
        |> live(~p"/users/confirm/#{token}")
        |> follow_redirect(conn, ~p"/users/confirm")

      assert Phoenix.Flash.get(redirected.assigns.flash, :error) =~
               "O endereço de confirmação é inválido ou expirou"
    end

    test "a spent token is quiet when the account is already confirmed", %{conn: conn, user: user} do
      token = confirmation_token(user)

      assert {:error, {:redirect, %{to: "/users/log_in"}}} =
               live(conn, ~p"/users/confirm/#{token}")

      conn = build_conn() |> log_in_user(Accounts.get_user!(user.id))

      assert {:error, {:redirect, redirect}} = live(conn, ~p"/users/confirm/#{token}")
      assert redirect.to == "/"
      refute Map.has_key?(redirect, :flash)
    end

    test "does not confirm with an invalid token", %{conn: conn, user: user} do
      {:ok, redirected} =
        conn
        |> live(~p"/users/confirm/invalid-token")
        |> follow_redirect(conn, ~p"/users/confirm")

      assert Phoenix.Flash.get(redirected.assigns.flash, :error) =~
               "O endereço de confirmação é inválido ou expirou"

      refute Accounts.get_user!(user.id).confirmed_at
    end
  end
end
