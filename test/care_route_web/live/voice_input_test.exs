defmodule CareRouteWeb.VoiceInputTest do
  use CareRouteWeb.ConnCase, async: true
  use Oban.Testing, repo: CareRoute.Repo

  import Phoenix.LiveViewTest

  alias CareRoute.{Facilities, Intake, Referrals}
  alias CareRoute.Workers.IntakeWorker

  setup do
    {:ok, patient} = Intake.create_patient(%{name: "Vera", age: 30})
    {:ok, conversation} = Intake.start_conversation(patient)
    %{conversation: conversation}
  end

  test "the mic is offered while intake is open, in the patient's language", %{conn: conn} do
    {:ok, patient} = Intake.create_patient(%{preferred_language: "sw"})
    {:ok, conversation} = Intake.start_conversation(patient)
    {:ok, view, _} = live(conn, ~p"/intake/#{conversation.token}")

    assert has_element?(view, "#voice-input[phx-hook=VoiceInput][data-lang=sw-KE]")
    assert has_element?(view, "#voice-input button[aria-label='Jibu kwa sauti']")

    view |> form("#message-form", %{message: "chest pain, siwezi kupumua"}) |> render_submit()
    assert :ok = perform_job(IntakeWorker, %{conversation_id: conversation.id})

    # Closed conversation: no mic.
    refute has_element?(view, "#voice-input")
  end

  test "spoken answers are stored as voice and marked in the chat", %{
    conn: conn,
    conversation: conversation
  } do
    {:ok, view, _} = live(conn, ~p"/intake/#{conversation.token}")

    # input_mode is set by the VoiceInput hook in the browser.
    view
    |> form("#message-form", %{message: "my head hurts"})
    |> render_submit(%{input_mode: "voice"})

    assert [_greeting, %{"content" => "my head hurts", "via" => "voice"}] =
             Intake.get_conversation!(conversation.id).transcript

    assert has_element?(view, "#msg-1 [aria-label='Spoken answer']")

    # The mode resets for the next message, and typed answers aren't marked.
    assert has_element?(view, "#input-mode-1[value=text]")
    assert :ok = perform_job(IntakeWorker, %{conversation_id: conversation.id})
    view |> form("#message-form", %{message: "two days"}) |> render_submit()

    assert %{"content" => "two days"} =
             typed = List.last(Intake.get_conversation!(conversation.id).transcript)

    refute Map.has_key?(typed, "via")
    refute has_element?(view, "#msg-3 [aria-label='Spoken answer']")
  end

  test "new questions are sent to the read-aloud toggle", %{
    conn: conn,
    conversation: conversation
  } do
    {:ok, view, _} = live(conn, ~p"/intake/#{conversation.token}")

    assert has_element?(view, "#read-aloud[phx-hook=ReadAloud][data-lang=en-KE]")
    assert has_element?(view, "#read-aloud[data-latest^='Hi, I’m CareRoute']")
    assert has_element?(view, "#read-aloud button[aria-label='Read questions aloud']")

    view |> form("#message-form", %{message: "I have a cough"}) |> render_submit()
    refute_push_event(view, "read-aloud", %{})

    assert :ok = perform_job(IntakeWorker, %{conversation_id: conversation.id})
    assert_push_event(view, "read-aloud", %{text: "How long has this been going on?"})
  end

  test "recognition errors show a friendly message", %{conn: conn, conversation: conversation} do
    {:ok, view, _} = live(conn, ~p"/intake/#{conversation.token}")

    render_hook(view, "voice-error", %{"error" => "not-allowed"})
    assert render(view) =~ "Microphone access is blocked"

    render_hook(view, "voice-error", %{"error" => "no-speech"})
    assert render(view) =~ "I didn&#39;t catch that"
  end

  test "clinicians see which answers were spoken", %{conn: conn, conversation: conversation} do
    {:ok, clinic} = Facilities.create_facility(%{name: "Test Clinic", type: :clinic})
    {:ok, _} = Intake.submit_patient_message(conversation, "sore throat", via: :voice)
    assert :ok = perform_job(IntakeWorker, %{conversation_id: conversation.id})

    {:ok, referral} =
      Referrals.create_referral(%{
        patient_id: conversation.patient_id,
        conversation_id: conversation.id,
        to_facility_id: clinic.id
      })

    {:ok, view, _} = live(conn, ~p"/clinician/referrals/#{referral.id}")
    assert has_element?(view, "#referral-detail", "sore throat")
    assert has_element?(view, "#referral-detail span[title^='Transcribed from speech']", "spoken")
  end
end
