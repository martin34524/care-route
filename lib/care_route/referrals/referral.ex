defmodule CareRoute.Referrals.Referral do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending accepted completed)a

  schema "referrals" do
    field :reason, :string
    field :ai_summary, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :responded_at, :utc_datetime

    belongs_to :patient, CareRoute.Intake.Patient
    belongs_to :conversation, CareRoute.Intake.Conversation
    belongs_to :from_facility, CareRoute.Facilities.Facility
    belongs_to :to_facility, CareRoute.Facilities.Facility

    timestamps(type: :utc_datetime)
  end

  def changeset(referral, attrs) do
    referral
    |> cast(attrs, [
      :patient_id,
      :conversation_id,
      :from_facility_id,
      :to_facility_id,
      :reason,
      :ai_summary,
      :status,
      :responded_at
    ])
    |> validate_required([:patient_id, :to_facility_id])
    |> foreign_key_constraint(:patient_id)
    |> foreign_key_constraint(:to_facility_id)
  end
end
