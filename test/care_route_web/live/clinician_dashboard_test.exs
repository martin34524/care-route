defmodule CareRouteWeb.ClinicianDashboardTest do
  # Not async: the dashboard listens on the global "referrals" PubSub topic, so
  # referrals created by concurrently running tests would reach it.
  use CareRouteWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias CareRoute.{Facilities, Intake, Referrals, Routing}

  setup do
    {:ok, clinic} = Facilities.create_facility(%{name: "Test Clinic", type: :clinic})
    {:ok, hospital} = Facilities.create_facility(%{name: "Test Hospital", type: :hospital})

    {:ok, nurse} =
      Facilities.create_clinician(%{
        name: "Nurse Jane Doe",
        role: "Triage Nurse",
        facility_id: hospital.id
      })

    %{clinic: clinic, hospital: hospital, nurse: nurse}
  end

  # A finished intake with a stored symptom report and recommendation.
  defp referral(name, facility, level, symptoms) do
    {:ok, patient} = Intake.create_patient(%{name: name, age: 30})
    {:ok, conversation} = Intake.start_conversation(patient)

    {:ok, conversation} =
      Intake.append_message(conversation, "patient", Enum.join(symptoms, ", "))

    {:ok, _} =
      Intake.upsert_symptom_report(conversation, %{symptoms: symptoms, duration: "2 days"})

    {:ok, _} =
      Routing.create_recommendation(conversation, %{
        urgency_level: level,
        reasoning: ["Reason for #{name}."]
      })

    {:ok, referral} =
      Referrals.create_referral(%{
        patient_id: patient.id,
        conversation_id: conversation.id,
        to_facility_id: facility.id
      })

    referral
  end

  test "queue is sorted by urgency and the detail panel shows intake and rationale", %{
    conn: conn,
    clinic: clinic,
    hospital: hospital
  } do
    routine = referral("Rita", clinic, :clinic, ["sore throat"])
    urgent = referral("Umar", hospital, :urgent, ["chest pain"])

    {:ok, view, _} = live(conn, ~p"/clinician")
    html = view |> element("#referrals") |> render()
    assert :binary.match(html, "Umar") < :binary.match(html, "Rita")
    assert has_element?(view, "#referral-#{urgent.id}", "Urgent")
    assert has_element?(view, "#referral-#{routine.id}", "Sore throat, 2 days")

    view |> element("#referral-#{urgent.id}") |> render_click()
    assert_patch(view, ~p"/clinician/referrals/#{urgent.id}")

    assert has_element?(view, "#referral-detail", "Patient’s description")
    assert has_element?(view, "#referral-detail", "chest pain")
    assert has_element?(view, "#referral-detail", "Reason for Umar. Suggested level: Urgent.")
  end

  test "accept then complete, recording a response time", %{conn: conn, clinic: clinic} do
    r = referral("Rita", clinic, :clinic, ["sore throat"])
    {:ok, view, _} = live(conn, ~p"/clinician/referrals/#{r.id}")
    assert has_element?(view, "#stat-response", "—")

    view |> element("#accept-referral") |> render_click()
    assert has_element?(view, "#referral-#{r.id}", "Accepted")
    assert has_element?(view, "#stat-response", "0 min")
    assert Referrals.get_referral!(r.id).responded_at

    view |> element("#complete-referral") |> render_click()
    assert has_element?(view, "#referral-#{r.id}", "Completed")
    refute has_element?(view, "#reassign-form")
  end

  test "reassigning moves the referral to another facility", %{
    conn: conn,
    clinic: clinic,
    hospital: hospital
  } do
    r = referral("Rita", clinic, :clinic, ["sore throat"])
    {:ok, view, _} = live(conn, ~p"/clinician/referrals/#{r.id}")

    view |> form("#reassign-form", %{facility_id: hospital.id}) |> render_submit()

    assert render(view) =~ "Reassigned to Test Hospital."
    assert Referrals.get_referral!(r.id).to_facility_id == hospital.id
    assert has_element?(view, "#referral-detail", "to Test Hospital")
  end

  test "viewing as a clinician shows only their facility, including live arrivals", %{
    conn: conn,
    clinic: clinic,
    hospital: hospital,
    nurse: nurse
  } do
    referral("Rita", clinic, :clinic, ["sore throat"])
    {:ok, view, _} = live(conn, ~p"/clinician?as=#{nurse.id}")

    assert has_element?(view, "#viewer", "Nurse Jane Doe · Triage Nurse · Test Hospital")
    assert has_element?(view, "#empty-queue")

    # A clinic referral doesn't show up; a hospital one arrives highlighted.
    referral("Carl", clinic, :clinic, ["cough"])
    umar = referral("Umar", hospital, :urgent, ["chest pain"])
    refute render(view) =~ "Carl"
    assert has_element?(view, "#referral-#{umar.id} [title='Just arrived']")
    assert has_element?(view, "#stat-new-today", "1")
  end

  test "search and status tabs filter the queue", %{conn: conn, clinic: clinic} do
    rita = referral("Rita", clinic, :clinic, ["sore throat"])
    carl = referral("Carl", clinic, :clinic, ["cough"])
    {:ok, _} = Referrals.update_referral(carl, %{status: :accepted})

    {:ok, view, _} = live(conn, ~p"/clinician")
    assert has_element?(view, "#tab-pending", "New · 1")
    assert has_element?(view, "#tab-accepted", "Accepted · 1")

    view |> element("#tab-pending") |> render_click()
    assert has_element?(view, "#referral-#{rita.id}")
    refute has_element?(view, "#referral-#{carl.id}")

    view |> element("#tab-all") |> render_click()
    view |> form("#referral-search-form", %{search: "cough"}) |> render_change()
    assert has_element?(view, "#referral-#{carl.id}")
    refute has_element?(view, "#referral-#{rita.id}")
  end
end
