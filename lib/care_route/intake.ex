defmodule CareRoute.Intake do
  @moduledoc """
  Conversation state for a patient's intake session.

  Each patient message is appended to the transcript and an Oban job is
  enqueued to run the Claude extraction call; the result is applied by
  `CareRoute.Routing` and broadcast on the conversation's topic.
  """

  alias CareRoute.Repo
  alias CareRoute.Intake.{Patient, Conversation, SymptomReport}
  alias CareRoute.Workers.IntakeWorker

  @greeting "Hi, I'm CareRoute. I can help you figure out where to go for care. " <>
              "I'm not a doctor and can't diagnose, but tell me what's going on in your own words."

  def topic(conversation_id), do: "conversation:#{conversation_id}"

  def subscribe(conversation_id) do
    Phoenix.PubSub.subscribe(CareRoute.PubSub, topic(conversation_id))
  end

  def broadcast(%Conversation{id: id} = conversation) do
    Phoenix.PubSub.broadcast(CareRoute.PubSub, topic(id), {:conversation_updated, conversation})
  end

  def create_patient(attrs \\ %{}) do
    %Patient{} |> Patient.changeset(attrs) |> Repo.insert()
  end

  def get_patient!(id), do: Repo.get!(Patient, id)

  @doc "Starts a new conversation for a patient, seeded with the assistant greeting."
  def start_conversation(%Patient{id: patient_id}) do
    %Conversation{}
    |> Conversation.changeset(%{
      patient_id: patient_id,
      transcript: [entry("assistant", @greeting)]
    })
    |> Repo.insert()
  end

  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload([:patient, :symptom_report, :care_recommendation])
  end

  @doc """
  Records a patient message and enqueues the AI extraction job.
  Messages are ignored once the conversation has left the gathering state.
  """
  def submit_patient_message(%Conversation{status: :gathering} = conversation, content) do
    content = String.trim(content)

    with true <- content != "" || {:error, :empty},
         {:ok, conversation} <- append_message(conversation, "patient", content),
         {:ok, _job} <- Oban.insert(IntakeWorker.new(%{conversation_id: conversation.id})) do
      {:ok, conversation}
    end
  end

  def submit_patient_message(%Conversation{}, _content), do: {:error, :conversation_closed}

  def append_message(%Conversation{} = conversation, role, content) do
    conversation
    |> Conversation.changeset(%{transcript: conversation.transcript ++ [entry(role, content)]})
    |> Repo.update()
    |> tap_broadcast()
  end

  def update_status(%Conversation{} = conversation, status) do
    conversation
    |> Conversation.changeset(%{status: status})
    |> Repo.update()
    |> tap_broadcast()
  end

  @doc "Creates or replaces the structured symptom report for a conversation."
  def upsert_symptom_report(%Conversation{id: conversation_id}, attrs) do
    %SymptomReport{}
    |> SymptomReport.changeset(Map.put(attrs, :conversation_id, conversation_id))
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :conversation_id, :inserted_at]},
      conflict_target: :conversation_id
    )
  end

  defp entry(role, content) do
    %{"role" => role, "content" => content, "at" => DateTime.utc_now() |> DateTime.to_iso8601()}
  end

  defp tap_broadcast({:ok, conversation} = result) do
    broadcast(conversation)
    result
  end

  defp tap_broadcast(error), do: error
end
