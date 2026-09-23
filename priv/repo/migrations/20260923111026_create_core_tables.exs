defmodule CareRoute.Repo.Migrations.CreateCoreTables do
  use Ecto.Migration

  def change do
    create table(:facilities) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :distance_km, :float
      add :services, {:array, :string}, default: [], null: false

      timestamps(type: :utc_datetime)
    end

    create table(:clinicians) do
      add :name, :string, null: false
      add :role, :string
      add :facility_id, references(:facilities, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:clinicians, [:facility_id])

    create table(:patients) do
      add :name, :string
      add :age, :integer
      add :contact, :string
      add :preferred_language, :string, default: "en", null: false

      timestamps(type: :utc_datetime)
    end

    create table(:conversations) do
      add :patient_id, references(:patients, on_delete: :delete_all), null: false
      add :status, :string, default: "gathering", null: false
      # List of %{"role" => "patient" | "assistant", "content" => ..., "at" => ...}
      add :transcript, {:array, :map}, default: [], null: false

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:patient_id])

    create table(:symptom_reports) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :symptoms, {:array, :string}, default: [], null: false
      add :duration, :string
      add :severity, :string
      add :red_flags, {:array, :string}, default: [], null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:symptom_reports, [:conversation_id])

    create table(:care_recommendations) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :urgency_level, :string, null: false
      add :reasoning, {:array, :string}, default: [], null: false
      add :warning_signs, {:array, :string}, default: [], null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:care_recommendations, [:conversation_id])

    create table(:referrals) do
      add :patient_id, references(:patients, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, on_delete: :nilify_all)
      add :from_facility_id, references(:facilities, on_delete: :nilify_all)
      add :to_facility_id, references(:facilities, on_delete: :nilify_all), null: false
      add :reason, :text
      add :ai_summary, :text
      add :status, :string, default: "pending", null: false

      timestamps(type: :utc_datetime)
    end

    create index(:referrals, [:patient_id])
    create index(:referrals, [:to_facility_id, :status])
  end
end
