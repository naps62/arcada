defmodule OQueMudouWeb.ProviderFormLive do
  @moduledoc """
  Create / edit a summarizer `Provider` (`/admin/providers/new`,
  `/admin/providers/:id/edit`). Kind-specific fields show based on the selected
  kind. See issue #20.
  """
  use OQueMudouWeb, :live_view_admin

  alias OQueMudou.Providers
  alias OQueMudou.Providers.Provider

  @impl true
  def mount(params, _session, socket) do
    {provider, title} =
      case params do
        %{"id" => id} -> {Providers.get_provider!(id), "Edit provider"}
        _ -> {%Provider{kind: :anthropic, models: []}, "New provider"}
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
        {:noreply, socket |> put_flash(:info, "Provider saved.") |> push_navigate(to: ~p"/admin")}

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
    <div class="max-w-3xl">
      <nav aria-label="Breadcrumb" class="text-[0.8125rem] text-muted">
        <.link navigate={~p"/admin"} class="hover:text-primary hover:underline">Admin</.link>
        <span aria-hidden="true" class="mx-1.5 text-border">/</span>
        <span class="text-ink">{@title}</span>
      </nav>

      <h1 class="mt-4 border-b-2 border-rule-strong pb-3 font-display text-[1.75rem] font-semibold text-ink">
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
        <.admin_field field={@form[:name]} label="Name" placeholder="e.g. ollama-local" />

        <.admin_field field={@form[:kind]} type="select" label="Type">
          <option :for={k <- Provider.kinds()} value={k} selected={@kind == k}>{k}</option>
        </.admin_field>

        <.admin_field
          :if={@kind == :openai}
          field={@form[:base_url]}
          label="Base URL"
          placeholder="https://api.synthetic.new/v1"
          hint="OpenAI-compatible endpoint (without /chat/completions)."
        />

        <.admin_field
          :if={@kind in [:anthropic, :openai]}
          field={@form[:api_key]}
          type="password"
          name="provider[api_key]"
          value=""
          autocomplete="off"
          label={"API key " <> if(@api_key_set?, do: "(stored — leave blank to keep)", else: "")}
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
            label="Command"
            placeholder="claude -p --output-format json"
          />
        <% end %>

        <.admin_field
          field={@form[:models]}
          type="textarea"
          rows="4"
          label="Models"
          hint="One per line (or comma-separated)."
          value={Enum.join(@provider.models || [], "\n")}
        />

        <.admin_field
          field={@form[:max_concurrency]}
          type="number"
          min="1"
          label="Max concurrency"
          hint={
          "Parallel summarize jobs for this provider. SSH must stay at 1; " <>
            "API providers can go higher. Blank uses the per-type default (SSH 1, API 5)."
        }
        />

        <label class="flex items-center gap-2 text-sm text-ink">
          <input type="hidden" name="provider[enabled]" value="false" />
          <input
            type="checkbox"
            name="provider[enabled]"
            value="true"
            checked={@form[:enabled].value != false}
            class="rounded border-border text-primary focus:ring-primary"
          /> Enabled
        </label>

        <div class="flex items-center gap-3 border-t border-border pt-5">
          <button
            type="submit"
            class="rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-fg transition-colors duration-150 ease-out-quart hover:bg-primary-hover"
          >
            Save provider
          </button>
          <.link
            navigate={~p"/admin"}
            class="text-sm font-medium text-muted hover:text-primary hover:underline"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end
end
