defmodule CareRoute.Facilities.Facility do
  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(clinic hospital specialist)a

  schema "facilities" do
    field :name, :string
    field :type, Ecto.Enum, values: @types
    field :distance_km, :float
    field :services, {:array, :string}, default: []
    field :latitude, :float
    field :longitude, :float
    field :address, :string

    has_many :clinicians, CareRoute.Facilities.Clinician

    timestamps(type: :utc_datetime)
  end

  def changeset(facility, attrs) do
    facility
    |> cast(attrs, [:name, :type, :distance_km, :services, :latitude, :longitude, :address])
    |> validate_required([:name, :type])
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
  end
end
