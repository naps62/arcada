defmodule ArcadaWeb.UserSubscriptionsLive do
  @moduledoc """
  Manage standing email subscriptions (issue #95).

  One form covers both shapes the domain has: leaving the query blank *is* the
  "everything" digest, so the choice is a two-option radio rather than a second
  form. Picking "tudo o que sai" hides the query box and drops the daily
  cadence, which the domain refuses for a digest.
  """
  use ArcadaWeb, :live_view

  alias Arcada.Subscriptions
  alias Arcada.Subscriptions.Subscription

  @impl true
  def render(assigns) do
    ~H"""
    <.header class="text-center">
      Subscrições
      <:subtitle>
        Receba por email o que sai sobre um tema, ou um resumo de tudo.
      </:subtitle>
    </.header>

    <div class="mt-10 space-y-12 divide-y">
      <div :if={at_limit?(@subscriptions)}>
        <p class="text-sm text-muted">
          Atingiu o limite de {Subscriptions.subscription_count_label(Subscriptions.max_per_user())}.
          Apague uma abaixo para poder criar outra.
        </p>
      </div>

      <div :if={not at_limit?(@subscriptions)}>
        <h2 class="text-sm font-semibold uppercase tracking-[0.1em] text-muted">
          Nova subscrição
        </h2>

        <.simple_form for={@form} id="subscription_form" phx-submit="create" phx-change="validate">
          <fieldset>
            <legend class="text-sm font-semibold leading-6 text-ink">O que quer receber</legend>

            <label class="mt-2 flex items-start gap-3 text-sm text-ink">
              <input
                type="radio"
                name="kind"
                value="tema"
                checked={@kind == "tema"}
                class="mt-1 h-4 w-4 border-border text-primary focus:ring-primary"
              />
              <span>
                Um tema
                <span class="block text-xs text-muted">
                  Procuramos por si e só escrevemos quando há algo relevante.
                </span>
              </span>
            </label>

            <label class="mt-3 flex items-start gap-3 text-sm text-ink">
              <input
                type="radio"
                name="kind"
                value="tudo"
                checked={@kind == "tudo"}
                class="mt-1 h-4 w-4 border-border text-primary focus:ring-primary"
              />
              <span>
                Tudo o que sai
                <span class="block text-xs text-muted">
                  Um resumo periódico de todos os diplomas publicados.
                </span>
              </span>
            </label>
          </fieldset>

          <.input
            :if={@kind == "tema"}
            field={@form[:query]}
            type="text"
            label="Tema"
            placeholder="renda de casa"
          />

          <.input
            field={@form[:period]}
            type="select"
            label="Frequência"
            options={period_options(@kind)}
          />

          <:actions>
            <.button phx-disable-with="A guardar...">Subscrever</.button>
          </:actions>
        </.simple_form>
      </div>

      <div class="pt-12">
        <h2 class="text-sm font-semibold uppercase tracking-[0.1em] text-muted">
          As suas subscrições
        </h2>

        <p :if={@subscriptions == []} class="mt-4 text-sm text-muted">
          Ainda não subscreveu nada.
        </p>

        <ul :if={@subscriptions != []} class="mt-4 divide-y border-y border-border">
          <li
            :for={subscription <- @subscriptions}
            id={"subscription-#{subscription.id}"}
            class="flex flex-wrap items-center justify-between gap-3 py-4"
          >
            <div>
              <p class="text-sm font-medium text-ink">{describe(subscription)}</p>
              <p class="text-xs text-muted">
                {Subscriptions.period_label(subscription.period)}
                <span aria-hidden="true">·</span>
                {status(subscription)}
              </p>
            </div>

            <div class="flex items-center gap-3 text-xs font-semibold uppercase tracking-[0.08em]">
              <button
                type="button"
                phx-click="toggle"
                phx-value-id={subscription.id}
                class="rounded-sm px-1 py-1 text-muted transition-colors hover:text-primary"
              >
                {if subscription.active, do: "Pausar", else: "Retomar"}
              </button>
              <button
                type="button"
                phx-click="delete"
                phx-value-id={subscription.id}
                class="rounded-sm px-1 py-1 text-muted transition-colors hover:text-primary"
              >
                Apagar
              </button>
            </div>
          </li>
        </ul>

        <p :if={not at_limit?(@subscriptions)} class="mt-4 text-xs text-muted">
          Pode ter até {Subscriptions.subscription_count_label(Subscriptions.max_per_user())}.
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Subscrições")
     |> assign(:kind, "tema")
     |> assign_form(Subscriptions.change_subscription(%Subscription{}))
     |> load_subscriptions()}
  end

  @impl true
  def handle_event("validate", params, socket) do
    kind = kind_param(params)

    changeset =
      %Subscription{}
      |> Subscriptions.change_subscription(subscription_params(params, kind))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:kind, kind) |> assign_form(changeset)}
  end

  def handle_event("create", params, socket) do
    kind = kind_param(params)

    case Subscriptions.create_subscription(
           socket.assigns.current_user,
           subscription_params(params, kind)
         ) do
      {:ok, _subscription} ->
        {:noreply,
         socket
         |> put_flash(:info, "Subscrição criada.")
         |> assign(:kind, kind)
         |> assign_form(Subscriptions.change_subscription(%Subscription{}))
         |> load_subscriptions()}

      {:error, changeset} ->
        {:noreply, socket |> assign(:kind, kind) |> assign_form(changeset)}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    subscription = Subscriptions.get_user_subscription!(socket.assigns.current_user, id)
    {:ok, _subscription} = Subscriptions.set_active(subscription, not subscription.active)

    {:noreply, load_subscriptions(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    subscription = Subscriptions.get_user_subscription!(socket.assigns.current_user, id)
    {:ok, _subscription} = Subscriptions.delete_subscription(subscription)

    {:noreply, socket |> put_flash(:info, "Subscrição apagada.") |> load_subscriptions()}
  end

  defp load_subscriptions(socket) do
    assign(
      socket,
      :subscriptions,
      Subscriptions.list_user_subscriptions(socket.assigns.current_user)
    )
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  defp kind_param(%{"kind" => kind}) when kind in ~w(tema tudo), do: kind
  defp kind_param(_params), do: "tema"

  # The "tudo" shape *is* a blank query, so the radio choice is applied to the
  # params rather than carried as a field. Daily goes with it: the domain
  # rejects a daily digest, and an unreachable option left selected in the
  # select would only produce a validation error the user can't act on.
  defp subscription_params(params, kind) do
    attrs = Map.get(params, "subscription", %{})

    case kind do
      "tudo" -> attrs |> Map.put("query", nil) |> Map.update("period", nil, &digest_period/1)
      "tema" -> attrs
    end
  end

  defp digest_period("diaria"), do: "semanal"
  defp digest_period(period), do: period

  defp period_options(kind) do
    periods = if kind == "tudo", do: Subscriptions.digest_periods(), else: Subscriptions.periods()

    Enum.map(periods, &{Subscriptions.period_label(&1), &1})
  end

  # `>=`, not `==`: accounts created before the cap was lowered (issue #97) keep
  # the rows they have.
  defp at_limit?(subscriptions), do: length(subscriptions) >= Subscriptions.max_per_user()

  defp describe(%{query: nil}), do: "Tudo o que sai"
  defp describe(%{query: query}), do: "«#{query}»"

  defp status(%{active: false}), do: "em pausa"
  defp status(%{last_sent_at: nil}), do: "ainda não enviada"

  defp status(%{last_sent_at: sent_at}),
    do: "último envio a #{format_pt_date(DateTime.to_date(sent_at))}"
end
