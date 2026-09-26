defmodule CareRoute.HandoffWorkerTest do
  # Not async: the clinician dashboard listens on the global referrals topic.
  use CareRouteWeb.ConnCase, async: false
  use Oban.Testing, repo: CareRoute.Repo

  import Ecto.Query, only: [where: 2]
  import Phoenix.LiveViewTest

  alias CareRoute.{Facilities, Intake, Referrals}
  alias CareRoute.Workers.HandoffWorker

  setup do
    {:ok, clinic} = Facilities.create_facility(%{name: "Test Clinic", type: :clinic})
    {:ok, patient} = Intake.create_patient(%{age: 30})
    {:ok, conversation} = Intake.start_conversation(patient)
    {:ok, _} = Intake.append_message(conversation, "patient", "sore throat")

    {:ok, referral} =
      Referrals.create_referral(%{
        patient_id: patient.id,
        conversation_id: conversation.id,
        to_facility_id: clinic.id
      })

    %{referral: referral}
  end

  defp run(referral, opts \\ []) do
    perform_job(HandoffWorker, %{referral_id: referral.id}, opts)
  end

  test "a summary missing required fields is retried", %{referral: r} do
    Process.put(:care_route_ai_result, {:ok, %{"chief_complaint" => ""}})
    assert {:error, :invalid_ai_reply} = run(r, attempt: 1)
    refute Referrals.get_referral!(r.id).summary_failed_at
  end

  test "after the last attempt clinicians see 'unavailable' and can retry", %{
    conn: conn,
    referral: r
  } do
    {:ok, view, _} = live(conn, ~p"/clinician/referrals/#{r.id}")
    assert render(view) =~ "Generating summary"

    Process.put(:care_route_ai_result, {:error, :rate_limited})
    assert {:cancel, :rate_limited} = run(r, attempt: 3, max_attempts: 3)

    refute render(view) =~ "Generating summary"
    assert has_element?(view, "#summary-failed", "Summary unavailable")

    # The inline run leaves the queued job alone; in production it's cancelled.
    Oban.cancel_all_jobs(where(Oban.Job, worker: "CareRoute.Workers.HandoffWorker"))

    view |> element("#retry-summary") |> render_click()
    assert render(view) =~ "Generating summary"
    assert_enqueued(worker: HandoffWorker, args: %{referral_id: r.id})

    Process.delete(:care_route_ai_result)
    assert :ok = run(r)
    assert has_element?(view, "#ai-summary", "CC:")
    refute has_element?(view, "#summary-failed")
  end
end
