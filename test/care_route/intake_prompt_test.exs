defmodule CareRoute.IntakePromptTest do
  use ExUnit.Case, async: true

  alias CareRoute.AI.IntakePrompt

  test "asks one thing at a time and never repeats answered questions" do
    prompt = IntakePrompt.system()
    assert prompt =~ "Ask about one thing at a time"
    assert prompt =~ "never ask about something the patient has already told you"
    refute prompt =~ "has answered as many questions"
  end

  test "the final turn forbids another question" do
    assert IntakePrompt.system("en", final: true) =~ "Do not ask another"
  end

  test "writes patient-facing text in the patient's language" do
    assert IntakePrompt.system("sw") =~ "preferred language is Kiswahili"
  end

  test "the schema requires every field the routing step reads" do
    %{"input_schema" => schema} = IntakePrompt.tool()

    assert Enum.sort(schema["required"]) ==
             ~w(extracted next_action next_question recommendation urgency_signal)

    assert schema["properties"]["next_action"]["enum"] ==
             ~w(ask_question escalate_urgent ready_for_recommendation)
  end
end
