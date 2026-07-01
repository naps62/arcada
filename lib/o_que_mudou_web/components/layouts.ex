defmodule OQueMudouWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use OQueMudouWeb, :controller` and
  `use OQueMudouWeb, :live_view`.
  """
  use OQueMudouWeb, :html

  alias Phoenix.LiveView.JS

  embed_templates "layouts/*"

  # Sidebar sections for the admin shell. Adding a page = add a route + one
  # entry here (see issue #29). `:external` marks the seam where the link leaves
  # the app shell into Kaffy's own chrome.
  @admin_nav [
    %{
      section: :settings,
      label: "Model settings",
      path: "/admin",
      icon: "hero-adjustments-horizontal"
    },
    %{
      section: :db,
      label: "Database",
      path: "/admin/db",
      icon: "hero-circle-stack",
      external: true
    }
  ]

  @doc """
  Left-hand navigation for the admin shell. Highlights the section matching
  `current_path`; renders as a static column on desktop and an off-canvas
  drawer (toggled by the header hamburger) on narrow screens.
  """
  attr :current_path, :string, default: nil
  attr :id, :string, default: "admin-sidebar"

  def admin_sidebar(assigns) do
    assigns =
      assign(assigns, :nav, @admin_nav)
      |> assign(:active, admin_section(assigns.current_path))

    ~H"""
    <div
      id={@id <> "-overlay"}
      class="fixed inset-0 z-30 hidden bg-ink/40 backdrop-blur-sm lg:hidden"
      phx-click={hide_admin_sidebar(@id)}
      aria-hidden="true"
    >
    </div>

    <aside
      id={@id}
      class="fixed inset-y-0 left-0 z-40 hidden w-64 -translate-x-full transform border-r border-border bg-surface transition-transform duration-200 ease-out-quart lg:sticky lg:top-14 lg:z-0 lg:block lg:h-[calc(100dvh-3.5rem)] lg:translate-x-0"
    >
      <div class="flex h-14 items-center justify-between border-b border-border px-4 lg:hidden">
        <span class="text-[0.6875rem] font-semibold uppercase tracking-[0.14em] text-muted">
          Navigation
        </span>
        <button
          type="button"
          class="inline-flex size-8 items-center justify-center rounded-md text-muted transition-colors hover:bg-bg hover:text-ink"
          phx-click={hide_admin_sidebar(@id)}
          aria-label="Close navigation"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <nav class="flex flex-col gap-0.5 p-3" aria-label="Admin sections">
        <.link
          :for={item <- @nav}
          {admin_nav_target(item)}
          class={[
            "group flex items-center gap-3 rounded-md px-3 py-2 text-[0.875rem] font-medium transition-colors duration-150 ease-out-quart",
            @active == item.section && "bg-ink text-bg",
            @active != item.section && "text-muted hover:bg-bg hover:text-ink"
          ]}
          aria-current={@active == item.section && "page"}
        >
          <.icon name={item.icon} class="size-4 shrink-0" />
          <span class="flex-1">{item.label}</span>
          <.icon
            :if={item[:external]}
            name="hero-arrow-top-right-on-square-micro"
            class={"size-3.5 shrink-0 #{if @active == item.section, do: "text-bg/70", else: "text-muted/60"}"}
          />
        </.link>
      </nav>
    </aside>
    """
  end

  @doc "JS command: reveal the off-canvas admin sidebar (mobile)."
  def show_admin_sidebar(id \\ "admin-sidebar") do
    JS.remove_class("hidden -translate-x-full", to: "##{id}")
    |> JS.remove_class("hidden", to: "##{id}-overlay")
  end

  @doc "JS command: hide the off-canvas admin sidebar (mobile)."
  def hide_admin_sidebar(id \\ "admin-sidebar") do
    JS.add_class("-translate-x-full", to: "##{id}")
    |> JS.add_class("hidden", to: "##{id}-overlay")
  end

  # Which sidebar section owns the current path. Everything under /admin/db is
  # Kaffy's territory; the rest of /admin is the custom console.
  defp admin_section("/admin/db" <> _), do: :db
  defp admin_section(_), do: :settings

  # Kaffy (external) pages render their own full chrome, so open them in a new
  # tab and keep the admin console tab put. In-app sections use live navigation.
  defp admin_nav_target(%{external: true, path: path}),
    do: [href: path, target: "_blank", rel: "noopener"]

  defp admin_nav_target(%{path: path}), do: [navigate: path]

  @doc """
  Umami analytics config, or `nil` when not configured.

  Returns `%{script_url: ..., website_id: ...}` only when both
  `UMAMI_SCRIPT_URL` and `UMAMI_WEBSITE_ID` are set (see `config/runtime.exs`).
  When `nil` the root layout omits the tracking tag entirely — so dev and the
  VPN-gated deployment stay untracked, and analytics only loads once the public
  build is configured.
  """
  def umami do
    cfg = Application.get_env(:o_que_mudou, :umami, [])

    case {cfg[:script_url], cfg[:website_id]} do
      {url, id} when is_binary(url) and is_binary(id) ->
        %{script_url: url, website_id: id}

      _ ->
        nil
    end
  end
end
