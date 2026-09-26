defmodule CareRoute.Repo.Migrations.AddPatientConsentedAt do
  use Ecto.Migration

  def change do
    alter table(:patients) do
      # When the patient accepted the start screen's consent notice.
      add :consented_at, :utc_datetime
    end
  end
end
