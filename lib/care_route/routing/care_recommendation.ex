defmodule CareRoute.Routing.CareRecommendation do
  use Ecto.Schema
  import Ecto.Changeset

  @urgency_levels ~w(self_care clinic urgent)a

  schema "care_recommendations" do
    field :urgency_level, Ecto.Enum, values: @urgency_levels
    field :reasoning, {:array, :string}, default: []
    field :warning_signs, {:array, :string}, default: []

    belongs_to :conversation, CareRoute.Intake.Conversation

    timestamps(type: :utc_datetime)
  end

  def urgency_levels, do: @urgency_levels

  def changeset(recommendation, attrs) do
    recommendation
    |> cast(attrs, [:conversation_id, :urgency_level, :reasoning, :warning_signs])
    |> validate_required([:conversation_id, :urgency_level])
    |> unique_constraint(:conversation_id)
  end
end
