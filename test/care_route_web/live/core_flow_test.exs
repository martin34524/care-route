defmodule CareRouteWeb.CoreFlowTest do
  use CareRouteWeb.ConnCase, async: true
  use Oban.Testing, repo: CareRoute.Repo

  import Phoenix.LiveViewTest

  alias CareRoute.{Facilities, Intake, Referrals}
  alias CareRoute.Workers.IntakeWorker

  # Uses the offline IntakeStub (no ANTHROPIC_API_KEY in test).
  setup do
    {:ok, clinic} =
      Facilities.create_facility(%{name: "Test Clinic", type: :clinic, distance_km: 1.0})

    {:ok, hospital} =
      Facilities.create_facility(%{name: "Test Hospital", type: :hospital, distance_km: 3.0})

    {:ok, patient} = Intake.create_patient(%{name: "Asha", age: 3})
    {:ok, conversation} = Intake.start_conversation(patient)
    %{clinic: clinic, hospital: hospital, conversation: conversation}
  end

  defp say(view, conversation, text) do
    view |> form("#message-form", %{message: text}) |> render_submit()
    assert :ok = perform_job(IntakeWorker, %{conversation_id: conversation.id})
  end

  test "routine case: questions, recommendation, referral reaches clinician", %{
    conn: conn,
    conversation: conversation,
    clinic: clinic
  } do
    {:ok, clinician_view, _} = live(conn, ~p"/clinician")
    {:ok, view, _} = live(conn, ~p"/intake/#{conversation.id}")

    say(view, conversation, "My 3-year-old has had a fever")
    assert render(view) =~ "How long"
    say(view, conversation, "2 days")
    say(view, conversation, "moderate")
    say(view, conversation, "No difficulty with any of those")

    assert has_element?(view, "#recommendation", "Visit a clinic")

    view |> element("#facility-#{clinic.id} button") |> render_click()
    assert render(view) =~ "Referral sent to Test Clinic"

    assert render(clinician_view) =~ "Test Clinic"
    assert [_] = Referrals.list_referrals()
  end

  test "red flag short-circuits to the urgent pathway", %{
    conn: conn,
    conversation: conversation,
    hospital: hospital
  } do
    {:ok, view, _} = live(conn, ~p"/intake/#{conversation.id}")

    say(view, conversation, "Fever and she is having trouble breathing")

    assert has_element?(view, "#recommendation", "Seek urgent care now")
    assert has_element?(view, "#facility-#{hospital.id}")
    refute has_element?(view, "#message-form")
    assert Intake.get_conversation!(conversation.id).status == :urgent
  end
end
