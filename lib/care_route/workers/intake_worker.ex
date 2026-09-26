defmodule CareRoute.Workers.IntakeWorker do
  @moduledoc """
  Runs the intake extraction call for the latest patient message and hands the
  structured result to `CareRoute.Routing`.
  """

  use Oban.Worker,
    queue: :ai,
    max_attempts: 3,
    # One pending AI call per conversation, so two can't race on the transcript.
    unique: [
      keys: [:conversation_id],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias CareRoute.{AI, Intake, Routing}
  alias CareRoute.AI.{IntakePrompt, IntakeStub}
  alias CareRoute.Intake.Phrases

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"conversation_id" => id}} = job) do
    conversation = Intake.get_conversation!(id)

    # A later job may already have moved the conversation on.
    if conversation.status == :gathering do
      with {:ok, result} <- extract(conversation),
           {:ok, _conversation} <- Routing.apply_extraction(conversation, result) do
        :ok
      else
        {:error, reason} -> fail(conversation, reason, job)
      end
    else
      :ok
    end
  end

  # The patient is waiting, so retry quickly: 3s, then 6s.
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 3

  defp fail(conversation, reason, %Oban.Job{attempt: attempt, max_attempts: max})
       when attempt >= max do
    Logger.warning("Intake AI failed for conversation #{conversation.id}: #{inspect(reason)}")
    notice = Phrases.t(:ai_unavailable, conversation.patient.preferred_language)
    {:ok, _} = Intake.post_notice(conversation, notice)
    {:cancel, reason}
  end

  defp fail(_conversation, reason, _job), do: {:error, reason}

  defp extract(%{transcript: transcript, patient: patient} = conversation) do
    final = Routing.question_limit_reached?(conversation)

    AI.generate(
      IntakePrompt.system(patient.preferred_language, final: final),
      IntakePrompt.messages(transcript),
      IntakePrompt.tool(),
      fn -> IntakeStub.extract(transcript) end
    )
  end
end
