defmodule CareRoute.AI.IntakePrompt do
  @moduledoc """
  System prompt and tool schema for call site #1: conversational intake/extraction.
  """

  @doc """
  The intake system prompt. `final: true` is used once the patient has answered
  as many questions as intake allows; the model must then decide.
  """
  def system(language \\ "en", opts \\ []) do
    """
    You are CareRoute, a healthcare navigation assistant. You help a patient decide
    WHERE to seek care (self-care at home, a clinic visit, or urgent care). You do
    not diagnose, name conditions, or suggest medications or doses.

    On every turn, respond with the record_intake JSON:
    - extracted: everything learned so far across the whole conversation (symptoms,
      duration, severity, and any red flags such as difficulty breathing, chest pain,
      confusion, seizures, severe bleeding, or signs of dehydration in a child).
    - next_action:
      - "escalate_urgent" as soon as any red flag is present; set urgency_signal true.
      - "ask_question" if you need more information; put ONE short, plain-language
        question in next_question. Ask about one thing at a time (not "X, and also
        Y?"), and never ask about something the patient has already told you anywhere
        in the conversation, even in passing. Prioritise checking for red flags
        early.
      - "ready_for_recommendation" once you know the main symptoms, duration, severity,
        and have checked for red flags (usually 2-4 questions, never more than 5);
        fill recommendation.
    - recommendation: null unless next_action is "ready_for_recommendation". Reasoning
      and warning_signs should be short patient-facing sentences about when to seek
      more urgent care, not diagnoses.

    The patient's preferred language is #{CareRoute.Intake.Phrases.language_name(language)}.
    Write next_question, reasoning, and warning_signs in that language, in simple words.
    Always write the extracted fields in English for the clinician.

    Some answers are dictated and transcribed by speech recognition, so they may
    contain misheard words. If an answer seems garbled or contradictory, ask the
    patient to clarify rather than guessing.
    #{if opts[:final], do: final_turn()}\
    """
  end

  defp final_turn do
    """

    The patient has answered as many questions as intake allows. Do not ask another
    question: choose "ready_for_recommendation" (or "escalate_urgent" if any red flag
    is present) based on what you know, and mention in the reasoning if important
    details are missing.
    """
  end

  def tool do
    nullable_string = %{"type" => ["string", "null"]}
    string_list = %{"type" => "array", "items" => %{"type" => "string"}}

    %{
      "name" => "record_intake",
      "description" => "Record the structured intake state and choose the next step.",
      "input_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ~w(extracted next_action next_question urgency_signal recommendation),
        "properties" => %{
          "extracted" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(symptoms duration severity red_flags),
            "properties" => %{
              "symptoms" => string_list,
              "duration" => nullable_string,
              "severity" => nullable_string,
              "red_flags" => string_list
            }
          },
          "next_action" => %{
            "type" => "string",
            "enum" => ~w(ask_question escalate_urgent ready_for_recommendation)
          },
          "next_question" => nullable_string,
          "urgency_signal" => %{"type" => "boolean"},
          "recommendation" => %{
            "anyOf" => [
              %{
                "type" => "object",
                "additionalProperties" => false,
                "required" => ~w(urgency_level reasoning warning_signs),
                "properties" => %{
                  "urgency_level" => %{"type" => "string", "enum" => ~w(self_care clinic urgent)},
                  "reasoning" => string_list,
                  "warning_signs" => string_list
                }
              },
              %{"type" => "null"}
            ]
          }
        }
      }
    }
  end

  @doc "Converts the stored transcript into Messages API turns."
  def messages(transcript) do
    transcript
    |> Enum.reject(&CareRoute.Intake.notice?/1)
    # The API requires the first turn to come from the user; drop the greeting.
    |> Enum.drop_while(&(&1["role"] != "patient"))
    |> Enum.map(fn
      %{"role" => "patient", "content" => c} -> %{role: "user", content: c}
      %{"role" => "assistant", "content" => c} -> %{role: "assistant", content: c}
    end)
  end
end
