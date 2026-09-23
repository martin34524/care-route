defmodule CareRoute.Routing do
  @moduledoc """
  Deterministic state machine over the AI extraction result.

  The Claude call only extracts structure; this module decides what happens
  next by branching on `next_action`, never by re-reading free text:

    * `"ask_question"`             -> stay in `:gathering`, post the next question
    * `"escalate_urgent"`          -> short-circuit to `:urgent`
    * `"ready_for_recommendation"` -> move to `:assessed`, store the recommendation
  """

  alias CareRoute.{Intake, Repo}
  alias CareRoute.Intake.Conversation
  alias CareRoute.Routing.CareRecommendation

  @urgent_message "Based on what you've shared, please seek urgent care now. " <>
                    "If this is an emergency, call your local emergency number."

  def apply_extraction(%Conversation{} = conversation, %{"extracted" => extracted} = result) do
    {:ok, _report} =
      Intake.upsert_symptom_report(conversation, %{
        symptoms: Map.get(extracted, "symptoms", []),
        duration: Map.get(extracted, "duration"),
        severity: Map.get(extracted, "severity"),
        red_flags: Map.get(extracted, "red_flags", [])
      })

    red_flag? = result["urgency_signal"] == true or extracted["red_flags"] not in [nil, []]

    case {red_flag?, result["next_action"]} do
      {true, _} ->
        escalate(conversation, result)

      {_, "escalate_urgent"} ->
        escalate(conversation, result)

      {_, "ready_for_recommendation"} ->
        recommend(conversation, result)

      {_, "ask_question"} ->
        Intake.append_message(conversation, "assistant", result["next_question"])
    end
  end

  defp escalate(conversation, result) do
    with {:ok, _rec} <-
           create_recommendation(conversation, %{
             urgency_level: :urgent,
             reasoning: Map.get(result, "reasoning", []),
             warning_signs: get_in(result, ["extracted", "red_flags"]) || []
           }),
         {:ok, conversation} <- Intake.append_message(conversation, "assistant", @urgent_message) do
      Intake.update_status(conversation, :urgent)
    end
  end

  defp recommend(conversation, result) do
    rec = Map.get(result, "recommendation", %{})

    with {:ok, _rec} <-
           create_recommendation(conversation, %{
             urgency_level: rec["urgency_level"] || "clinic",
             reasoning: rec["reasoning"] || [],
             warning_signs: rec["warning_signs"] || []
           }),
         {:ok, conversation} <-
           Intake.append_message(
             conversation,
             "assistant",
             "Thanks, I have enough to suggest a next step."
           ) do
      Intake.update_status(conversation, :assessed)
    end
  end

  def create_recommendation(%Conversation{id: conversation_id}, attrs) do
    %CareRecommendation{}
    |> CareRecommendation.changeset(Map.put(attrs, :conversation_id, conversation_id))
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :conversation_id, :inserted_at]},
      conflict_target: :conversation_id
    )
  end
end
