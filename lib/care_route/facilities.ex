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

  @earth_radius_km 6371.0
  # A patient further than this from every facility is outside the simulated
  # network, so their real position isn't used for distances.
  @max_origin_km 100

  @doc "The simulated patient position used until the browser shares a real one."
  def demo_origin, do: Application.fetch_env!(:care_route, :demo_origin)

  @doc """
  Recomputes `distance_km` from `origin` (`%{lat: _, lng: _}`) and sorts nearest
  first. Returns `:out_of_area` when the origin is far from every facility.
  """
  def with_distances(facilities, %{lat: lat, lng: lng} = origin)
      when is_number(lat) and is_number(lng) do
    facilities =
      facilities
      |> Enum.map(fn f ->
        if f.latitude, do: %{f | distance_km: Float.round(haversine_km(origin, f), 1)}, else: f
      end)
      |> Enum.sort_by(&(&1.distance_km || :infinity))

    if Enum.any?(facilities, &(&1.distance_km && &1.distance_km <= @max_origin_km)),
      do: {:ok, facilities},
      else: :out_of_area
  end

  defp haversine_km(%{lat: lat1, lng: lng1}, %Facility{latitude: lat2, longitude: lng2}) do
    to_rad = &(&1 * :math.pi() / 180)
    dlat = to_rad.(lat2 - lat1)
    dlng = to_rad.(lng2 - lng1)

    a =
      :math.pow(:math.sin(dlat / 2), 2) +
        :math.cos(to_rad.(lat1)) * :math.cos(to_rad.(lat2)) * :math.pow(:math.sin(dlng / 2), 2)

    2 * @earth_radius_km * :math.asin(:math.sqrt(a))
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
