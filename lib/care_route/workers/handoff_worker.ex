defmodule CareRoute.Workers.HandoffWorker do
  @moduledoc """
  Generates the clinician handoff summary for a new referral and stores it,
  which broadcasts `{:referral_updated, referral}` to clinician views.
  """

  use Oban.Worker, queue: :ai, max_attempts: 3

  alias CareRoute.{AI, Intake, Referrals}
  alias CareRoute.AI.HandoffPrompt

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"referral_id" => id}}) do
    referral = Referrals.get_referral!(id)

    cond do
      referral.ai_summary ->
        :ok

      is_nil(referral.conversation_id) ->
        {:cancel, :no_conversation}

      true ->
        conversation = Intake.get_conversation!(referral.conversation_id)

        with {:ok, note} <-
               AI.generate(
                 HandoffPrompt.system(),
                 HandoffPrompt.messages(referral, conversation),
                 HandoffPrompt.tool(),
                 fn -> HandoffPrompt.stub(referral, conversation) end
               ),
             {:ok, _referral} <-
               Referrals.update_referral(referral, %{ai_summary: HandoffPrompt.format(note)}) do
          :ok
        end
    end
  end
end
