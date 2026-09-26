defmodule CareRouteWeb.CoreFlowTest do
  use CareRouteWeb.ConnCase, async: true
  use Oban.Testing, repo: CareRoute.Repo

  import Phoenix.LiveViewTest

  alias CareRoute.{Facilities, Intake, Referrals}
  alias CareRoute.Workers.{HandoffWorker, IntakeWorker}

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
    {:ok, view, _} = live(conn, ~p"/intake/#{conversation.token}")

    say(view, conversation, "My 3-year-old has had a fever")
    assert render(view) =~ "How long"
    say(view, conversation, "2 days")
    say(view, conversation, "moderate")
    say(view, conversation, "No difficulty with any of those")

    # The chat hands off to the results page.
    assert {:ok, results, _} =
             view
             |> element(~s(a[href="/intake/#{conversation.token}/results"]))
             |> render_click()
             |> follow_redirect(conn)

    assert has_element?(results, "#recommendation", "Clinic visit")
    assert has_element?(results, "#recommendation", "Moderate urgency")

    results |> element("#facility-#{clinic.id} button", "Request referral") |> render_click()
    assert has_element?(results, "#referral-sent", "Referral sent to Test Clinic")
    assert has_element?(results, "#facility-#{clinic.id}", "Referral sent")

    # The referral is still shown after a reload.
    {:ok, reloaded, _} = live(conn, ~p"/intake/#{conversation.token}/results")
    assert has_element?(reloaded, "#referral-sent", "Test Clinic")

    assert render(clinician_view) =~ "Test Clinic"
    assert [referral] = Referrals.list_referrals()

    {:ok, show_view, _} = live(conn, ~p"/clinician/referrals/#{referral.id}")
    assert render(show_view) =~ "Generating summary"

    assert_enqueued(worker: HandoffWorker, args: %{referral_id: referral.id})
    assert :ok = perform_job(HandoffWorker, %{referral_id: referral.id})

    assert has_element?(show_view, "#ai-summary", "CC:")
    assert has_element?(show_view, "#ai-summary", "Red flags: none reported")
  end

  test "chat shows progress, clears the input, and ignores sends while waiting", %{
    conn: conn,
    conversation: conversation
  } do
    {:ok, view, _} = live(conn, ~p"/intake/#{conversation.token}")
    assert render(view) =~ "Question 1 of 4"
    assert has_element?(view, "#message-input-0")

    view |> form("#message-form", %{message: "My child has a fever"}) |> render_submit()

    # New input id, so the browser drops the typed text.
    assert has_element?(view, "#message-input-1")
    assert has_element?(view, "#thinking")
    assert has_element?(view, ~s(#message-form button[disabled]))

    # A second send before the reply arrives is ignored: no extra message or job.
    view |> form("#message-form", %{message: "again"}) |> render_submit()
    assert length(Intake.get_conversation!(conversation.id).transcript) == 2
    assert [_] = all_enqueued(worker: IntakeWorker)

    assert :ok = perform_job(IntakeWorker, %{conversation_id: conversation.id})
    refute has_element?(view, "#thinking")
    assert render(view) =~ "Question 2 of 4"
  end

  test "Kiswahili patients get fixed messages in Kiswahili", %{conn: conn} do
    {:ok, patient} = Intake.create_patient(%{age: 30, preferred_language: "sw"})
    {:ok, conversation} = Intake.start_conversation(patient)
    {:ok, view, _} = live(conn, ~p"/intake/#{conversation.token}")

    assert render(view) =~ "Habari, mimi ni CareRoute"
    say(view, conversation, "Nina homa na ninashindwa kupumua, chest pain")
    assert render(view) =~ "tafuta huduma ya dharura"
    assert render(view) =~ "Ikiwa hii ni dharura ya kiafya"
    assert render(view) =~ "Ona pendekezo langu"

    # The whole results page is in Kiswahili too.
    {:ok, results, _} = live(conn, ~p"/intake/#{conversation.token}/results")
    assert has_element?(results, "#recommendation", "Huduma ya dharura")
    assert has_element?(results, "#recommendation", "Tuma rufaa kwa mhudumu wa afya")
    assert has_element?(results, "#facilities", "Omba rufaa")
    assert render(results) =~ "CareRoute AI haitambui magonjwa"
  end

  test "admin dashboard shows routing counts and updates on new referrals", %{
    conn: conn,
    conversation: conversation,
    hospital: hospital
  } do
    {:ok, admin, _} = live(conn, ~p"/admin")
    assert has_element?(admin, "#stat-in-progress", "1")

    {:ok, view, _} = live(conn, ~p"/intake/#{conversation.token}")
    say(view, conversation, "Chest pain and trouble breathing")
    {:ok, results, _} = live(conn, ~p"/intake/#{conversation.token}/results")
    results |> element("#facility-#{hospital.id} button") |> render_click()

    assert has_element?(admin, "#stat-urgent", "1")
    assert has_element?(admin, "#facility-load", "Test Hospital")
  end

  test "red flag short-circuits to the urgent pathway", %{
    conn: conn,
    conversation: conversation,
    hospital: hospital
  } do
    {:ok, view, _} = live(conn, ~p"/intake/#{conversation.token}")

    say(view, conversation, "Fever and she is having trouble breathing")

    assert has_element?(view, "#message-form input[disabled]")
    assert has_element?(view, "header", "Urgent · please seek care now")

    assert has_element?(
             view,
             ~s(a[href="/intake/#{conversation.token}/results"]),
             "See my recommendation"
           )

    assert Intake.get_conversation!(conversation.id).status == :urgent

    {:ok, results, _} = live(conn, ~p"/intake/#{conversation.token}/results")
    assert has_element?(results, "#recommendation", "Urgent care")
    assert has_element?(results, "#recommendation", "High urgency · seek care now")
    assert has_element?(results, "#recommendation", "Find urgent care near me")
    assert has_element?(results, "#facility-#{hospital.id}")

    # "Send referral to a clinician" refers to the nearest offered facility.
    results |> element("#send-referral") |> render_click()
    assert has_element?(results, "#referral-sent", "Test Hospital")
    refute has_element?(results, "#send-referral")
  end

  test "patient links use an unguessable token, not the sequential id", %{
    conn: conn,
    conversation: conversation
  } do
    assert String.length(conversation.token) >= 22
    refute conversation.token == to_string(conversation.id)

    assert_raise Ecto.NoResultsError, fn -> live(conn, "/intake/#{conversation.id}") end
    assert_raise Ecto.NoResultsError, fn -> live(conn, "/intake/#{conversation.id}/results") end
    assert {:ok, _view, _} = live(conn, ~p"/intake/#{conversation.token}")
  end

  test "results page sends unfinished intakes back to the chat", %{
    conn: conn,
    conversation: conversation
  } do
    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/intake/#{conversation.token}/results")

    assert to == ~p"/intake/#{conversation.token}"
  end
end
