defmodule ArcadaWeb.UserSessionController do
  use ArcadaWeb, :controller

  alias Arcada.Accounts
  alias Arcada.Accounts.User
  alias ArcadaWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Conta criada. Confirme o email que lhe enviámos para a activar.")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Palavra-passe actualizada com sucesso!")
  end

  def create(conn, params) do
    create(conn, params, "Bem-vindo de volta!")
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    case Accounts.get_user_by_email_and_password(email, password) do
      # Credentials check out but the account is unverified: no session. Naming
      # the reason is safe *here* specifically because this branch is only
      # reachable by someone who already supplied the right password — it tells
      # an attacker nothing they don't have. The generic error below is what
      # keeps the endpoint useless for enumeration, so the password check must
      # stay ahead of this one.
      %User{confirmed_at: nil} ->
        conn
        |> put_flash(
          :error,
          "A sua conta ainda não está confirmada. Verifique o email que lhe enviámos."
        )
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/confirm")

      %User{} = user ->
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      nil ->
        conn
        |> put_flash(:error, "Email ou palavra-passe inválidos")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log_in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Sessão terminada.")
    |> UserAuth.log_out_user()
  end
end
