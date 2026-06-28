defmodule OQueMudouWeb.Router do
  use OQueMudouWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OQueMudouWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
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

    live "/", RegisterLive, :index
    live "/acts/:id", ActLive, :show
  end

  scope "/admin", OQueMudouWeb do
    pipe_through [:browser, :admin]

    live "/summarizer", AdminLive, :index
  end

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
    end
  end
end
