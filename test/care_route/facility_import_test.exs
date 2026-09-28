defmodule CareRoute.FacilityImportTest do
  use CareRoute.DataCase, async: true

  alias CareRoute.{Facilities, Intake, Referrals, Repo}
  alias CareRoute.Facilities.{Facility, Import}

  @fixture "test/support/fixtures/overpass_kenya.json"

  defp parsed, do: @fixture |> File.read!() |> Jason.decode!() |> Import.parse_osm()
  defp by_name(rows, name), do: Enum.find(rows, &(&1.name == name))

  test "maps OpenStreetMap tags onto facilities" do
    coast = by_name(parsed(), "Coast General Hospital")

    assert coast.source_id == "node/101"
    assert coast.type == :hospital
    assert coast.emergency
    assert coast.phone == "+254 41 231 4201"
    assert coast.address == "Moi Ave, Mombasa"
    assert coast.opening_hours == "24/7"
    assert coast.services == ["paediatrics", "emergency medicine"]
  end

  test "small facilities tagged as hospitals are treated as clinics" do
    rows = parsed()
    assert by_name(rows, "Naikarra Dispensary").type == :clinic
    assert by_name(rows, "The Mater Hospital - Satellite Clinic").type == :clinic
    # Named a hospital but tagged a clinic: the name wins; lowercase names are tidied.
    kiriani = by_name(rows, "Kiriani Mission Hospital")
    assert kiriani.type == :hospital
    assert kiriani.county == "Murang'a"
  end

  test "keeps same-name branches that are far apart, merging only close ones" do
    rows =
      Import.parse_osm(%{
        "elements" => [
          %{
            "type" => "node",
            "id" => 1,
            "lat" => -1.2964,
            "lon" => 36.8037,
            "tags" => %{"amenity" => "hospital", "name" => "Nairobi Hospital"}
          },
          %{
            "type" => "way",
            "id" => 2,
            "center" => %{"lat" => -1.2966, "lon" => 36.8040},
            "tags" => %{
              "amenity" => "hospital",
              "name" => "nairobi hospital",
              "phone" => "+254 20 284 5000"
            }
          },
          %{
            "type" => "node",
            "id" => 3,
            "lat" => -1.2351,
            "lon" => 36.8106,
            "tags" => %{"amenity" => "hospital", "name" => "Nairobi Hospital"}
          }
        ]
      })

    assert length(rows) == 2
    # The merged pair keeps the entry with more details (the phone number).
    assert Enum.any?(rows, &(&1.phone == "+254 20 284 5000"))
  end

  test "merges duplicates and skips unnamed or unlocated places" do
    names = Enum.map(parsed(), & &1.name)
    assert Enum.count(names, &(&1 == "Coast General Hospital")) == 1
    refute "No Coordinates Hospital" in names
    assert length(names) == 4
  end

  test "imports, refreshes, and removes facilities that left the source" do
    assert {:ok, %{imported: 4, removed: 0}} = Import.run(:osm, file: @fixture)
    assert Repo.aggregate(Facility, :count) == 4
    refute Enum.any?(Repo.all(Facility), & &1.partner)

    # Re-importing updates in place.
    assert {:ok, %{imported: 4, removed: 0}} = Import.run(:osm, file: @fixture)
    assert Repo.aggregate(Facility, :count) == 4

    # A facility that disappeared is removed, unless a referral points at it.
    kept = Repo.get_by!(Facility, source_id: "node/103")
    {:ok, patient} = Intake.create_patient(%{})
    {:ok, _} = Referrals.create_referral(%{patient_id: patient.id, to_facility_id: kept.id})

    smaller = Path.join(System.tmp_dir!(), "overpass-#{System.unique_integer([:positive])}.json")
    File.write!(smaller, Jason.encode!(%{"elements" => []}))

    assert {:ok, %{imported: 0, removed: 3}} = Import.run(:osm, file: smaller)
    assert [%{source_id: "node/103"}] = Repo.all(Facility)
  end

  test "imported facilities are found by the nearest search" do
    {:ok, _} = Import.run(:osm, file: @fixture)

    assert {:ok, [%{name: "Coast General Hospital"} | _]} =
             Facilities.nearest(%{lat: -1.30, lng: 36.80}, [:hospital])
  end

  test "parses a CSV export" do
    path = Path.join(System.tmp_dir!(), "facilities-#{System.unique_integer([:positive])}.csv")

    File.write!(path, """
    source_id,name,type,latitude,longitude,county,phone,level,emergency,services
    13023,Kenyatta National Hospital,hospital,-1.3010,36.8070,Nairobi,+254 20 272 6300,Level 6,yes,emergency;surgery
    13024,Mbagathi Dispensary,clinic,-1.3100,36.7900,Nairobi,,Level 2,no,
    ,Missing Id,clinic,-1.0,36.0,,,,,
    """)

    assert [knh, disp] = Import.parse_csv(path)
    assert knh.name == "Kenyatta National Hospital"
    assert knh.type == :hospital and knh.emergency and knh.level == "Level 6"
    assert knh.services == ["emergency", "surgery"]
    assert disp.type == :clinic and disp.phone == nil

    assert {:ok, %{imported: 2}} = Import.run_csv(path)
    assert Repo.get_by!(Facility, source: "csv", source_id: "13023").county == "Nairobi"
  end

  test "falls back to the next Overpass server when one is busy" do
    Req.Test.stub(CareRoute.Directory, fn conn ->
      if conn.host == "overpass-api.de",
        do: Plug.Conn.send_resp(conn, 200, "<p>Error: runtime error: server too busy</p>"),
        else: Req.Test.json(conn, %{"elements" => []})
    end)

    assert %{"elements" => []} = Import.fetch_osm!()
  end

  test "reports both servers' errors when all are busy" do
    Req.Test.stub(CareRoute.Directory, &Plug.Conn.send_resp(&1, 504, "Gateway Timeout"))

    error = assert_raise RuntimeError, fn -> Import.fetch_osm!() end
    assert error.message =~ "overpass-api.de/api/interpreter: status 504"
    assert error.message =~ "overpass.kumi.systems/api/interpreter: status 504"
  end
end
