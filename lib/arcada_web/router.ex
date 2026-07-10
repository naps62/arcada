defmodule ArcadaWeb.Router do
  use ArcadaWeb, :router

  import ArcadaWeb.UserAuth
  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ArcadaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    # Mint an opaque visitor id so anonymous search can be rate-limited (#32).
    plug ArcadaWeb.Plugs.VisitorId
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Admin (/admin) is served ONLY on the private VPN host (ADMIN_HOST, e.g.
  # arcada.example.internal): RequireAdminHost 404s it on the public host so the surface
  # doesn't exist there at all. The access boundary is the VPN itself — reaching
  # the admin host means you're already on the network, so no extra in-app auth
  # (issues #19, #37).
  pipeline :admin do
    plug ArcadaWeb.Plugs.RequireAdminHost
  end

  scope "/", ArcadaWeb do
    pipe_through :browser

    # Dynamic robots.txt + sitemap.xml (track the SEO indexing gate; see #36).
    get "/robots.txt", SeoController, :robots
    get "/sitemap.xml", SeoController, :sitemap

    # Bare `/acts/:dre_id` (no slug) 301s to the canonical `/acts/:dre_id/:slug`
    # via a real HTTP redirect (not a LiveView client nav) so crawlers see one
    # canonical URL per act. Lives outside the live_session — it's a plain GET.
    get "/acts/:dre_id", ActRedirectController, :show

    # Public pages mount the current user (nil when logged out) so the masthead
    # can show account/login links. Auth is optional here — gating (issue #27)
    # happens per-route with :require_authenticated_user, not on these.
    live_session :public,
      on_mount: [{ArcadaWeb.UserAuth, :mount_current_user}] do
      live "/", RegisterLive, :index
      live "/faq", FaqLive, :index
      live "/sobre", AboutLive, :index
      live "/acts/:dre_id/:slug", ActLive, :show
    end
  end

  scope "/admin", ArcadaWeb do
    pipe_through [:browser, :admin]

    live "/", AdminLive, :index
    live "/summarizer", AdminLive, :index
    live "/providers/new", ProviderFormLive, :new
    live "/providers/:id/edit", ProviderFormLive, :edit
    live "/acts", AdminActsLive, :index
    live "/acts/:id", AdminActLive, :show
  end

  # Oban Web: background-job dashboard (queues, states, retries, history) for the
  # scrape/summarize workers. Mounted at /admin/jobs behind the same edge gate
  # (Authelia + VPN) and in-app :admin check. `oban_dashboard` sets up its own
  # live_session, so it lives in a dedicated scope rather than the admin scope above.
  scope "/admin" do
    pipe_through [:browser, :admin]

    oban_dashboard("/jobs")
  end

  # Raw-DB admin (Kaffy): auto-generated CRUD over every Ecto schema, mounted at
  # /admin/db behind the same edge gate (Authelia + VPN) and in-app :admin check.
  use Kaffy.Routes, scope: "/admin/db", pipe_through: [:browser, :admin]

  # Other scopes may use custom stacks.
  # scope "/api", ArcadaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:arcada, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ArcadaWeb.Telemetry
      # Public-user emails (verification/reset) land here in dev — nothing is sent.
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ArcadaWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{ArcadaWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", ArcadaWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ArcadaWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", ArcadaWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{ArcadaWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
end
