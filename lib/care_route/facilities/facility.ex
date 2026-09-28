defmodule CareRoute.Facilities.Facility do
  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(clinic hospital specialist)a

  @fields ~w(name type distance_km services latitude longitude address source source_id partner
             county phone level emergency opening_hours)a

  def types, do: @types

  schema "facilities" do
    field :name, :string
    field :type, Ecto.Enum, values: @types
    field :distance_km, :float
    field :services, {:array, :string}, default: []
    field :latitude, :float
    field :longitude, :float
    field :address, :string
    field :source, :string, default: "seed"
    field :source_id, :string
    field :partner, :boolean, default: false
    field :county, :string
    field :phone, :string
    field :level, :string
    field :emergency, :boolean, default: false
    field :opening_hours, :string

    has_many :clinicians, CareRoute.Facilities.Clinician

    timestamps(type: :utc_datetime)
  end

  def changeset(facility, attrs) do
    facility
    |> cast(attrs, @fields)
    |> validate_required([:name, :type])
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> unique_constraint([:source, :source_id])
  end
end
