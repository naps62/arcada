defmodule ArcadaWeb.UserRegistrationLiveTest do
  use ArcadaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Arcada.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Criar conta"
      assert html =~ "Entrar"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, "/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces", "password" => "too short"})

      assert result =~ "Criar conta"
      assert result =~ "must have the @ sign and no spaces"
      assert result =~ "should be at least 12 character"
    end
  end

  describe "register user" do
    test "creates account and logs the user in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the masthead menu
      conn = get(conn, "/")
      response = html_response(conn, 200)
      assert response =~ "Conta"
      assert response =~ "Sair"
    end

    test "creates account with an optional username", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      form =
        form(lv, "#registration_form",
          user: valid_user_attributes(email: email, username: "handle")
        )

      render_submit(form)
      conn = follow_trigger_action(form, conn)
      assert redirected_to(conn) == ~p"/"

      assert Arcada.Accounts.get_user_by_email(email).username == "handle"
    end

    test "rejects submissions that fill the honeypot field", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      result =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit(%{"hp_name" => "i am a bot"})

      assert result =~ "Verifique os erros"
      refute Arcada.Accounts.get_user_by_email(email)
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email, "password" => "valid_password"}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Entrar button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element(~s|main a[href="#{~p"/users/log_in"}"]|)
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log_in")

      assert login_html =~ "Entrar"
    end
  end
end
