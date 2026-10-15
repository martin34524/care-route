defmodule CareRouteWeb.QuickRepliesTest do
  use CareRouteWeb.ConnCase, async: true
  use Oban.Testing, repo: CareRoute.Repo

  import Phoenix.LiveViewTest

  alias CareRoute.Intake
  alias CareRoute.Workers.IntakeWorker

  # Starts a chat, answers once, and has the AI ask `question`.
  defp chat_asking(conn, question, language \\ "en") do
    {:ok, patient} = Intake.create_patient(%{age: 30, preferred_language: language})
    {:ok, c} = Intake.start_conversation(patient)
    {:ok, c} = Intake.submit_patient_message(c, "I have a headache")

    Process.put(
      :care_route_ai_result,
      {:ok,
       %{
         "extracted" => %{"symptoms" => ["headache"], "red_flags" => []},
         "next_action" => "ask_question",
         "next_question" => question,
         "urgency_signal" => false
       }}
    )

    :ok = perform_job(IntakeWorker, %{conversation_id: c.id})
    Process.delete(:care_route_ai_result)
    {:ok, view, _} = live(conn, ~p"/intake/#{c.token}")
    {view, c}
  end

  test "no quick replies on the opening greeting", %{conn: conn} do
    {:ok, patient} = Intake.create_patient(%{age: 30})
    {:ok, c} = Intake.start_conversation(patient)
    {:ok, view, _} = live(conn, ~p"/intake/#{c.token}")
    refute has_element?(view, "#quick-replies")
  end

  test "a yes/no question offers Yes, No and Not sure; tapping one answers", %{conn: conn} do
    {view, c} = chat_asking(conn, "Is the pain getting worse?")

    assert has_element?(view, "#quick-replies button", "Yes")
    assert has_element?(view, "#quick-replies button", "Not sure")

    view |> element(~s(#quick-replies button[phx-value-message="No"])) |> render_click()

    assert List.last(Intake.get_conversation!(c.id).transcript)["content"] == "No"
    # Waiting for the next question: no buttons.
    refute has_element?(view, "#quick-replies")
  end

  test "a severity question offers the three levels, in the patient's language", %{conn: conn} do
    {view, _c} = chat_asking(conn, "Je, maumivu ni kidogo, wastani, au kali?", "sw")

    assert has_element?(view, "#quick-replies button", "Kidogo")
    assert has_element?(view, "#quick-replies button", "Kali")
  end

  test "open questions get no quick replies", %{conn: conn} do
    {view, _c} = chat_asking(conn, "How long has this been going on?")
    refute has_element?(view, "#quick-replies")
  end
end
