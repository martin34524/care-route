defmodule CareRoute.Repo.Migrations.AddReferralRespondedAt do
  use Ecto.Migration

  def change do
    alter table(:referrals) do
      # When a clinician first acted on the referral; drives "avg. response time".
      add :responded_at, :utc_datetime
    end
  end
end
