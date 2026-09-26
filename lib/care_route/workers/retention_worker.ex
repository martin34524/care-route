defmodule CareRoute.Workers.RetentionWorker do
  @moduledoc """
  Deletes patients older than the retention period, along with their
  conversations, symptom reports, recommendations and referrals (which
  cascade from the patient). Runs daily via Oban's cron plugin.

      config :care_route, :retention_days, 30
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias CareRoute.Intake.Patient
  alias CareRoute.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    days = Application.fetch_env!(:care_route, :retention_days)
    cutoff = DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60)

    {count, _} = Repo.delete_all(from p in Patient, where: p.inserted_at < ^cutoff)
    if count > 0, do: Logger.info("Retention: deleted #{count} patients older than #{days} days")
    :ok
  end
end
