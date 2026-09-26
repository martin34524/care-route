defmodule CareRouteWeb.StartTest do
  use CareRouteWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CareRoute.Repo
  alias CareRoute.Intake.Patient

  defp submit(view, params) do
    view |> form("#start-form", patient: params) |> render_submit()
  end

  test "can't start without ticking the consent box", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/start")
    assert has_element?(view, "#start-form button[type=submit][disabled]")

    submit(view, %{name: "Asha", age: "30", consent: "false"})
    assert has_element?(view, "#start-error", "Please tick the box to continue.")
    assert Repo.aggregate(Patient, :count) == 0
  end

  test "starting records consent and opens the chat", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/start")

    assert {:error, {:live_redirect, %{to: "/intake/" <> token}}} =
             submit(view, %{name: " Asha ", age: "30", consent: "true"})

    assert [patient] = Repo.all(Patient)
    assert patient.name == "Asha"
    assert patient.age == 30
    assert patient.consented_at
    assert String.length(token) >= 22
  end

  test "picking Kiswahili switches the page and the patient's language", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/start")

    view |> form("#start-form", patient: %{preferred_language: "sw"}) |> render_change()
    assert render(view) =~ "Kabla hatujaanza"
    assert render(view) =~ "Ninaelewa kwamba CareRoute haitambui magonjwa"

    submit(view, %{preferred_language: "sw", consent: "true"})
    assert [%{preferred_language: "sw"}] = Repo.all(Patient)
  end

  test "an impossible age shows an error", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/start")
    submit(view, %{age: "400", consent: "true"})
    assert has_element?(view, "#start-error", "Enter an age between 0 and 129.")
  end

  test "the chat and results pages offer Start over", %{conn: conn} do
    {:ok, patient} = CareRoute.Intake.create_patient(%{})
    {:ok, conversation} = CareRoute.Intake.start_conversation(patient)
    {:ok, view, _} = live(conn, ~p"/intake/#{conversation.token}")
    assert has_element?(view, ~s(#start-over[href="/start"]), "Start over")
  end
end
