defmodule ArcadaWeb.UnsubscribeLive do
  @moduledoc """
  Login-free unsubscribe, reached from the link in every subscription email.

  Mount only *reads* — cancelling takes a click. Mail clients and corporate link
  scanners fetch every URL in an email, so a page that unsubscribed on GET would
  silently cancel subscriptions nobody touched.
  """
  use ArcadaWeb, :live_view

  alias Arcada.Subscriptions

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md py-10">
      <.header class="text-center">
        Cancelar subscrição
      </.header>

      <div :if={@subscription} class="mt-8 space-y-6 text-center">
        <p class="text-sm text-muted">
          Deixa de receber <span class="font-medium text-ink">{describe(@subscription)}</span>.
        </p>

        <.button phx-click="unsubscribe" phx-disable-with="A cancelar...">
          Confirmar cancelamento
        </.button>

        <p class="text-xs text-muted">
          Enganou-se? Feche esta página — nada muda até confirmar.
        </p>
      </div>

      <p :if={is_nil(@subscription)} class="mt-8 text-center text-sm text-muted">
        Esta ligação já não é válida. A subscrição pode já ter sido cancelada.
      </p>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    subscription =
      case Subscriptions.fetch_by_unsubscribe_token(token) do
        {:ok, subscription} -> subscription
        :error -> nil
      end

    {:ok,
     socket
     |> assign(:subscription, subscription)
     |> assign(:page_title, "Cancelar subscrição")
     # A one-off page reached from an email is not something search engines
     # should hold; the token in the URL is also nobody else's business.
     |> assign(:page_noindex, true)}
  end

  def handle_event("unsubscribe", _params, %{assigns: %{subscription: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("unsubscribe", _params, socket) do
    {:ok, _subscription} = Subscriptions.set_active(socket.assigns.subscription, false)

    {:noreply,
     socket
     |> assign(:subscription, nil)
     |> put_flash(:info, "Subscrição cancelada. Não voltará a receber estes emails.")}
  end

  defp describe(%{query: nil, period: period}),
    do: "o resumo #{String.downcase(Subscriptions.period_label(period))} de tudo o que sai"

  defp describe(%{query: query, period: period}),
    do: "«#{query}» (#{String.downcase(Subscriptions.period_label(period))})"
end
