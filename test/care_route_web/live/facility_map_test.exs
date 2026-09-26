defmodule CareRouteWeb.FacilityMapTest do
  use CareRouteWeb.ConnCase, async: true
  use Oban.Testing, repo: CareRoute.Repo

  import Phoenix.LiveViewTest

  alias CareRoute.{Facilities, Intake, Referrals}
  alias CareRoute.Workers.IntakeWorker

  # Two hospitals on opposite sides of Nairobi.
  setup do
    {:ok, west} =
      Facilities.create_facility(%{
        name: "West Hospital",
        type: :hospital,
        latitude: -1.2779,
        longitude: 36.7695,
        address: "Lavington"
      })

    {:ok, east} =
      Facilities.create_facility(%{
        name: "East Hospital",
        type: :hospital,
        latitude: -1.2612,
        longitude: 36.8889
      })

    {:ok, patient} = Intake.create_patient(%{age: 40})
    {:ok, conversation} = Intake.start_conversation(patient)
    {:ok, view, _} = live(build_conn(), ~p"/intake/#{conversation.id}")

    view
    |> form("#message-form", %{message: "chest pain and trouble breathing"})
    |> render_submit()

    assert :ok = perform_job(IntakeWorker, %{conversation_id: conversation.id})

    {:ok, results, _} = live(build_conn(), ~p"/intake/#{conversation.id}/results")
    %{view: results, west: west, east: east}
  end

  test "renders the map with facility coordinates and the demo origin", %{view: view, west: west} do
    assert has_element?(view, "#facility-map[phx-hook=FacilityMap]")

    data = view |> element("#facility-map") |> render()
    assert data =~ "West Hospital"
    assert data =~ "-1.2779"
    assert data =~ "&quot;source&quot;:&quot;demo&quot;"
    assert has_element?(view, "#facility-#{west.id}", "Lavington")
    assert has_element?(view, ~s(#facility-#{west.id} a[href*="destination=-1.2779,36.7695"]))
  end

  test "a shared location re-sorts facilities by real distance", %{
    view: view,
    west: west,
    east: east
  } do
    # Standing next to East Hospital.
    render_hook(view, "located", %{"lat" => -1.2615, "lng" => 36.8880})

    assert_push_event(view, "facility-map:update", %{facilities: [first, second], origin: origin})
    assert first.id == east.id
    assert second.id == west.id
    assert first.distance_km < 1
    assert origin.source == "device"

    html = render(view)
    {east_pos, _} = :binary.match(html, "facility-#{east.id}")
    {west_pos, _} = :binary.match(html, "facility-#{west.id}")
    assert east_pos < west_pos
  end

  test "a location far outside the network keeps the demo origin", %{view: view} do
    render_hook(view, "located", %{"lat" => 51.5, "lng" => -0.12})

    assert render(view) =~ "outside the demo area"
    refute_push_event(view, "facility-map:update", %{})
  end

  test "choosing from the map refers and focuses the facility", %{view: view, east: east} do
    render_hook(view, "refer", %{"facility-id" => to_string(east.id)})

    assert_push_event(view, "facility-map:select", %{id: id})
    assert id == east.id
    assert has_element?(view, "#referral-sent", "Referral sent to East Hospital")

    # A second pick (e.g. double tap) doesn't create another referral.
    render_hook(view, "refer", %{"facility-id" => to_string(east.id)})
    assert [_] = Referrals.list_referrals()
  end

  test "facilities that weren't offered can't be chosen", %{view: view} do
    {:ok, clinic} = Facilities.create_facility(%{name: "Some Clinic", type: :clinic})

    render_hook(view, "refer", %{"facility-id" => to_string(clinic.id)})
    assert Referrals.list_referrals() == []
  end
end
