defmodule CareRoute.IntakeWorkerTest do
  use CareRouteWeb.ConnCase, async: true
  use Oban.Testing, repo: CareRoute.Repo

  import Ecto.Query, only: [where: 2]
  import Phoenix.LiveViewTest

  alias CareRoute.Intake
  alias CareRoute.Workers.IntakeWorker

  setup do
    {:ok, patient} = Intake.create_patient(%{age: 30})
    {:ok, conversation} = Intake.start_conversation(patient)
    {:ok, conversation} = Intake.submit_patient_message(conversation, "I have a cough")
    %{conversation: conversation}
  end

  defp run(conversation, opts) do
    perform_job(IntakeWorker, %{conversation_id: conversation.id}, opts)
  end

  test "retries quickly while attempts remain, without posting anything", %{conversation: c} do
    Process.put(:care_route_ai_result, {:error, :timeout})

    assert {:error, :timeout} = run(c, attempt: 1)
    assert length(Intake.get_conversation!(c.id).transcript) == 2
    assert IntakeWorker.backoff(%Oban.Job{attempt: 1}) == 3
  end

  test "an invalid AI reply is retried too", %{conversation: c} do
    Process.put(:care_route_ai_result, {:ok, %{"next_action" => "diagnose"}})
    assert {:error, :invalid_ai_reply} = run(c, attempt: 1)
  end

  test "after the last attempt the patient sees a notice and can retry", %{
    conn: conn,
    conversation: c
  } do
    {:ok, view, _} = live(conn, ~p"/intake/#{c.id}")
    assert has_element?(view, "#thinking")

    Process.put(:care_route_ai_result, {:error, :timeout})
    assert {:cancel, :timeout} = run(c, attempt: 3, max_attempts: 3)

    # Typing dots replaced by a notice with a Try again button.
    refute has_element?(view, "#thinking")
    assert has_element?(view, "#retry-answer", "Try again")
    assert render(view) =~ "having trouble connecting"

    # perform_job/3 runs inline and leaves the queued job alone; in production
    # that job is cancelled by now, which frees the one-job-per-conversation slot.
    Oban.cancel_all_jobs(where(Oban.Job, worker: "CareRoute.Workers.IntakeWorker"))

    # Retrying drops the notice and queues a fresh AI call.
    view |> element("#retry-answer") |> render_click()
    assert has_element?(view, "#thinking")
    refute Enum.any?(Intake.get_conversation!(c.id).transcript, &Intake.notice?/1)
    assert [_] = all_enqueued(worker: IntakeWorker)

    Process.delete(:care_route_ai_result)
    assert :ok = run(c, attempt: 1)
    assert render(view) =~ "How long has this been going on?"
  end

  test "notices never reach the AI and are dropped when the patient answers", %{
    conversation: c
  } do
    {:ok, c} = Intake.post_notice(Intake.get_conversation!(c.id), "Sorry, try again")

    assert [%{role: "user", content: "I have a cough"}] =
             CareRoute.AI.IntakePrompt.messages(c.transcript)

    {:ok, c} = Intake.submit_patient_message(c, "It started yesterday")
    refute Enum.any?(c.transcript, &Intake.notice?/1)
  end

  test "only one pending AI job per conversation", %{conversation: c} do
    assert {:ok, %Oban.Job{conflict?: true}} =
             Oban.insert(IntakeWorker.new(%{conversation_id: c.id}))

    assert [_] = all_enqueued(worker: IntakeWorker, args: %{conversation_id: c.id})
  end
end
