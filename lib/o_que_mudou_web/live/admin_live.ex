defmodule OQueMudouWeb.AdminLive do
  @moduledoc """
  Admin hub (`/admin`): pick the active summarizer provider + model (used by the
  daily cron / auto-summarize) and manage provider instances. Gated by Authelia +
  VPN ACL at the edge and `RequireAdminGroup` in-app. See issues #19, #20.
  """
  use OQueMudouWeb, :live_view_admin

  alias OQueMudou.{Admin, Providers}
  alias OQueMudou.Providers.Provider

  @default_cap 80_000

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
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Active selection updated.") |> load()}
      {:error, cs} -> {:noreply, assign(socket, form: to_form(cs, as: :setting))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id |> Providers.get_provider!() |> Providers.delete_provider()
    {:noreply, socket |> put_flash(:info, "Provider removed.") |> load()}
  end

  defp parse_id(""), do: nil
  defp parse_id(nil), do: nil
  defp parse_id(s), do: String.to_integer(s)

  defp selected_provider(providers, id), do: Enum.find(providers, &(&1.id == id))

  defp model_options(nil), do: []
  defp model_options(provider), do: provider.models

  # ── Saved-state readout helpers (what auto-summarize uses right now) ────────
  defp active_name(%{active_provider: %{name: n}}), do: n
  defp active_name(_), do: nil
  defp active_kind(%{active_provider: %{kind: k}}), do: k
  defp active_kind(_), do: nil

  # {effective_cap, default?} — null in the DB falls back to the 80k default.
  defp effective_cap(%{max_text_chars: n}) when is_integer(n), do: {n, false}
  defp effective_cap(_), do: {@default_cap, true}

  defp ranking_on?(%{embeddings_base_url: b}) when is_binary(b) and b != "", do: true
  defp ranking_on?(_), do: false

  defp fmt_int(n) when is_integer(n),
    do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:selected, selected_provider(assigns.providers, assigns.selected_id))
      |> assign(:configured?, not is_nil(assigns.settings.active_provider_id))

    ~H"""
    <header class="border-b-2 border-rule-strong pb-4">
      <h1 class="font-display text-[1.75rem] font-semibold leading-tight text-ink">Summarizer</h1>
      <p class="mt-2 max-w-prose text-sm leading-relaxed text-muted">
        The active provider and model run the automatic daily summaries. You can also run any act
        against any provider and model from that act's page.
      </p>
    </header>

    <%!-- ── What runs automatically: saved state, read-only ─────────────────── --%>
    <section aria-label="Active configuration" class="mt-8">
      <h2 class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
        Running now
      </h2>

      <%= if @configured? do %>
        <dl class="mt-3 grid grid-cols-2 gap-px overflow-hidden rounded-md border border-border bg-border sm:grid-cols-4">
          <.readout label="Provider">
            <span class="font-medium text-ink">{active_name(@settings)}</span>
            <span :if={active_kind(@settings)} class="ml-1 text-xs text-muted">
              {active_kind(@settings)}
            </span>
          </.readout>
          <.readout label="Model">
            <span class={[@settings.active_model && "font-medium text-ink", !@settings.active_model && "text-muted"]}>
              {@settings.active_model || "— not set —"}
            </span>
          </.readout>
          <.readout label="Long-text cap">
            <% {cap, default?} = effective_cap(@settings) %>
            <span class="font-medium tabular-nums text-ink">{fmt_int(cap)}</span>
            <span class="text-xs text-muted">chars{if default?, do: " · default"}</span>
          </.readout>
          <.readout label="Section ranking">
            <span class="font-medium text-ink">
              {if ranking_on?(@settings), do: "Relevant sections", else: "Truncate start"}
            </span>
          </.readout>
        </dl>
      <% else %>
        <p class="mt-3 flex items-start gap-2 rounded-md border border-border bg-surface px-4 py-3 text-sm text-muted">
          <.icon name="hero-pause-circle-micro" class="mt-0.5 size-4 shrink-0" />
          <span>
            Automatic summaries are <span class="font-medium text-ink">paused</span>.
            Pick a provider and model below to start generating them.
          </span>
        </p>
      <% end %>
    </section>

    <%!-- ── Edit the active selection + oversized-diploma handling ──────────── --%>
    <section aria-label="Settings" class="mt-8">
      <h2 class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">Settings</h2>

      <.form
        id="active-form"
        for={@form}
        as={:setting}
        phx-change="validate"
        phx-submit="save"
        class="mt-3 space-y-5"
      >
        <.admin_field field={@form[:active_provider_id]} type="select" label="Provider">
          <option value="">— none (summaries stay ungenerated) —</option>
          <option :for={p <- @providers} value={p.id} selected={@selected_id == p.id}>
            {p.name} ({p.kind})
          </option>
        </.admin_field>

        <.admin_field
          field={@form[:active_model]}
          type="select"
          label="Model"
          hint={@selected && "Models from #{@selected.name}"}
        >
          <option value="">— choose —</option>
          <option
            :for={m <- model_options(@selected)}
            value={m}
            selected={to_string(@form[:active_model].value) == m}
          >
            {m}
          </option>
        </.admin_field>

        <div class="border-t border-border pt-5">
          <h3 class="text-sm font-semibold text-ink">Long diplomas</h3>
          <p class="mt-1 max-w-prose text-xs leading-relaxed text-muted">
            Large acts (huge annexes) are cut to the limit below. With an embeddings server, instead
            of cutting from the start the most relevant sections (what actually changes) are kept and
            the trailing tables discarded.
          </p>
        </div>

        <.admin_field
          field={@form[:max_text_chars]}
          type="number"
          label="Character limit"
          hint="Empty = 80,000 (default)."
        />

        <.admin_field
          field={@form[:embeddings_base_url]}
          type="text"
          label="Embeddings server (base URL)"
          hint="OpenAI-compatible /v1/embeddings (llama.cpp, Ollama). Empty = truncate from the start."
        />

        <.admin_field
          field={@form[:embeddings_model]}
          type="text"
          label="Embeddings model"
          hint="e.g. nomic-embed-text"
        />

        <button
          type="submit"
          class="rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-fg transition-colors duration-150 ease-out-quart hover:bg-primary-hover"
        >
          Save changes
        </button>
      </.form>
    </section>

    <%!-- ── Provider instances ─────────────────────────────────────────────── --%>
    <section aria-label="Providers" class="mt-12">
      <div class="flex items-baseline justify-between gap-4 border-b-2 border-rule-strong pb-2">
        <h2 class="text-[0.6875rem] font-semibold uppercase tracking-[0.1em] text-muted">
          Providers
          <span :if={@providers != []} class="ml-1 font-normal tabular-nums">
            {length(@providers)}
          </span>
        </h2>
        <.link
          :if={@providers != []}
          navigate={~p"/admin/providers/new"}
          class="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
        >
          <.icon name="hero-plus-micro" class="size-4" /> New provider
        </.link>
      </div>

      <%= if @providers == [] do %>
        <div class="mt-4 rounded-md border border-dashed border-border px-6 py-10 text-center">
          <.icon name="hero-server-stack" class="mx-auto size-7 text-muted" />
          <p class="mt-3 font-display text-base text-ink">No providers yet</p>
          <p class="mx-auto mt-1 max-w-sm text-sm leading-relaxed text-muted">
            Add an Anthropic, OpenAI-compatible, or SSH backend to start generating summaries.
          </p>
          <.link
            navigate={~p"/admin/providers/new"}
            class="mt-5 inline-flex items-center gap-1 rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-fg transition-colors duration-150 ease-out-quart hover:bg-primary-hover"
          >
            <.icon name="hero-plus-micro" class="size-4" /> Add the first provider
          </.link>
        </div>
      <% else %>
        <ul class="mt-1 divide-y divide-border">
          <li :for={p <- @providers} class="flex flex-wrap items-center justify-between gap-x-4 gap-y-1.5 py-3.5">
            <div class="min-w-0">
              <p class="flex flex-wrap items-center gap-x-2 gap-y-1">
                <span class="font-display text-base text-ink">{p.name}</span>
                <span class="inline-flex items-center rounded-[3px] bg-surface-inset px-1.5 py-0.5 text-[0.6875rem] font-medium uppercase tracking-[0.04em] text-muted">
                  {p.kind}
                </span>
                <span
                  :if={p.id == @settings.active_provider_id}
                  class="inline-flex items-center gap-1 text-[0.6875rem] font-semibold uppercase tracking-[0.06em] text-primary"
                >
                  <.icon name="hero-bolt-micro" class="size-3.5" /> active
                </span>
                <span
                  :if={not p.enabled}
                  class="inline-flex items-center gap-1 text-[0.6875rem] font-medium uppercase tracking-[0.06em] text-muted"
                >
                  <.icon name="hero-no-symbol-micro" class="size-3.5" /> disabled
                </span>
              </p>
              <p class="mt-0.5 truncate text-xs text-muted">
                {(p.models != [] && Enum.join(p.models, ", ")) || "no models"}
                <span aria-hidden="true" class="mx-1 text-border">·</span>
                {Provider.max_concurrency(p)}× concurrent
              </p>
            </div>
            <div class="flex shrink-0 items-center gap-3 text-sm">
              <.link
                navigate={~p"/admin/providers/#{p.id}/edit"}
                class="font-medium text-primary hover:underline"
              >
                Edit
              </.link>
              <button
                phx-click="delete"
                phx-value-id={p.id}
                data-confirm={"Remove provider #{p.name}?"}
                class="text-muted transition-colors duration-150 ease-out-quart hover:text-state-error-ink"
              >
                Remove
              </button>
            </div>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end

  # A single labelled cell in the read-only "Running now" readout.
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp readout(assigns) do
    ~H"""
    <div class="bg-surface px-3 py-2.5">
      <dt class="text-[0.625rem] font-semibold uppercase tracking-[0.1em] text-muted">{@label}</dt>
      <dd class="mt-1 text-sm">{render_slot(@inner_block)}</dd>
    </div>
    """
  end
end
