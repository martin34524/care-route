defmodule CareRoute.Intake.Patient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "patients" do
    field :name, :string
    field :age, :integer
    field :contact, :string
    field :preferred_language, :string, default: "en"
    field :consented_at, :utc_datetime

    has_many :conversations, CareRoute.Intake.Conversation

    timestamps(type: :utc_datetime)
  end

  def changeset(patient, attrs) do
    patient
    |> cast(attrs, [:name, :age, :contact, :preferred_language, :consented_at])
    |> validate_length(:name, max: 80)
    |> update_change(:contact, &String.trim/1)
    |> validate_format(:contact, ~r/^\+?[0-9][0-9 \-]{5,18}[0-9]$/)
    |> validate_change(:contact, fn :contact, value ->
      digits = value |> String.replace(~r/\D/, "") |> String.length()
      if digits in 7..15, do: [], else: [contact: "must have 7 to 15 digits"]
    end)
    |> validate_number(:age, greater_than_or_equal_to: 0, less_than: 130)
    |> validate_inclusion(:preferred_language, Map.keys(CareRoute.Intake.Phrases.languages()))
  end
end
