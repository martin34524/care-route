defmodule CareRoute.Routing do
  @moduledoc """
  Deterministic state machine over the AI extraction result.

  The AI call only extracts structure; this module decides what happens
  next by branching on `next_action`, never by re-reading free text:

    * `"ask_question"`             -> stay in `:gathering`, post the next question
    * `"escalate_urgent"`          -> short-circuit to `:urgent`
    * `"ready_for_recommendation"` -> move to `:assessed`, store the recommendation
  """

  alias CareRoute.{Intake, Repo}
  alias CareRoute.Intake.{Conversation, Phrases}
  alias CareRoute.Routing.CareRecommendation

  # Hard cap on patient answers before the AI must recommend or escalate.
  @max_answers 6

  @doc "Whether the patient has answered as many questions as intake allows."
  def question_limit_reached?(%Conversation{transcript: transcript}) do
    Enum.count(transcript, &(&1["role"] == "patient")) >= @max_answers
  end

  @doc """
  Applies one AI extraction result to the conversation.

  Returns `{:error, reason}` for a reply that can't be acted on (unknown next
  step, empty question, recommendation without a valid level, or another
  question past the limit) so the caller can retry with a fresh AI call.
  Danger signs always win: any red flag escalates, even in a malformed reply.
  """
  def apply_extraction(%Conversation{} = conversation, result) when is_map(result) do
    extracted = if is_map(result["extracted"]), do: result["extracted"], else: %{}
    red_flags = list(extracted["red_flags"])

    {:ok, _report} =
      Intake.upsert_symptom_report(conversation, %{
        symptoms: list(extracted["symptoms"]),
        duration: extracted["duration"],
        severity: extracted["severity"],
        red_flags: red_flags
      })

    if result["urgency_signal"] == true or red_flags != [] do
      escalate(conversation, result)
    else
      case next_step(result) do
        :escalate ->
          escalate(conversation, result)

        :recommend ->
          recommend(conversation, result)

        {:ask, question} ->
          if question_limit_reached?(conversation),
            do: {:error, :question_limit},
            else: Intake.append_message(conversation, "assistant", question)

        :invalid ->
          {:error, :invalid_ai_reply}
      end
    end
  end

  defp next_step(%{"next_action" => "escalate_urgent"}), do: :escalate

  defp next_step(%{
         "next_action" => "ready_for_recommendation",
         "recommendation" => %{"urgency_level" => level}
       })
       when level in ~w(self_care clinic urgent),
       do: :recommend

  defp next_step(%{"next_action" => "ask_question", "next_question" => question})
       when is_binary(question) do
    case String.trim(question) do
      "" -> :invalid
      question -> {:ask, question}
    end
  end

  defp next_step(_result), do: :invalid

  defp list(value) when is_list(value), do: Enum.filter(value, &is_binary/1)
  defp list(_value), do: []

  defp escalate(conversation, result) do
    rec = if is_map(result["recommendation"]), do: result["recommendation"], else: %{}
    extracted = if is_map(result["extracted"]), do: result["extracted"], else: %{}

    with {:ok, _rec} <-
           create_recommendation(conversation, %{
             urgency_level: :urgent,
             reasoning: list(rec["reasoning"]),
             warning_signs: list(extracted["red_flags"])
           }),
         {:ok, conversation} <-
           Intake.append_message(
             conversation,
             "assistant",
             Phrases.t(:urgent, language(conversation))
           ) do
      Intake.update_status(conversation, :urgent)
    end
  end

  defp recommend(conversation, result) do
    rec = result["recommendation"]

    with {:ok, _rec} <-
           create_recommendation(conversation, %{
             urgency_level: rec["urgency_level"],
             reasoning: list(rec["reasoning"]),
             warning_signs: list(rec["warning_signs"])
           }),
         {:ok, conversation} <-
           Intake.append_message(
             conversation,
             "assistant",
             Phrases.t(:ready, language(conversation))
           ) do
      Intake.update_status(conversation, :assessed)
    end
  end

  defp language(%Conversation{patient: %{preferred_language: language}}), do: language
  defp language(%Conversation{}), do: "en"

  def create_recommendation(%Conversation{id: conversation_id}, attrs) do
    %CareRecommendation{}
    |> CareRecommendation.changeset(Map.put(attrs, :conversation_id, conversation_id))
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :conversation_id, :inserted_at]},
      conflict_target: :conversation_id
    )
  end

  @doc "Recommendation counts keyed by urgency level."
  def count_by_urgency do
    import Ecto.Query

    Repo.all(
      from r in CareRecommendation,
        group_by: r.urgency_level,
        select: {r.urgency_level, count(r.id)}
    )
    |> Map.new()
  end
end
