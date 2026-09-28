# Simulated facility directory and demo clinicians. Names are fictional; the
# coordinates are realistic Nairobi locations so the map and distances make sense.
# Safe to re-run: facilities and clinicians are updated by name, so existing
# referrals keep pointing at the same rows.
#
#     mix run priv/repo/seeds.exs

alias CareRoute.Repo
alias CareRoute.Facilities
alias CareRoute.Facilities.{Clinician, Facility}

upsert = fn schema, attrs ->
  (Repo.get_by(schema, name: attrs.name) || struct(schema))
  |> schema.changeset(attrs)
  |> Repo.insert_or_update!()
end

# The demo partner facilities: fictional names at realistic Nairobi locations.
# They stand in for pilot clinics that use CareRoute's clinician dashboard, so
# only they receive referrals. Real facilities come from
# `mix care_route.import_facilities` (OpenStreetMap) and are directory-only.
partner = %{source: "seed", partner: true}

facilities =
  for attrs <- [
        %{
          name: "Kilimani Community Clinic",
          type: :clinic,
          address: "Argwings Kodhek Rd, Kilimani",
          latitude: -1.2893,
          longitude: 36.7839,
          services: ["general", "pediatrics", "lab"]
        },
        %{
          name: "Westlands Family Health Centre",
          type: :clinic,
          address: "Woodvale Grove, Westlands",
          latitude: -1.2673,
          longitude: 36.8069,
          services: ["general", "maternal health"]
        },
        %{
          name: "City General Hospital",
          type: :hospital,
          address: "Hospital Rd, Upper Hill",
          latitude: -1.3007,
          longitude: 36.8065,
          emergency: true,
          services: ["emergency", "pediatrics", "imaging", "inpatient"]
        },
        %{
          name: "Parklands District Hospital",
          type: :hospital,
          address: "3rd Parklands Ave, Parklands",
          latitude: -1.2612,
          longitude: 36.8189,
          emergency: true,
          services: ["emergency", "inpatient", "lab"]
        },
        %{
          name: "Children's Specialist Centre",
          type: :specialist,
          address: "James Gichuru Rd, Lavington",
          latitude: -1.2779,
          longitude: 36.7695,
          services: ["pediatrics", "respiratory"]
        }
      ] do
    upsert.(Facility, Map.merge(attrs, partner))
  end

by_name = Map.new(facilities, &{&1.name, &1})

for {name, role, facility} <- [
      {"Dr. Amina Otieno", "Clinical Officer", "Kilimani Community Clinic"},
      {"Nurse Peter Kamau", "Triage Nurse", "City General Hospital"}
    ] do
  upsert.(Clinician, %{name: name, role: role, facility_id: by_name[facility].id})
end
