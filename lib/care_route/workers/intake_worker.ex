defmodule CareRoute.Workers.IntakeWorker do
  @moduledoc """
  Runs the intake extraction call for the latest patient message and hands the
  structured result to `CareRoute.Routing`.
  """

  use Oban.Worker, queue: :ai, max_attempts: 3

  alias CareRoute.{Intake, Routing}
  alias CareRoute.AI.{Claude, Gemini, IntakePrompt, IntakeStub}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"conversation_id" => id}}) do
    conversation = Intake.get_conversation!(id)

    # A later job may already have moved the conversation on.
    if conversation.status == :gathering do
      with {:ok, result} <- extract(conversation.transcript),
           {:ok, _conversation} <- Routing.apply_extraction(conversation, result) do
        :ok
      end
    else
      :ok
    end
  end

  # Provider order: Gemini, then Claude, then the offline stub.
  defp extract(transcript) do
    system = IntakePrompt.system()
    messages = IntakePrompt.messages(transcript)

    cond do
      Gemini.configured?() ->
        Gemini.generate_json(system, messages, IntakePrompt.tool()["input_schema"])

      Claude.configured?() ->
        Claude.call_tool(system, messages, IntakePrompt.tool())

      true ->
        {:ok, IntakeStub.extract(transcript)}
    end
  end
end
