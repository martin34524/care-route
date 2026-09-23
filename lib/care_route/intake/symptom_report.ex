defmodule CareRoute.Intake.SymptomReport do
  use Ecto.Schema
  import Ecto.Changeset

  schema "symptom_reports" do
    field :symptoms, {:array, :string}, default: []
    field :duration, :string
    field :severity, :string
    field :red_flags, {:array, :string}, default: []

    belongs_to :conversation, CareRoute.Intake.Conversation

    timestamps(type: :utc_datetime)
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [:conversation_id, :symptoms, :duration, :severity, :red_flags])
    |> validate_required([:conversation_id])
    |> unique_constraint(:conversation_id)
  end
end
