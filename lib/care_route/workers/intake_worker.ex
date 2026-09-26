defmodule CareRoute.Workers.IntakeWorker do
  @moduledoc """
  Runs the intake extraction call for the latest patient message and hands the
  structured result to `CareRoute.Routing`.
  """

  use Oban.Worker, queue: :ai, max_attempts: 3

  alias CareRoute.{AI, Intake, Routing}
  alias CareRoute.AI.{IntakePrompt, IntakeStub}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"conversation_id" => id}}) do
    conversation = Intake.get_conversation!(id)

    # A later job may already have moved the conversation on.
    if conversation.status == :gathering do
      with {:ok, result} <- extract(conversation),
           {:ok, _conversation} <- Routing.apply_extraction(conversation, result) do
        :ok
      end
    else
      :ok
    end
  end

  defp extract(%{transcript: transcript, patient: patient}) do
    AI.generate(
      IntakePrompt.system(patient.preferred_language),
      IntakePrompt.messages(transcript),
      IntakePrompt.tool(),
      fn -> IntakeStub.extract(transcript) end
    )
  end
end
