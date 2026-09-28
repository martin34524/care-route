defmodule CareRouteWeb.FacilityMapTest do
  use CareRouteWeb.ConnCase, async: true
  use Oban.Testing, repo: CareRoute.Repo

  import Phoenix.LiveViewTest

  alias CareRoute.{Facilities, Intake, Referrals}
  alias CareRoute.Workers.IntakeWorker

  # A partner hospital (uses CareRoute) and a real directory hospital, both
  # near the Nairobi fallback origin; plus a Kisumu hospital for searches.
  setup do
    {:ok, partner} =
      Facilities.create_facility(%{
        name: "Partner Hospital",
        type: :hospital,
        partner: true,
        emergency: true,
        latitude: -1.2779,
        longitude: 36.7695,
        address: "Lavington"
      })

    {:ok, directory} =
      Facilities.create_facility(%{
        name: "Directory Hospital",
        type: :hospital,
        source: "osm",
        source_id: "node/1",
        phone: "+254 20 123 4567",
        latitude: -1.2612,
        longitude: 36.8889
      })

    {:ok, kisumu} =
      Facilities.create_facility(%{
        name: "Kisumu Hospital",
        type: :hospital,
        source: "osm",
        source_id: "node/2",
        latitude: -0.1000,
        longitude: 34.7600
      })

    {:ok, patient} = Intake.create_patient(%{age: 40})
    {:ok, conversation} = Intake.start_conversation(patient)
    {:ok, chat, _} = live(build_conn(), ~p"/intake/#{conversation.token}")

    chat
    |> form("#message-form", %{message: "chest pain and trouble breathing"})
    |> render_submit()

    assert :ok = perform_job(IntakeWorker, %{conversation_id: conversation.id})

    {:ok, results, _} = live(build_conn(), ~p"/intake/#{conversation.token}/results")
    %{view: results, partner: partner, directory: directory, kisumu: kisumu}
  end

  test "shows the nearest facilities around Nairobi until a location is known", %{
    view: view,
    partner: partner,
    directory: directory,
    kisumu: kisumu
  } do
    assert has_element?(view, "#origin-label", "Near central Nairobi")
    assert has_element?(view, "#facility-map[phx-hook=FacilityMap]")
    assert has_element?(view, "#facility-#{partner.id}", "CareRoute partner")
    assert has_element?(view, "#facility-#{partner.id}", "Emergency department")
    assert has_element?(view, ~s(#facility-#{partner.id} a[href*="destination=-1.2779,36.7695"]))

    # Kisumu is ~270 km away; the search stops widening once 3 are found... but
    # only 2 are near Nairobi, so it widens and finds Kisumu too, furthest last.
    html = view |> element("#facility-map") |> render()
    assert html =~ "Partner Hospital"
    assert has_element?(view, "#facility-#{directory.id}")
    assert has_element?(view, "#facility-#{kisumu.id}")
    assert render(view) =~ "Facility data © OpenStreetMap contributors"
  end

  test "nearby partners are shown even when many other places are closer", %{partner: partner} do
    # Twelve directory hospitals right next to the Nairobi origin, all nearer than the partner.
    for i <- 1..12 do
      {:ok, _} =
        Facilities.create_facility(%{
          name: "Close Hospital #{i}",
          type: :hospital,
          source: "osm",
          source_id: "node/close-#{i}",
          latitude: -1.2925 + i * 0.0001,
          longitude: 36.7870
        })
    end

    origin = Facilities.demo_origin()
    assert {:ok, only_nearest} = Facilities.nearest(origin, [:hospital])
    refute Enum.any?(only_nearest, & &1.partner)

    assert {:ok, with_partners} = Facilities.nearest(origin, [:hospital], partners_within_km: 50)
    assert length(with_partners) == 11
    assert Enum.any?(with_partners, &(&1.id == partner.id))
    assert with_partners == Enum.sort_by(with_partners, & &1.distance_km)
  end

  test "directory facilities offer a call and directions, but no referral", %{
    view: view,
    directory: directory
  } do
    assert has_element?(view, ~s(#facility-#{directory.id} a[href="tel:+254201234567"]), "Call")
    assert has_element?(view, "#facility-#{directory.id}", "Not connected to CareRoute yet")
    refute has_element?(view, "#facility-#{directory.id} button", "Request referral")

    # A crafted event can't refer to it either.
    render_hook(view, "refer", %{"facility-id" => to_string(directory.id)})
    assert Referrals.list_referrals() == []
  end

  test "partners receive referrals, and 'Send referral' picks the nearest partner", %{
    view: view,
    partner: partner
  } do
    view |> element("#send-referral") |> render_click()

    assert_push_event(view, "facility-map:select", %{id: id})
    assert id == partner.id
    assert has_element?(view, "#referral-sent", "Referral sent to Partner Hospital")

    # A second tap doesn't create another referral.
    render_hook(view, "refer", %{"facility-id" => to_string(partner.id)})
    assert [_] = Referrals.list_referrals()
  end

  test "a shared location in Kenya re-searches around it", %{view: view, kisumu: kisumu} do
    render_hook(view, "located", %{"lat" => -0.0917, "lng" => 34.7680})

    assert_push_event(view, "facility-map:update", %{facilities: [first | _], origin: origin})
    assert first.id == kisumu.id
    assert first.distance_km < 2
    assert origin.source == "device"
    assert has_element?(view, "#origin-label", "Near your location")
    # No partner near Kisumu, so no one-tap referral.
    refute has_element?(view, "#send-referral")
  end

  test "a location outside Kenya keeps the Nairobi results", %{view: view} do
    render_hook(view, "located", %{"lat" => 51.5, "lng" => -0.12})

    assert render(view) =~ "outside Kenya"
    refute_push_event(view, "facility-map:update", %{})
    assert has_element?(view, "#origin-label", "Near central Nairobi")
  end

  test "searching a town moves the results there", %{view: view, kisumu: kisumu} do
    Req.Test.stub(CareRoute.Directory, fn conn ->
      assert conn.query_params["countrycodes"] == "ke"

      Req.Test.json(conn, [
        %{
          "lat" => "-0.1029",
          "lon" => "34.7541",
          "display_name" => "Kisumu, Kisumu County, Kenya"
        }
      ])
    end)

    view
    |> form("#town-form", %{town: "Kisumu town #{System.unique_integer()}"})
    |> render_submit()

    assert has_element?(view, "#origin-label", "Near Kisumu")
    assert_push_event(view, "facility-map:update", %{facilities: [first | _]})
    assert first.id == kisumu.id
  end

  test "an unknown town or a failed search explains itself", %{view: view} do
    Req.Test.stub(CareRoute.Directory, &Req.Test.json(&1, []))
    view |> form("#town-form", %{town: "Nowhere #{System.unique_integer()}"}) |> render_submit()
    assert render(view) =~ "couldn&#39;t find that place in Kenya"

    Req.Test.stub(CareRoute.Directory, &Plug.Conn.send_resp(&1, 503, "busy"))
    view |> form("#town-form", %{town: "Elsewhere #{System.unique_integer()}"}) |> render_submit()
    assert render(view) =~ "Place search isn&#39;t working right now"
  end
end
