defmodule CareRouteWeb.RateLimitTest do
  # Changes the global rate-limit config, so not async.
  use CareRouteWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias CareRoute.{Intake, RateLimit}

  setup do
    previous = Application.get_env(:care_route, :rate_limits)
    on_exit(fn -> Application.put_env(:care_route, :rate_limits, previous) end)
    :ok
  end

  defp limit(name, max, window \\ 600) do
    Application.put_env(:care_route, :rate_limits, [{name, {max, window}}])
  end

  defp from_ip(conn, ip), do: %{conn | remote_ip: ip}

  test "counts hits per key within a window" do
    limit(:test_action, 2)
    key = make_ref()

    assert :ok = RateLimit.hit(:test_action, key)
    assert :ok = RateLimit.hit(:test_action, key)
    assert RateLimit.limited?(:test_action, key)
    assert {:error, :rate_limited} = RateLimit.hit(:test_action, key)
    # Other keys and unconfigured names are unaffected.
    assert :ok = RateLimit.hit(:test_action, make_ref())
    assert :ok = RateLimit.hit(:unconfigured, key)
  end

  test "one visitor can only start so many conversations", %{conn: conn} do
    limit(:start_conversation, 1)
    conn = from_ip(conn, {10, 1, 1, 1})
    params = %{age: "30", consent: "true"}

    {:ok, view, _} = live(conn, ~p"/start")

    assert {:error, {:live_redirect, _}} =
             view |> form("#start-form", patient: params) |> render_submit()

    {:ok, view, _} = live(conn, ~p"/start")
    html = view |> form("#start-form", patient: params) |> render_submit()
    assert html =~ "Too many requests"

    # A different visitor can still start.
    {:ok, view, _} = live(from_ip(conn, {10, 1, 1, 2}), ~p"/start")

    assert {:error, {:live_redirect, _}} =
             view |> form("#start-form", patient: params) |> render_submit()
  end

  test "the client IP comes from the proxy header only when configured", %{conn: conn} do
    conn = conn |> from_ip({10, 0, 0, 9}) |> put_req_header("fly-client-ip", "41.90.1.2")
    assert CareRouteWeb.ClientIP.get(conn) == "10.0.0.9"

    Application.put_env(:care_route, :client_ip_header, "fly-client-ip")
    on_exit(fn -> Application.delete_env(:care_route, :client_ip_header) end)
    assert CareRouteWeb.ClientIP.get(conn) == "41.90.1.2"
  end

  test "town searches are limited per conversation", %{conn: conn} do
    limit(:town_search, 1)
    Req.Test.stub(CareRoute.Directory, &Req.Test.json(&1, []))

    {:ok, patient} = Intake.create_patient(%{age: 30})
    {:ok, c} = Intake.start_conversation(patient)

    {:ok, _} =
      CareRoute.Routing.create_recommendation(c, %{
        urgency_level: :clinic,
        reasoning: [],
        warning_signs: []
      })

    {:ok, view, _} = live(conn, ~p"/intake/#{c.token}/results")

    assert view
           |> form("#town-form", %{town: "Nowhere #{System.unique_integer()}"})
           |> render_submit() =~ "couldn"

    assert view
           |> form("#town-form", %{town: "Again #{System.unique_integer()}"})
           |> render_submit() =~ "Too many requests"
  end

  test "staff logins are refused for a while after too many wrong passwords" do
    limit(:staff_login_failures, 2)
    ip = {10, 2, 2, 2}

    wrong =
      build_conn()
      |> from_ip(ip)
      |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("staff", "guess"))

    assert get(wrong, ~p"/clinician").status == 401
    assert get(wrong, ~p"/clinician").status == 401

    # Now even the right password is refused from that IP…
    right = build_conn() |> from_ip(ip) |> staff_conn()
    conn = get(right, ~p"/clinician")
    assert conn.status == 429
    assert get_resp_header(conn, "retry-after") == ["900"]

    # …but not from elsewhere, and a request without credentials isn't a failure.
    assert get(build_conn() |> from_ip({10, 2, 2, 3}) |> staff_conn(), ~p"/clinician").status ==
             200

    assert get(build_conn() |> from_ip({10, 2, 2, 4}), ~p"/clinician").status == 401
    refute RateLimit.limited?(:staff_login_failures, "10.2.2.4")
  end
end
