defmodule CareRoute.SafetyFlowTest do
  use CareRouteWeb.ConnCase, async: true
  use Oban.Testing, repo: CareRoute.Repo

  import Phoenix.LiveViewTest

  alias CareRoute.{Intake, Referrals}
  alias CareRoute.Workers.IntakeWorker

  defp conversation_with(message, language \\ "en") do
    {:ok, patient} = Intake.create_patient(%{age: 30, preferred_language: language})
    {:ok, conversation} = Intake.start_conversation(patient)
    {:ok, conversation} = Intake.submit_patient_message(conversation, message)
    conversation
  end

  defp run(conversation), do: perform_job(IntakeWorker, %{conversation_id: conversation.id})

  test "a danger phrase escalates without asking the AI" do
    # If the AI were asked, this would fail the job.
    Process.put(:care_route_ai_result, {:error, :should_not_be_called})
    c = conversation_with("My mother suddenly has slurred speech")

    assert :ok = run(c)
    c = Intake.get_conversation!(c.id)

    assert c.status == :urgent
    assert c.care_recommendation.urgency_level == :urgent
    assert "possible stroke signs (safety check)" in c.symptom_report.red_flags
    assert List.last(c.transcript)["content"] =~ "seek urgent care now"
  after
    Process.delete(:care_route_ai_result)
  end

  test "a negated danger sign goes to the AI as usual" do
    Process.put(:care_route_ai_result, {:error, :timeout})
    c = conversation_with("No chest pain, just a cough")

    assert {:error, :timeout} = perform_job(IntakeWorker, %{conversation_id: c.id}, attempt: 1)
    assert Intake.get_conversation!(c.id).status == :gathering
  after
    Process.delete(:care_route_ai_result)
  end

  test "possible self-harm gets a crisis response and urgent care", %{conn: conn} do
    c = conversation_with("Sitaki kuishi tena, nataka kujiua", "sw")

    assert :ok = run(c)
    c = Intake.get_conversation!(c.id)

    assert c.status == :urgent
    assert "possible self-harm risk (safety check)" in c.symptom_report.red_flags
    assert List.last(c.transcript)["content"] =~ "Huhitaji kukabiliana na hili peke yako"
    assert List.last(c.transcript)["content"] =~ "999 au 112"

    {:ok, _view, html} = live(conn, ~p"/intake/#{c.token}/results")
    assert html =~ "Umetaja mawazo ya kujidhuru"
  end

  test "configured crisis lines are added to the crisis message" do
    lines = Application.get_env(:care_route, :crisis_lines)

    Application.put_env(:care_route, :crisis_lines, [%{label: "Test Line", number: "0800"}])
    on_exit(fn -> Application.put_env(:care_route, :crisis_lines, lines) end)

    assert CareRoute.Intake.Phrases.t(:crisis, "en") =~
             "You can also call Test Line on 0800."
  end

  test "overlong messages are refused, with a message in the chat", %{conn: conn} do
    c = conversation_with("I have a headache")
    :ok = run(c)
    c = Intake.get_conversation!(c.id)
    too_long = String.duplicate("a", Intake.max_message_length() + 1)

    assert {:error, :too_long} = Intake.submit_patient_message(c, too_long)

    {:ok, view, _} = live(conn, ~p"/intake/#{c.token}")
    assert has_element?(view, "input[name=message][maxlength='1000']")

    html = view |> form("#message-form", message: too_long) |> render_submit()
    assert html =~ "That message is too long"
  end

  test "a conversation can only have one referral" do
    c = conversation_with("I have a headache")

    facility =
      CareRoute.Repo.insert!(%CareRoute.Facilities.Facility{
        name: "Test Clinic",
        type: :clinic,
        partner: true
      })

    attrs = %{patient_id: c.patient_id, conversation_id: c.id, to_facility_id: facility.id}

    assert {:ok, _} = Referrals.create_referral(attrs)

    assert {:error, %Ecto.Changeset{errors: [conversation_id: _]}} =
             Referrals.create_referral(attrs)
  end
end
