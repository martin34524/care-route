defmodule CareRoute.Intake.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(gathering urgent assessed)a

  schema "conversations" do
    field :status, Ecto.Enum, values: @statuses, default: :gathering
    field :transcript, {:array, :map}, default: []

    belongs_to :patient, CareRoute.Intake.Patient
    has_one :symptom_report, CareRoute.Intake.SymptomReport
    has_one :care_recommendation, CareRoute.Routing.CareRecommendation

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:patient_id, :status, :transcript])
    |> validate_required([:patient_id, :status])
    |> foreign_key_constraint(:patient_id)
  end
end
