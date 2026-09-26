defmodule CareRoute.RoutingTest do
  use CareRoute.DataCase, async: true

  alias CareRoute.{Intake, Routing}

  setup do
    {:ok, patient} = Intake.create_patient(%{age: 30})
    {:ok, conversation} = Intake.start_conversation(patient)
    {:ok, conversation} = Intake.append_message(conversation, "patient", "I have a cough")
    %{conversation: Intake.get_conversation!(conversation.id)}
  end

  defp reply(overrides) do
    Map.merge(
      %{
        "extracted" => %{
          "symptoms" => ["cough"],
          "duration" => nil,
          "severity" => nil,
          "red_flags" => []
        },
        "next_action" => "ask_question",
        "next_question" => "How long have you had it?",
        "urgency_signal" => false,
        "recommendation" => nil
      },
      overrides
    )
  end

  defp reload(conversation), do: Intake.get_conversation!(conversation.id)

  test "asks the next question", %{conversation: c} do
    assert {:ok, _} = Routing.apply_extraction(c, reply(%{}))
    c = reload(c)
    assert List.last(c.transcript)["content"] == "How long have you had it?"
    assert c.status == :gathering
    assert c.symptom_report.symptoms == ["cough"]
  end

  test "recommends with a valid level", %{conversation: c} do
    rec = %{"urgency_level" => "self_care", "reasoning" => ["Mild."], "warning_signs" => []}

    assert {:ok, _} =
             Routing.apply_extraction(
               c,
               reply(%{"next_action" => "ready_for_recommendation", "recommendation" => rec})
             )

    c = reload(c)
    assert c.status == :assessed
    assert c.care_recommendation.urgency_level == :self_care
  end

  test "any red flag escalates, even in an otherwise broken reply", %{conversation: c} do
    broken = %{
      "extracted" => %{"red_flags" => ["chest pain"]},
      "next_action" => "something_else"
    }

    assert {:ok, _} = Routing.apply_extraction(c, broken)
    c = reload(c)
    assert c.status == :urgent
    assert c.care_recommendation.warning_signs == ["chest pain"]
  end

  describe "replies that can't be acted on are rejected for a retry" do
    test "unknown next_action", %{conversation: c} do
      assert {:error, :invalid_ai_reply} =
               Routing.apply_extraction(c, reply(%{"next_action" => "diagnose"}))
    end

    test "empty or missing question", %{conversation: c} do
      assert {:error, :invalid_ai_reply} =
               Routing.apply_extraction(c, reply(%{"next_question" => "  "}))

      assert {:error, :invalid_ai_reply} =
               Routing.apply_extraction(c, reply(%{"next_question" => nil}))
    end

    test "recommendation without a valid level", %{conversation: c} do
      for rec <- [nil, %{"urgency_level" => "er"}, %{"reasoning" => []}] do
        assert {:error, :invalid_ai_reply} =
                 Routing.apply_extraction(
                   c,
                   reply(%{"next_action" => "ready_for_recommendation", "recommendation" => rec})
                 )
      end
    end

    test "missing extracted block doesn't crash", %{conversation: c} do
      assert {:error, :invalid_ai_reply} = Routing.apply_extraction(c, %{"next_action" => nil})
    end

    test "nothing is posted to the chat", %{conversation: c} do
      Routing.apply_extraction(c, reply(%{"next_question" => ""}))
      assert length(reload(c).transcript) == length(c.transcript)
    end
  end

  test "another question past the answer limit is rejected", %{conversation: c} do
    c =
      Enum.reduce(1..5, c, fn i, c ->
        {:ok, c} = Intake.append_message(c, "assistant", "Question #{i}?")
        {:ok, c} = Intake.append_message(c, "patient", "Answer #{i}")
        c
      end)

    assert Routing.question_limit_reached?(c)
    assert {:error, :question_limit} = Routing.apply_extraction(c, reply(%{}))
  end
end
