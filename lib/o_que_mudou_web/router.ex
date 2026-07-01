defmodule OQueMudouWeb.Router do
  use OQueMudouWeb, :router

  import OQueMudouWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OQueMudouWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Edge-gated by Traefik (authelia + VPN ACL); this plug re-checks the
  # Remote-Groups header as defense in depth. See issue #19.
  pipeline :admin do
    plug OQueMudouWeb.Plugs.RequireAdminGroup
  end

  scope "/", OQueMudouWeb do
    pipe_through :browser

    # Public pages mount the current user (nil when logged out) so the masthead
    # can show account/login links. Auth is optional here — gating (issue #27)
    # happens per-route with :require_authenticated_user, not on these.
    live_session :public,
      on_mount: [{OQueMudouWeb.UserAuth, :mount_current_user}] do
      live "/", RegisterLive, :index
      live "/pesquisar", SearchLive, :index
      live "/faq", FaqLive, :index
      live "/sobre", AboutLive, :index
      live "/acts/:id", ActLive, :show
    end
  end

  scope "/admin", OQueMudouWeb do
    pipe_through [:browser, :admin]

    live "/", AdminLive, :index
    live "/summarizer", AdminLive, :index
    live "/providers/new", ProviderFormLive, :new
    live "/providers/:id/edit", ProviderFormLive, :edit
    live "/acts/:id", AdminActLive, :show
  end

  # Raw-DB admin (Kaffy): auto-generated CRUD over every Ecto schema, mounted at
  # /admin/db behind the same edge gate (Authelia + VPN) and in-app :admin check.
  use Kaffy.Routes, scope: "/admin/db", pipe_through: [:browser, :admin]

  # Other scopes may use custom stacks.
  # scope "/api", OQueMudouWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:o_que_mudou, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: OQueMudouWeb.Telemetry
      # Public-user emails (verification/reset) land here in dev — nothing is sent.
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", OQueMudouWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{OQueMudouWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", OQueMudouWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{OQueMudouWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", OQueMudouWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{OQueMudouWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
end
