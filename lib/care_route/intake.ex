defmodule CareRoute.Intake do
  @moduledoc """
  Conversation state for a patient's intake session.

  Each patient message is appended to the transcript and an Oban job is
  enqueued to run the Claude extraction call; the result is applied by
  `CareRoute.Routing` and broadcast on the conversation's topic.
  """

  alias CareRoute.Repo
  alias CareRoute.Intake.{Patient, Conversation, Phrases, SymptomReport}
  alias CareRoute.Workers.IntakeWorker

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

  @doc "Starts a new conversation for a patient, seeded with a greeting in their language."
  def start_conversation(%Patient{id: patient_id, preferred_language: language}) do
    %Conversation{}
    |> Conversation.changeset(%{
      patient_id: patient_id,
      transcript: [entry("assistant", Phrases.t(:greeting, language))]
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

  Pass `via: :voice` for answers transcribed from speech; the transcript
  keeps that so clinicians know the text came from speech recognition.
  """
  def submit_patient_message(conversation, content, opts \\ [])

  def submit_patient_message(%Conversation{status: :gathering} = conversation, content, opts) do
    content = String.trim(content)
    extra = if opts[:via] == :voice, do: %{"via" => "voice"}, else: %{}

    with true <- content != "" || {:error, :empty},
         {:ok, conversation} <- append_message(conversation, "patient", content, extra),
         {:ok, _job} <- Oban.insert(IntakeWorker.new(%{conversation_id: conversation.id})) do
      {:ok, conversation}
    end
  end

  def submit_patient_message(%Conversation{}, _content, _opts),
    do: {:error, :conversation_closed}

  def append_message(%Conversation{} = conversation, role, content, extra \\ %{}) do
    entry = Map.merge(entry(role, content), extra)

    conversation
    |> Conversation.changeset(%{transcript: conversation.transcript ++ [entry]})
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

  @doc "Conversation counts keyed by status, e.g. `%{gathering: 2, urgent: 1}`."
  def count_conversations_by_status do
    import Ecto.Query

    Repo.all(from c in Conversation, group_by: c.status, select: {c.status, count(c.id)})
    |> Map.new()
  end
end
