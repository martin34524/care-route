defmodule CareRoute.Facilities.Facility do
  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(clinic hospital specialist)a

  schema "facilities" do
    field :name, :string
    field :type, Ecto.Enum, values: @types
    field :distance_km, :float
    field :services, {:array, :string}, default: []

    has_many :clinicians, CareRoute.Facilities.Clinician

    timestamps(type: :utc_datetime)
  end

  def changeset(facility, attrs) do
    facility
    |> cast(attrs, [:name, :type, :distance_km, :services])
    |> validate_required([:name, :type])
  end
end
