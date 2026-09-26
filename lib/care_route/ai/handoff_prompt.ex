defmodule CareRoute.AI.HandoffPrompt do
  @moduledoc """
  System prompt and schema for call site #2: the clinician-facing handoff summary,
  generated once intake is complete and stored on the referral.
  """

  alias CareRoute.Referrals.Referral

  def system do
    """
    You write concise clinical handoff notes for a clinician receiving a patient
    referred by CareRoute, a care-navigation assistant. Use only facts stated in the
    intake; never invent vitals, history, or findings, and write "not reported" when
    something is unknown. Do not give a diagnosis; you may list what the clinician
    may want to assess. Write in English regardless of the patient's language, in
    clinical shorthand a triage nurse can read in under 30 seconds. Answers marked
    "(spoken)" were transcribed by speech recognition; if one looks garbled, say so
    rather than interpreting it.
    """
  end

  def tool do
    string_list = %{"type" => "array", "items" => %{"type" => "string"}}

    %{
      "name" => "record_handoff",
      "description" => "Record the structured clinician handoff note.",
      "input_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ~w(chief_complaint history red_flags triage_level suggested_assessment),
        "properties" => %{
          "chief_complaint" => %{"type" => "string"},
          "history" => %{
            "type" => "string",
            "description" => "2-3 sentences: onset, duration, severity, relevant negatives."
          },
          "red_flags" => string_list,
          "triage_level" => %{"type" => "string", "enum" => ~w(self_care clinic urgent)},
          "suggested_assessment" => string_list
        }
      }
    }
  end

  @doc "Builds the single user message describing the completed intake."
  def messages(%Referral{} = referral, conversation) do
    patient = referral.patient
    report = conversation.symptom_report
    rec = conversation.care_recommendation

    transcript =
      conversation.transcript
      |> Enum.reject(&CareRoute.Intake.notice?/1)
      |> Enum.map_join("\n", fn %{"role" => role, "content" => c} = msg ->
        if msg["via"] == "voice", do: "#{role} (spoken): #{c}", else: "#{role}: #{c}"
      end)

    content = """
    Patient age: #{patient.age || "not reported"}
    Patient language: #{patient.preferred_language}
    Referred to: #{referral.to_facility.name} (#{referral.to_facility.type})
    CareRoute urgency: #{rec && rec.urgency_level}
    Extracted symptoms: #{report && Enum.join(report.symptoms, ", ")}
    Duration: #{report && report.duration}
    Severity: #{report && report.severity}
    Red flags: #{report && Enum.join(report.red_flags, ", ")}

    Intake transcript:
    #{transcript}
    """

    [%{role: "user", content: content}]
  end

  @doc "Renders the structured note as the plain text stored in `referrals.ai_summary`."
  def format(note) do
    red_flags =
      if note["red_flags"] in [nil, []],
        do: "none reported",
        else: Enum.join(note["red_flags"], "; ")

    """
    CC: #{note["chief_complaint"]}
    HPI: #{note["history"]}
    Red flags: #{red_flags}
    CareRoute triage: #{note["triage_level"]}
    Consider: #{Enum.join(note["suggested_assessment"] || [], "; ")}
    """
    |> String.trim()
  end

  @doc "Offline stand-in built from the stored symptom report."
  def stub(_referral, conversation) do
    report = conversation.symptom_report
    rec = conversation.care_recommendation

    %{
      "chief_complaint" => (report && Enum.join(report.symptoms, ", ")) || "not reported",
      "history" =>
        "Duration: #{(report && report.duration) || "not reported"}. " <>
          "Severity: #{(report && report.severity) || "not reported"}. (offline stub summary)",
      "red_flags" => (report && report.red_flags) || [],
      "triage_level" => to_string((rec && rec.urgency_level) || "clinic"),
      "suggested_assessment" => ["Vital signs", "Hydration status"]
    }
  end
end
