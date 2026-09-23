defmodule CareRoute.Intake.Patient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "patients" do
    field :name, :string
    field :age, :integer
    field :contact, :string
    field :preferred_language, :string, default: "en"

    has_many :conversations, CareRoute.Intake.Conversation

    timestamps(type: :utc_datetime)
  end

  def changeset(patient, attrs) do
    patient
    |> cast(attrs, [:name, :age, :contact, :preferred_language])
    |> validate_number(:age, greater_than_or_equal_to: 0, less_than: 130)
  end
end
