defmodule CareRoute.Facilities do
  @moduledoc """
  Simulated facility directory and the clinicians who work there.
  """

  import Ecto.Query
  alias CareRoute.Repo
  alias CareRoute.Facilities.{Facility, Clinician}

  def list_facilities do
    Repo.all(from f in Facility, order_by: [asc: f.distance_km])
  end

  @doc "Facilities able to handle a given urgency level, nearest first."
  def list_facilities_for(:urgent), do: by_types([:hospital])
  def list_facilities_for(:clinic), do: by_types([:clinic, :specialist])
  def list_facilities_for(_), do: by_types([:clinic])

  defp by_types(types) do
    Repo.all(from f in Facility, where: f.type in ^types, order_by: [asc: f.distance_km])
  end

  def get_facility!(id), do: Repo.get!(Facility, id)

  def create_facility(attrs) do
    %Facility{} |> Facility.changeset(attrs) |> Repo.insert()
  end

  def list_clinicians, do: Repo.all(Clinician) |> Repo.preload(:facility)

  def get_clinician!(id), do: Repo.get!(Clinician, id) |> Repo.preload(:facility)

  def create_clinician(attrs) do
    %Clinician{} |> Clinician.changeset(attrs) |> Repo.insert()
  end
end
