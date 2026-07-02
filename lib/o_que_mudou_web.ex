defmodule OQueMudouWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use OQueMudouWeb, :controller
      use OQueMudouWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  # robots.txt + sitemap.xml are served dynamically by SeoController, not from
  # priv/static, so they can reflect the SEO indexing gate (see #36).
  def static_paths, do: ~w(assets fonts images favicon.ico favicon.svg)

  def router do
    quote do
      # helpers: true — Kaffy (raw-DB admin at /admin/db) still relies on the
      # legacy Phoenix.Router.Helpers path helpers. App code uses verified ~p
      # routes; this just keeps the helper module generated for Kaffy.
      use Phoenix.Router, helpers: true

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: OQueMudouWeb.Layouts]

      use Gettext, backend: OQueMudouWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {OQueMudouWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  @doc """
  LiveViews for the back-of-house admin console. Same design tokens as the
  public broadsheet, but its own tool chrome (`:admin` layout) instead of the
  public masthead. Served only on the VPN host; see `Plugs.RequireAdminHost`.
  """
  def live_view_admin do
    quote do
      use Phoenix.LiveView,
        layout: {OQueMudouWeb.Layouts, :admin}

      on_mount OQueMudouWeb.AdminNav

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # Translation
      use Gettext, backend: OQueMudouWeb.Gettext

      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import OQueMudouWeb.CoreComponents

      # SEO helpers (canonical URLs, robots gate) used by the root layout
      alias OQueMudouWeb.SEO

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: OQueMudouWeb.Endpoint,
        router: OQueMudouWeb.Router,
        statics: OQueMudouWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
