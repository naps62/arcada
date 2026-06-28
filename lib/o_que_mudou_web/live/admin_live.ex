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

      <.simple_form
        id="summarizer-form"
        for={@form}
        as={:setting}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:summarizer_adapter]}
          type="select"
          label="Adaptador"
          prompt="— usar defeito (env) —"
          options={Setting.adapters()}
        />

        <fieldset class="border-t border-border pt-5">
          <legend class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
            Claude API
          </legend>
          <.input field={@form[:api_model]} label="Modelo (api)" placeholder="claude-sonnet-4-6" />
          <.input
            type="password"
            name="setting[api_key]"
            value=""
            label={"API key " <> if(@api_key_set?, do: "(guardada — deixar vazio para manter)", else: "(nenhuma)")}
            autocomplete="off"
          />
        </fieldset>

        <fieldset class="border-t border-border pt-5">
          <legend class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
            SSH (claude -p)
          </legend>
          <.input field={@form[:ssh_host]} label="Host" placeholder="192.0.2.10" />
          <.input field={@form[:ssh_user]} label="Utilizador" placeholder="naps62" />
          <.input
            field={@form[:ssh_claude_cmd]}
            label="Comando claude"
            placeholder="claude -p --output-format json"
          />
          <.input field={@form[:ssh_model]} label="Modelo (ssh)" placeholder="claude-cli" />
        </fieldset>

        <:actions>
          <.button>Guardar</.button>
          <button
            type="button"
            phx-click="test_summarize"
            class="text-sm font-medium text-primary hover:underline"
          >
            Testar: resumir o diploma mais recente
          </button>
        </:actions>
      </.simple_form>

      <p class="mt-6 text-xs text-muted">
        Nota: a concorrência da fila de resumos é fixada no arranque — mudar de
        adaptador exige reiniciar a aplicação para a ajustar.
      </p>
    </div>
    """
  end
end
