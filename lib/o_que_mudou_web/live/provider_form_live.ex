defmodule OQueMudouWeb.ProviderFormLive do
  @moduledoc """
  Create / edit a summarizer `Provider` (`/admin/providers/new`,
  `/admin/providers/:id/edit`). Kind-specific fields show based on the selected
  kind. See issue #20.
  """
  use OQueMudouWeb, :live_view

  alias OQueMudou.Providers
  alias OQueMudou.Providers.Provider

  @impl true
  def mount(params, _session, socket) do
    {provider, title} =
      case params do
        %{"id" => id} -> {Providers.get_provider!(id), "Editar provider"}
        _ -> {%Provider{kind: :anthropic, models: []}, "Novo provider"}
      end

    {:ok,
     socket
     |> assign(provider: provider, title: title, kind: provider.kind || :anthropic)
     |> assign(api_key_set?: not is_nil(provider.api_key))
     |> assign_form(Providers.change_provider(provider))}
  end

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset, as: :provider))

  @impl true
  def handle_event("validate", %{"provider" => params}, socket) do
    changeset =
      socket.assigns.provider
      |> Providers.change_provider(drop_blank_key(params, socket))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(kind: parse_kind(params["kind"])) |> assign_form(changeset)}
  end

  def handle_event("save", %{"provider" => params}, socket) do
    params = drop_blank_key(params, socket)

    saved =
      case socket.assigns.provider do
        %Provider{id: nil} -> Providers.create_provider(params)
        existing -> Providers.update_provider(existing, params)
      end

    case saved do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Provider guardado.") |> push_navigate(to: ~p"/admin")}

      {:error, cs} ->
        {:noreply, assign_form(socket, cs)}
    end
  end

  # On edit, a blank api_key means "keep the stored one".
  defp drop_blank_key(params, %{assigns: %{provider: %Provider{id: id}}}) when not is_nil(id) do
    case params["api_key"] do
      blank when blank in [nil, ""] -> Map.delete(params, "api_key")
      _ -> params
    end
  end

  defp drop_blank_key(params, _socket), do: params

  defp parse_kind(k) when k in ~w(anthropic openai ssh), do: String.to_existing_atom(k)
  defp parse_kind(_), do: :anthropic

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl py-8">
      <.link navigate={~p"/admin"} class="text-sm text-muted hover:text-primary hover:underline">
        ← Admin
      </.link>
      <h1 class="mt-4 border-b-2 border-rule-strong pb-3 font-display text-2xl font-semibold text-ink">
        {@title}
      </h1>

      <.form
        id="provider-form"
        for={@form}
        as={:provider}
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-5"
      >
        <.admin_field field={@form[:name]} label="Nome" placeholder="ex. ollama-local" />

        <.admin_field field={@form[:kind]} type="select" label="Tipo">
          <option :for={k <- Provider.kinds()} value={k} selected={@kind == k}>{k}</option>
        </.admin_field>

        <.admin_field
          :if={@kind == :openai}
          field={@form[:base_url]}
          label="Base URL"
          placeholder="https://api.synthetic.new/v1"
          hint="Endpoint compatível com OpenAI (sem /chat/completions)."
        />

        <.admin_field
          :if={@kind in [:anthropic, :openai]}
          field={@form[:api_key]}
          type="password"
          name="provider[api_key]"
          value=""
          autocomplete="off"
          label={"API key " <> if(@api_key_set?, do: "(guardada — vazio mantém)", else: "")}
        />

        <%= if @kind == :ssh do %>
          <.admin_field field={@form[:ssh_host]} label="SSH host" placeholder="192.0.2.10" />
          <.admin_field field={@form[:ssh_user]} label="SSH user" placeholder="naps62" />
          <.admin_field
            field={@form[:ssh_identity_file]}
            label="Identity file"
            placeholder="/tmp/.ssh/id_ed25519"
          />
          <.admin_field
            field={@form[:ssh_claude_cmd]}
            label="Comando"
            placeholder="claude -p --output-format json"
          />
        <% end %>

        <.admin_field
          field={@form[:models]}
          type="textarea"
          rows="4"
          label="Modelos"
          hint="Um por linha (ou separados por vírgula)."
          value={Enum.join(@provider.models || [], "\n")}
        />

        <label class="flex items-center gap-2 text-sm text-ink">
          <input type="hidden" name="provider[enabled]" value="false" />
          <input
            type="checkbox"
            name="provider[enabled]"
            value="true"
            checked={@form[:enabled].value != false}
          /> Ativado
        </label>

        <button
          type="submit"
          class="rounded-md bg-ink px-4 py-2 text-sm font-semibold text-bg hover:opacity-90"
        >
          Guardar
        </button>
      </.form>
    </div>
    """
  end
end
