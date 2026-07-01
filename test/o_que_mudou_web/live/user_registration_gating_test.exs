defmodule OQueMudouWeb.UserRegistrationGatingTest do
  # async: false — these flip global application config (daily cap / timing
  # gate), so they must not run concurrently with other tests.
  use OQueMudouWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import OQueMudou.AccountsFixtures

  describe "daily signup cap" do
    setup do
      original = Application.get_env(:o_que_mudou, :daily_signup_cap)
      Application.put_env(:o_que_mudou, :daily_signup_cap, 0)
      on_exit(fn -> Application.put_env(:o_que_mudou, :daily_signup_cap, original) end)
    end

    test "shows the closed banner when the cap is reached", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")
      assert html =~ "limite diário"
    end

    test "refuses to create an account when closed", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      lv
      |> form("#registration_form", user: valid_user_attributes(email: email))
      |> render_submit()

      refute OQueMudou.Accounts.get_user_by_email(email)
    end
  end

  describe "timing gate" do
    setup do
      original = Application.get_env(:o_que_mudou, :signup_min_fill_ms)
      Application.put_env(:o_que_mudou, :signup_min_fill_ms, 60_000)
      on_exit(fn -> Application.put_env(:o_que_mudou, :signup_min_fill_ms, original) end)
    end

    test "rejects submissions that arrive too fast", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      result =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit()

      assert result =~ "Verifique os erros"
      refute OQueMudou.Accounts.get_user_by_email(email)
    end
  end
end
