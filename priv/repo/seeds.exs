# Simulated facility directory and demo clinicians.
#
#     mix run priv/repo/seeds.exs

alias CareRoute.Repo
alias CareRoute.Facilities
alias CareRoute.Facilities.{Clinician, Facility}

Repo.delete_all(Clinician)
Repo.delete_all(Facility)

facilities =
  for attrs <- [
        %{
          name: "Kilimani Community Clinic",
          type: :clinic,
          distance_km: 1.2,
          services: ["general", "pediatrics", "lab"]
        },
        %{
          name: "Westlands Family Health Centre",
          type: :clinic,
          distance_km: 2.8,
          services: ["general", "maternal health"]
        },
        %{
          name: "City General Hospital",
          type: :hospital,
          distance_km: 4.5,
          services: ["emergency", "pediatrics", "imaging", "inpatient"]
        },
        %{
          name: "Children's Specialist Centre",
          type: :specialist,
          distance_km: 6.1,
          services: ["pediatrics", "respiratory"]
        }
      ] do
    {:ok, facility} = Facilities.create_facility(attrs)
    facility
  end

by_name = Map.new(facilities, &{&1.name, &1})

for {name, role, facility} <- [
      {"Dr. Amina Otieno", "Clinical Officer", "Kilimani Community Clinic"},
      {"Nurse Peter Kamau", "Triage Nurse", "City General Hospital"}
    ] do
  {:ok, _} =
    Facilities.create_clinician(%{name: name, role: role, facility_id: by_name[facility].id})
end
