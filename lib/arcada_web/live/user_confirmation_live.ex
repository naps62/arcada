defmodule ArcadaWeb.UserConfirmationLive do
  use ArcadaWeb, :live_view

  alias Arcada.Accounts

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <div class="mx-auto max-w-sm text-center">
      <.header class="text-center">A confirmar a sua conta</.header>
      <p class="mt-4 text-sm text-muted">Um momento — já o encaminhamos.</p>
    </div>
    """
  end

  # Confirm as soon as the socket connects, rather than behind a button.
  # `connected?/1` is false on the initial dead render, so a mail scanner that
  # prefetches the link gets HTML and confirms nothing. That is the same
  # guarantee the button gave: the form was `phx-submit` with no `action`, so
  # confirming already required a live socket — the click protected nothing and
  # only cost the user a step.
  def mount(%{"token" => token}, _session, socket) do
    if connected?(socket) do
      confirm(socket, token)
    else
      {:ok, socket}
    end
  end

  # Deliberately no auto-login. A leaked token — forwarded mail, a shared link,
  # a mail server log — must confirm the address without also handing over a
  # session. Confirming an address is a low-stakes claim; a session is not.
  defp confirm(socket, token) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        {:ok,
         socket
         |> put_flash(:info, "Conta confirmada. Já pode entrar.")
         |> redirect(to: ~p"/users/log_in")}

      :error ->
        # An already-confirmed account means the link was visited twice (by the
        # user, or by something automated). Not worth alarming anyone about —
        # send them on quietly.
        case socket.assigns do
          %{current_user: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            {:ok, redirect(socket, to: ~p"/")}

          %{} ->
            {:ok,
             socket
             |> put_flash(:error, "O endereço de confirmação é inválido ou expirou.")
             |> redirect(to: ~p"/users/confirm")}
        end
    end
  end
end
