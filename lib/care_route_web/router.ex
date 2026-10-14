defmodule CareRouteWeb.Router do
  use CareRouteWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CareRouteWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Clinician and admin pages. Basic auth when credentials are configured
  # (always in production; see config/runtime.exs).
  pipeline :staff do
    plug :staff_auth
  end

  scope "/", CareRouteWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/privacy", PageController, :privacy

    live_session :patient, session: {CareRouteWeb.ClientIP, :session, []} do
      live "/start", PatientLive.Start
      live "/intake/:token", PatientLive.Intake
      live "/intake/:token/results", PatientLive.Results
    end
  end

  # A separate live_session means arriving here from a patient page is a full
  # page load, so the auth plug always runs.
  scope "/", CareRouteWeb do
    pipe_through [:browser, :staff]

    live_session :staff do
      live "/clinician", ClinicianLive.Dashboard, :index
      live "/clinician/referrals/:id", ClinicianLive.Dashboard, :show

      live "/admin", AdminLive.Dashboard
    end
  end

  # Basic auth, refusing an IP for a while after too many wrong passwords.
  defp staff_auth(conn, _opts) do
    case Application.get_env(:care_route, :staff_auth) do
      nil -> conn
      credentials -> check_staff_credentials(conn, credentials)
    end
  end

  defp check_staff_credentials(conn, credentials) do
    ip = CareRouteWeb.ClientIP.get(conn)

    if CareRoute.RateLimit.limited?(:staff_login_failures, ip) do
      conn
      |> put_resp_header("retry-after", "900")
      |> send_resp(429, "Too many failed logins. Try again in 15 minutes.")
      |> halt()
    else
      with {user, pass} <- Plug.BasicAuth.parse_basic_auth(conn),
           true <- Plug.Crypto.secure_compare(user, credentials[:username]),
           true <- Plug.Crypto.secure_compare(pass, credentials[:password]) do
        conn
      else
        result ->
          # A missing header is the browser asking for the login prompt, not a guess.
          if result != :error, do: CareRoute.RateLimit.hit(:staff_login_failures, ip)
          conn |> Plug.BasicAuth.request_basic_auth() |> halt()
      end
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", CareRouteWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:care_route, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CareRouteWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
