defmodule OQueMudouWeb.AdminLive do
  @moduledoc """
  Admin page to set the summarizer provider/model at runtime (overrides the
  env-var defaults). Gated at the edge by Authelia + the VPN ACL, and in-app by
  `OQueMudouWeb.Plugs.RequireAdminGroup`. See issue #19.
  """
  use OQueMudouWeb, :live_view

  alias OQueMudou.Admin
  alias OQueMudou.Admin.Setting
  alias OQueMudou.Register
  alias OQueMudou.Summarizer

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_settings(socket)}
  end

  defp assign_settings(socket) do
    settings = Admin.get_settings()

    assign(socket,
      form: to_form(Admin.change_settings(settings), as: :setting),
      api_key_set?: not is_nil(settings.api_key),
      effective_adapter: Summarizer.adapter() |> Module.split() |> List.last()
    )
  end

  @impl true
  def handle_event("validate", %{"setting" => params}, socket) do
    changeset =
      Admin.get_settings()
      |> Admin.change_settings(Map.delete(params, "api_key"))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :setting))}
  end

  def handle_event("save", %{"setting" => params}, socket) do
    case Admin.update_settings(params) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> put_flash(:info, "Configuração guardada. Aplica-se ao próximo resumo.")
         |> assign_settings()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :setting))}
    end
  end

  def handle_event("test_summarize", _params, socket) do
    case Register.list_acts(limit: 1) do
      [act | _] ->
        Summarizer.enqueue(act.id)

        {:noreply,
         put_flash(
           socket,
           :info,
           "Resumo do diploma mais recente (##{act.id}) enfileirado com a configuração atual."
         )}

      [] ->
        {:noreply, put_flash(socket, :error, "Não há diplomas para testar.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl py-8">
      <header class="border-b-2 border-rule-strong pb-4">
        <p class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">Admin</p>
        <h1 class="mt-1 font-display text-2xl font-semibold text-ink">Resumidor</h1>
        <p class="mt-2 text-sm text-muted">
          Adaptador em uso agora: <span class="font-semibold text-ink">{@effective_adapter}</span>.
          Campos vazios usam o valor por defeito das variáveis de ambiente.
        </p>
      </header>

      <.form
        id="summarizer-form"
        for={@form}
        as={:setting}
        phx-change="validate"
        phx-submit="save"
        class="mt-8 space-y-8"
      >
        <.field field={@form[:summarizer_adapter]} type="select" label="Adaptador">
          <option value="">— usar defeito (env) —</option>
          <option
            :for={a <- Setting.adapters()}
            value={a}
            selected={to_string(@form[:summarizer_adapter].value) == a}
          >
            {a}
          </option>
        </.field>

        <fieldset class="space-y-5 border-t border-border pt-6">
          <legend class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
            Claude API
          </legend>
          <.field field={@form[:api_model]} label="Modelo (api)" placeholder="claude-sonnet-4-6" />
          <.field
            name="setting[api_key]"
            type="password"
            value=""
            autocomplete="off"
            label={"API key " <> if(@api_key_set?, do: "(guardada — deixar vazio para manter)", else: "(nenhuma)")}
          />
        </fieldset>

        <fieldset class="space-y-5 border-t border-border pt-6">
          <legend class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
            SSH (claude -p)
          </legend>
          <.field field={@form[:ssh_host]} label="Host" placeholder="192.0.2.10" />
          <.field field={@form[:ssh_user]} label="Utilizador" placeholder="naps62" />
          <.field
            field={@form[:ssh_claude_cmd]}
            label="Comando claude"
            placeholder="claude -p --output-format json"
          />
          <.field field={@form[:ssh_model]} label="Modelo (ssh)" placeholder="claude-cli" />
        </fieldset>

        <div class="flex items-center justify-between gap-6 border-t border-border pt-6">
          <button
            type="submit"
            class="rounded-md bg-ink px-4 py-2 text-sm font-semibold text-bg hover:opacity-90"
          >
            Guardar
          </button>
          <button
            type="button"
            phx-click="test_summarize"
            class="text-sm font-medium text-primary hover:underline"
          >
            Testar: resumir o diploma mais recente
          </button>
        </div>
      </.form>

      <p class="mt-6 text-xs text-muted">
        Nota: a concorrência da fila de resumos é fixada no arranque — mudar de
        adaptador exige reiniciar a aplicação para a ajustar.
      </p>
    </div>
    """
  end

  # Theme-aware form field (the default core_components input hardcodes
  # bg-white/zinc, which breaks dark mode). Uses the app's semantic tokens.
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :name, :string, default: nil
  attr :id, :string, default: nil
  attr :value, :string, default: nil
  attr :rest, :global, include: ~w(placeholder autocomplete)
  slot :inner_block

  defp field(assigns) do
    assigns =
      assigns
      |> assign(:name, assigns.name || (assigns.field && assigns.field.name))
      |> assign(:id, assigns.id || (assigns.field && assigns.field.id))
      |> assign(
        :resolved_value,
        if(is_nil(assigns.value) and assigns.field, do: assigns.field.value, else: assigns.value)
      )

    ~H"""
    <div>
      <label for={@id} class="block text-sm font-medium text-ink">{@label}</label>
      <select
        :if={@type == "select"}
        id={@id}
        name={@name}
        class={input_class()}
        {@rest}
      >
        {render_slot(@inner_block)}
      </select>
      <input
        :if={@type != "select"}
        type={@type}
        id={@id}
        name={@name}
        value={@resolved_value}
        class={input_class()}
        {@rest}
      />
    </div>
    """
  end

  defp input_class do
    "mt-1.5 block w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-ink " <>
      "placeholder:text-muted/60 focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
  end
end
