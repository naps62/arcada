defmodule OQueMudouWeb.UserRegistrationLive do
  use OQueMudouWeb, :live_view

  alias OQueMudou.Accounts
  alias OQueMudou.Accounts.User
  alias OQueMudouWeb.Turnstile

  # Reject submits that arrive faster than a human could plausibly fill the
  # form — a cheap bot filter alongside the honeypot field and Turnstile.
  # Configurable so the test suite (instant submits) can disable it.
  @default_min_fill_ms 2_000

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Criar conta
        <:subtitle>
          Já tem conta? <.link
            navigate={~p"/users/log_in"}
            class="font-semibold text-primary hover:underline"
          >
            Entrar
          </.link>.
        </:subtitle>
      </.header>

      <div
        :if={not @signups_open}
        class="mt-6 rounded-lg border border-amber-300 bg-amber-50 p-4 text-sm text-amber-900"
      >
        As inscrições atingiram o limite diário. Volte a tentar amanhã.
      </div>

      <.simple_form
        for={@form}
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={~p"/users/log_in?_action=registered"}
        method="post"
      >
        <.error :if={@check_errors}>
          Algo correu mal. Verifique os erros abaixo.
        </.error>

        <.input field={@form[:email]} type="email" label="Email" required />
        <.input
          field={@form[:username]}
          type="text"
          label="Nome de utilizador (opcional)"
        />
        <.input field={@form[:password]} type="password" label="Palavra-passe" required />

        <%!-- Honeypot: positioned off-screen so humans never see it but bots
             that fill every field trip it. Any value = bot. --%>
        <div aria-hidden="true" style="position:absolute; left:-9999px; top:-9999px;">
          <label for="hp_name">Não preencher</label>
          <input id="hp_name" type="text" name="hp_name" tabindex="-1" autocomplete="off" />
        </div>

        <div :if={@turnstile_site_key} id="turnstile-widget" phx-update="ignore">
          <div class="cf-turnstile" data-sitekey={@turnstile_site_key}></div>
        </div>

        <:actions>
          <.button phx-disable-with="A criar conta..." class="w-full" disabled={not @signups_open}>
            Criar conta
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign(signups_open: Accounts.signups_open?())
      |> assign(turnstile_site_key: Turnstile.site_key())
      |> assign(mounted_at: System.monotonic_time(:millisecond))
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params} = params, socket) do
    cond do
      bot_suspected?(params, socket) ->
        # Look like an ordinary validation failure — don't teach the bot which
        # signal tripped, and never send an email. Set check_errors *after*
        # assign_form, which would otherwise clear it for a valid changeset.
        {:noreply,
         socket
         |> assign_form(Accounts.change_user_registration(%User{}, user_params))
         |> assign(check_errors: true)}

      not Accounts.signups_open?() ->
        {:noreply,
         socket
         |> assign(signups_open: false)
         |> assign_form(Accounts.change_user_registration(%User{}, user_params))}

      Turnstile.verify(params["cf-turnstile-response"]) != :ok ->
        {:noreply,
         socket
         |> put_flash(:error, "Falha na verificação anti-robô. Tente novamente.")
         |> push_event("turnstile-reset", %{})
         |> assign_form(Accounts.change_user_registration(%User{}, user_params))}

      true ->
        register(socket, user_params)
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp register(socket, user_params) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(check_errors: true)
         |> push_event("turnstile-reset", %{})
         |> assign_form(changeset)}
    end
  end

  defp bot_suspected?(params, socket) do
    honeypot_filled?(params) or too_fast?(socket)
  end

  defp honeypot_filled?(params), do: String.trim(params["hp_name"] || "") != ""

  defp too_fast?(socket) do
    min_fill_ms = Application.get_env(:o_que_mudou, :signup_min_fill_ms, @default_min_fill_ms)

    case socket.assigns[:mounted_at] do
      nil -> false
      ms -> System.monotonic_time(:millisecond) - ms < min_fill_ms
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
