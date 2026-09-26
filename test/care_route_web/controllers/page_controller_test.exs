defmodule CareRouteWeb.PageControllerTest do
  use CareRouteWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "landing page renders and links into the app", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Find the right care, right away."
    assert html =~ "Three minutes to the right door"
    assert html =~ "not a diagnostic tool"
    assert html =~ ~s(href="/start")
    assert html =~ ~s(href="/clinician")
  end

  test "clinician and admin pages require the staff login" do
    for path <- ["/clinician", "/clinician/referrals/1", "/admin"] do
      conn = get(build_conn(), path)
      assert conn.status == 401, path

      wrong = Plug.BasicAuth.encode_basic_auth("staff", "wrong")
      conn = build_conn() |> put_req_header("authorization", wrong) |> get(path)
      assert conn.status == 401, path
    end

    # Patient pages stay public.
    assert build_conn() |> get(~p"/") |> html_response(200)
    assert build_conn() |> get(~p"/start") |> html_response(200)
  end

  test "Start now opens the intake start screen", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/start")
    assert html =~ "Before we start"
  end

  test "the privacy page explains data use and terms", %{conn: conn} do
    html = conn |> get(~p"/privacy") |> html_response(200)
    assert html =~ "How CareRoute uses your information"
    assert html =~ ~s(id="terms")
    assert html =~ "999 or 112"
  end

  test "the landing footer links to the privacy page", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(href="/privacy")
    assert html =~ ~s(href="/privacy#terms")
  end
end
