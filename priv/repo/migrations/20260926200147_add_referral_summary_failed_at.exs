defmodule CareRoute.Repo.Migrations.AddReferralSummaryFailedAt do
  use Ecto.Migration

  def change do
    alter table(:referrals) do
      # Set when the AI handoff summary gave up, so clinicians can retry it.
      add :summary_failed_at, :utc_datetime
    end
  end
end
