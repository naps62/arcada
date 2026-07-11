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
    test "creates account and redirects to login without logging in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      assert {:error, {:live_redirect, %{to: to}}} = render_submit(form)
      assert to == ~p"/users/log_in"

      # Account exists, but registration no longer auto-logs the user in — the
      # session stays anonymous so a fresh signup and a duplicate look identical.
      assert Arcada.Accounts.get_user_by_email(email)

      conn = get(conn, "/")
      response = html_response(conn, 200)
      refute response =~ "Sair"
    end

    test "creates account with an optional username", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      form =
        form(lv, "#registration_form",
          user: valid_user_attributes(email: email, username: "handle")
        )

      assert {:error, {:live_redirect, %{to: to}}} = render_submit(form)
      assert to == ~p"/users/log_in"

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

    test "masks a duplicated email as a successful signup", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      form =
        form(lv, "#registration_form",
          user: %{"email" => user.email, "password" => "valid_password"}
        )

      # Identical response to a fresh signup — no field error, same redirect —
      # so submit can't be used to enumerate accounts (#63).
      result = render_submit(form)

      assert {:error, {:live_redirect, %{to: to}}} = result
      assert to == ~p"/users/log_in"
      refute inspect(result) =~ "has already been taken"
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
