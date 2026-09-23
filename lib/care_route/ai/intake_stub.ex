defmodule CareRoute.AI.IntakeStub do
  @moduledoc """
  Offline stand-in for the Claude intake call, used when no ANTHROPIC_API_KEY is
  set. Returns the same JSON contract so the UI and routing can be built first.
  """

  @red_flag_words ~w(breathing breathe chest unconscious seizure bleeding confused blue)
  @questions [
    "How long has this been going on?",
    "How severe would you say it is — mild, moderate, or severe?",
    "Is there any difficulty breathing, chest pain, or confusion?"
  ]

  def extract(transcript) do
    patient_msgs = for %{"role" => "patient", "content" => c} <- transcript, do: c
    text = patient_msgs |> Enum.join(" ") |> String.downcase()
    red_flags = Enum.filter(@red_flag_words, &String.contains?(text, &1))
    # Answers to "is there any difficulty breathing..." like "no" shouldn't count.
    red_flags =
      if String.contains?(text, ["no difficulty", "no trouble"]), do: [], else: red_flags

    base = %{
      "extracted" => %{
        "symptoms" => [List.first(patient_msgs)],
        "duration" => Enum.at(patient_msgs, 1),
        "severity" => Enum.at(patient_msgs, 2),
        "red_flags" => red_flags
      },
      "urgency_signal" => red_flags != [],
      "next_question" => nil,
      "recommendation" => nil
    }

    cond do
      red_flags != [] ->
        Map.put(base, "next_action", "escalate_urgent")

      length(patient_msgs) <= length(@questions) ->
        Map.merge(base, %{
          "next_action" => "ask_question",
          "next_question" => Enum.at(@questions, length(patient_msgs) - 1)
        })

      true ->
        Map.merge(base, %{
          "next_action" => "ready_for_recommendation",
          "recommendation" => %{
            "urgency_level" => "clinic",
            "reasoning" => ["Symptoms have lasted a few days without red flags (stub response)."],
            "warning_signs" => ["Trouble breathing", "Symptoms getting much worse quickly"]
          }
        })
    end
  end
end
