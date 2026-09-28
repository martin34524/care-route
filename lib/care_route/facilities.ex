defmodule CareRoute.Facilities do
  @moduledoc """
  The facility directory (real facilities imported from OpenStreetMap or a CSV
  export, plus the demo partner facilities) and the clinicians who work there.
  """

  import Ecto.Query
  alias CareRoute.Repo
  alias CareRoute.Facilities.{Facility, Clinician}

  def list_facilities do
    Repo.all(from f in Facility, order_by: [asc: f.name])
  end

  @doc "Facilities that use CareRoute's clinician dashboard, so referrals reach them."
  def list_partners do
    Repo.all(from f in Facility, where: f.partner, order_by: [asc: f.name])
  end

  @doc "The kinds of facility suited to a recommended level of care."
  def types_for(:urgent), do: [:hospital]
  # Hospital outpatient departments also see non-urgent patients.
  def types_for(_level), do: [:clinic, :specialist, :hospital]

  @doc "The simulated patient position used until the browser shares a real one."
  def demo_origin, do: Application.fetch_env!(:care_route, :demo_origin)

  # Search radii (km): start close and widen until there are enough results,
  # so rural patients still get options. Kenya is about 1,000 km across.
  @radii [10, 25, 50, 100, 250, 600]
  @min_results 3

  @doc """
  The nearest facilities of `types` to `origin` (`%{lat: _, lng: _}`), nearest
  first, with `distance_km` filled in. Returns `:out_of_area` when nothing is
  within #{List.last(@radii)} km (e.g. the patient isn't in Kenya).

  Options: `:limit` (default 10); `:partners_within_km` also includes partner
  facilities that close even when more than `limit` places are nearer, so a
  patient in a dense city still sees the ones that can receive a referral.
  """
  def nearest(%{lat: lat, lng: lng}, types, opts \\ []) when is_number(lat) and is_number(lng) do
    limit = Keyword.get(opts, :limit, 10)

    Enum.find_value(@radii, :out_of_area, fn radius ->
      found = within(lat, lng, types, radius, limit)

      cond do
        length(found) >= min(@min_results, limit) -> {:ok, found}
        radius == List.last(@radii) and found != [] -> {:ok, found}
        true -> nil
      end
    end)
    |> with_partners(lat, lng, types, opts[:partners_within_km])
  end

  defp with_partners({:ok, found}, lat, lng, types, radius_km) when is_number(radius_km) do
    partners =
      lat
      |> within(lng, types, radius_km, 50, partners_only: true)
      |> Enum.reject(fn p -> Enum.any?(found, &(&1.id == p.id)) end)

    {:ok, Enum.sort_by(found ++ partners, & &1.distance_km)}
  end

  defp with_partners(result, _lat, _lng, _types, _radius_km), do: result

  defp within(lat, lng, types, radius_km, limit, opts \\ []) do
    # Bounding box first (uses the latitude/longitude index), then the exact
    # great-circle distance.
    dlat = radius_km / 111.0
    dlng = radius_km / (111.0 * max(:math.cos(lat * :math.pi() / 180), 0.01))

    candidates =
      from f in Facility,
        where: f.type in ^types,
        where: f.partner or not (^Keyword.get(opts, :partners_only, false)),
        where: f.latitude >= ^(lat - dlat) and f.latitude <= ^(lat + dlat),
        where: f.longitude >= ^(lng - dlng) and f.longitude <= ^(lng + dlng),
        select: %{
          id: f.id,
          distance:
            fragment(
              "2 * 6371 * asin(sqrt(power(sin(radians(? - ?) / 2), 2) + cos(radians(?)) * cos(radians(?)) * power(sin(radians(? - ?) / 2), 2)))",
              f.latitude,
              type(^lat, :float),
              type(^lat, :float),
              f.latitude,
              f.longitude,
              type(^lng, :float)
            )
        }

    from(f in Facility,
      join: c in subquery(candidates),
      on: c.id == f.id,
      where: c.distance <= ^radius_km,
      order_by: [asc: c.distance, asc: f.id],
      limit: ^limit,
      select: {f, c.distance}
    )
    |> Repo.all()
    |> Enum.map(fn {f, distance} -> %{f | distance_km: Float.round(distance, 1)} end)
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
