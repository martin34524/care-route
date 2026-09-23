defmodule CareRoute.Facilities.Clinician do
  use Ecto.Schema
  import Ecto.Changeset

  schema "clinicians" do
    field :name, :string
    field :role, :string

    belongs_to :facility, CareRoute.Facilities.Facility

    timestamps(type: :utc_datetime)
  end

  def changeset(clinician, attrs) do
    clinician
    |> cast(attrs, [:name, :role, :facility_id])
    |> validate_required([:name])
  end
end
