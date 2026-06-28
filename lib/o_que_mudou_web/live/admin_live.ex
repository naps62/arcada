defmodule OQueMudouWeb.AdminLive do
  @moduledoc """
  Admin hub (`/admin`): pick the active summarizer provider + model (used by the
  daily cron / auto-summarize) and manage provider instances. Gated by Authelia +
  VPN ACL at the edge and `RequireAdminGroup` in-app. See issues #19, #20.
  """
  use OQueMudouWeb, :live_view

  alias OQueMudou.{Admin, Providers}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load(socket)}
  end

  defp load(socket) do
    settings = Admin.get_settings()
    providers = Providers.list_providers()

    socket
    |> assign(providers: providers, settings: settings)
    |> assign(selected_id: settings.active_provider_id)
    |> assign(form: to_form(Admin.change_settings(settings), as: :setting))
  end

  @impl true
  def handle_event("validate", %{"setting" => params}, socket) do
    {:noreply, assign(socket, selected_id: parse_id(params["active_provider_id"]))}
  end

  def handle_event("save", %{"setting" => params}, socket) do
    case Admin.update_settings(params) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Ativo atualizado.") |> load()}
      {:error, cs} -> {:noreply, assign(socket, form: to_form(cs, as: :setting))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id |> Providers.get_provider!() |> Providers.delete_provider()
    {:noreply, socket |> put_flash(:info, "Provider removido.") |> load()}
  end

  defp parse_id(""), do: nil
  defp parse_id(nil), do: nil
  defp parse_id(s), do: String.to_integer(s)

  defp selected_provider(providers, id), do: Enum.find(providers, &(&1.id == id))

  defp model_options(nil), do: []
  defp model_options(provider), do: provider.models

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, :selected, selected_provider(assigns.providers, assigns.selected_id))

    ~H"""
    <div class="mx-auto max-w-2xl py-8">
      <header class="border-b-2 border-rule-strong pb-4">
        <p class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">Admin</p>
        <h1 class="mt-1 font-display text-2xl font-semibold text-ink">Resumidor</h1>
        <p class="mt-2 text-sm text-muted">
          O provider+modelo ativo é usado nos resumos automáticos. Podes correr
          qualquer ato com qualquer provider/modelo na página de cada ato.
        </p>
      </header>

      <section class="mt-8">
        <h2 class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">Ativo</h2>
        <.form
          id="active-form"
          for={@form}
          as={:setting}
          phx-change="validate"
          phx-submit="save"
          class="mt-3 space-y-5"
        >
          <.admin_field field={@form[:active_provider_id]} type="select" label="Provider">
            <option value="">— nenhum (resumos ficam por gerar) —</option>
            <option
              :for={p <- @providers}
              value={p.id}
              selected={@selected_id == p.id}
            >
              {p.name} ({p.kind})
            </option>
          </.admin_field>

          <.admin_field
            field={@form[:active_model]}
            type="select"
            label="Modelo"
            hint={@selected && "Modelos de #{@selected.name}"}
          >
            <option value="">— escolher —</option>
            <option
              :for={m <- model_options(@selected)}
              value={m}
              selected={to_string(@form[:active_model].value) == m}
            >
              {m}
            </option>
          </.admin_field>

          <button
            type="submit"
            class="rounded-md bg-ink px-4 py-2 text-sm font-semibold text-bg hover:opacity-90"
          >
            Guardar ativo
          </button>
        </.form>
      </section>

      <section class="mt-10">
        <div class="flex items-center justify-between border-b border-border pb-2">
          <h2 class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
            Providers
          </h2>
          <.link
            navigate={~p"/admin/providers/new"}
            class="text-sm font-medium text-primary hover:underline"
          >
            + novo
          </.link>
        </div>

        <p :if={@providers == []} class="mt-4 text-sm text-muted">
          Ainda não há providers. Cria o primeiro.
        </p>

        <ul class="mt-2 divide-y divide-border">
          <li :for={p <- @providers} class="flex items-center justify-between gap-4 py-3">
            <div class="min-w-0">
              <p class="font-display text-base text-ink">
                {p.name}
                <span class="ml-1 text-xs text-muted">· {p.kind}</span>
                <span :if={not p.enabled} class="ml-1 text-xs text-state-error-ink">(desativado)</span>
              </p>
              <p class="truncate text-xs text-muted">
                {Enum.join(p.models, ", ")}
              </p>
            </div>
            <div class="flex shrink-0 items-center gap-3 text-sm">
              <.link navigate={~p"/admin/providers/#{p.id}/edit"} class="text-primary hover:underline">
                editar
              </.link>
              <button
                phx-click="delete"
                phx-value-id={p.id}
                data-confirm={"Remover o provider #{p.name}?"}
                class="text-muted hover:text-state-error-ink"
              >
                remover
              </button>
            </div>
          </li>
        </ul>
      </section>
    </div>
    """
  end
end
