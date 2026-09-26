defmodule CareRoute.Workers.HandoffWorker do
  @moduledoc """
  Generates the clinician handoff summary for a new referral and stores it,
  which broadcasts `{:referral_updated, referral}` to clinician views.
  """

  use Oban.Worker,
    queue: :ai,
    max_attempts: 3,
    unique: [
      keys: [:referral_id],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias CareRoute.{AI, Intake, Referrals}
  alias CareRoute.AI.HandoffPrompt

  require Logger

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"referral_id" => id}} = job) do
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
             :ok <- HandoffPrompt.validate(note),
             {:ok, _referral} <-
               Referrals.update_referral(referral, %{ai_summary: HandoffPrompt.format(note)}) do
          :ok
        else
          {:error, reason} -> fail(referral, reason, job)
        end
    end
  end

  # After the last attempt, mark the referral so clinicians see "unavailable"
  # with a retry button instead of a spinner that never ends.
  defp fail(referral, reason, %Oban.Job{attempt: attempt, max_attempts: max})
       when attempt >= max do
    Logger.warning("Handoff summary failed for referral #{referral.id}: #{inspect(reason)}")

    {:ok, _} =
      Referrals.update_referral(referral, %{summary_failed_at: DateTime.utc_now(:second)})

    {:cancel, reason}
  end

  defp fail(_referral, reason, _job), do: {:error, reason}
end
