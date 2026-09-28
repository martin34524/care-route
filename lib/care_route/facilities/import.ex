defmodule CareRoute.Facilities.Import do
  @moduledoc """
  Loads the real facility directory into `facilities`.

    * `:osm` — every hospital, clinic and health centre in Kenya from
      OpenStreetMap (Overpass API). Data © OpenStreetMap contributors, ODbL:
      credit it wherever facilities are shown.
    * `:csv` — any export with these header columns (e.g. a Kenya Master Health
      Facility List export, renamed to match): `source_id, name, type,
      latitude, longitude` and optionally `county, phone, level, emergency,
      opening_hours, address, services` (`;`-separated). `type` is
      hospital, clinic or specialist; `emergency` is yes/true/1.

  Imports upsert by `{source, source_id}`, so re-running refreshes them.
  Facilities that disappeared from the source are deleted unless a referral
  points at them. Imported facilities are never partners.
  """

  import Ecto.Query

  alias CareRoute.Repo
  alias CareRoute.Facilities.Facility
  alias CareRoute.Referrals.Referral

  NimbleCSV.define(__MODULE__.CSV, separator: ",", escape: "\"")

  # Public Overpass servers; the next one is tried when one is busy.
  @overpass_urls [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter"
  ]
  @osm_query """
  [out:json][timeout:180];
  area["ISO3166-1"="KE"][admin_level=2]->.ke;
  (
    nwr["amenity"~"^(hospital|clinic|doctors)$"](area.ke);
    nwr["healthcare"~"^(hospital|clinic|centre)$"](area.ke);
  );
  out center tags;
  """

  @upsert_fields ~w(name type latitude longitude address county phone level emergency
                    opening_hours services updated_at)a

  @doc "Fetches and imports a source. Returns `{:ok, %{imported: n, removed: n}}`."
  def run(:osm, opts \\ []) do
    json =
      case opts[:file] do
        nil -> fetch_osm!()
        path -> path |> File.read!() |> Jason.decode!()
      end

    json |> parse_osm() |> upsert("osm")
  end

  def run_csv(path), do: path |> parse_csv() |> upsert("csv")

  ## OpenStreetMap

  def fetch_osm!(urls \\ @overpass_urls) do
    Enum.reduce_while(urls, [], fn url, errors ->
      case fetch_overpass(url) do
        {:ok, body} -> {:halt, body}
        {:error, reason} -> {:cont, ["#{url}: #{reason}" | errors]}
      end
    end)
    |> case do
      %{} = body ->
        body

      errors ->
        raise "Couldn't download facilities from OpenStreetMap:\n" <>
                Enum.join(Enum.reverse(errors), "\n")
    end
  end

  defp fetch_overpass(url) do
    Req.new(
      url: url,
      # Overpass asks clients to identify themselves.
      headers: [{"user-agent", "CareRoute AI (github.com/martin34524/care-route)"}],
      receive_timeout: 240_000,
      retry: :transient,
      max_retries: 2
    )
    |> Req.merge(Application.get_env(:care_route, :directory_req_options, []))
    |> Req.post(form: [data: @osm_query])
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"elements" => _} = body}} ->
        {:ok, body}

      # A busy server can answer 200 with an HTML error page.
      {:ok, %Req.Response{status: status, body: body}} when is_binary(body) ->
        {:error, "status #{status}, " <> overpass_error(body)}

      {:ok, %Req.Response{status: status}} ->
        {:error, "status #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp overpass_error(body) do
    case Regex.run(~r/Error: ([^<]+)/, body) do
      [_, message] -> String.slice(String.trim(message), 0, 200)
      nil -> "unexpected response"
    end
  end

  @doc "Turns an Overpass JSON response into facility attributes, skipping unnamed places."
  def parse_osm(%{"elements" => elements}) do
    elements
    |> Enum.map(&osm_element/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.source_id)
    |> merge_duplicates()
  end

  # The same place is often mapped twice (a point and a building outline):
  # the same name within a kilometre counts as one facility, keeping the entry
  # with the most details. Same-name branches further apart are kept.
  defp merge_duplicates(rows) do
    rows
    |> Enum.group_by(&String.downcase(&1.name))
    |> Enum.flat_map(fn {_name, same_name} ->
      same_name
      |> Enum.sort_by(&detail_score/1, :desc)
      |> Enum.reduce([], fn row, kept ->
        if Enum.any?(kept, &(km_between(&1, row) < 1.0)), do: kept, else: [row | kept]
      end)
    end)
  end

  defp detail_score(row) do
    Enum.count(
      [row.phone, row.address, row.opening_hours, row.emergency || nil, row.county],
      & &1
    )
  end

  defp km_between(a, b) do
    rad = &(&1 * :math.pi() / 180)
    dlat = rad.(b.latitude - a.latitude)
    dlng = rad.(b.longitude - a.longitude)

    h =
      :math.pow(:math.sin(dlat / 2), 2) +
        :math.cos(rad.(a.latitude)) * :math.cos(rad.(b.latitude)) *
          :math.pow(:math.sin(dlng / 2), 2)

    2 * 6371 * :math.asin(:math.sqrt(h))
  end

  defp osm_element(%{"type" => kind, "id" => id, "tags" => tags} = el) do
    {lat, lng} = coords(el)
    name = tags["name"] || tags["name:en"]

    if name && lat && lng do
      %{
        source_id: "#{kind}/#{id}",
        name: name |> String.trim() |> tidy_name() |> String.slice(0, 255),
        type: osm_type(name, tags),
        latitude: lat,
        longitude: lng,
        address: osm_address(tags),
        county: tags |> first_tag(["addr:county", "is_in:county"]) |> strip_county(),
        phone: tags |> first_tag(["phone", "contact:phone"]) |> first_value(),
        level: nil,
        emergency: tags["emergency"] == "yes",
        opening_hours: tags["opening_hours"],
        services: tags |> Map.get("healthcare:speciality", "") |> split_list()
      }
    end
  end

  defp osm_element(_element), do: nil

  defp coords(%{"lat" => lat, "lon" => lng}), do: {lat, lng}
  defp coords(%{"center" => %{"lat" => lat, "lon" => lng}}), do: {lat, lng}
  defp coords(_element), do: {nil, nil}

  # Many small facilities are tagged as hospitals in OpenStreetMap. Urgent
  # patients are only sent to hospitals, so trust the name over the tag.
  @small_facility ~r/\b(dispensary|health\s*cent(re|er)|clinic|medical\s*cent(re|er)|maternity|nursing\s*home)\b/i

  defp osm_type(name, tags) do
    hospital_tag? = tags["amenity"] == "hospital" or tags["healthcare"] == "hospital"
    small? = Regex.match?(@small_facility, name)

    # "X Hospital" is a hospital whatever the tag; "X Hospital Clinic" or a
    # dispensary tagged as a hospital is not.
    if (hospital_tag? or name =~ ~r/hospital/i) and not small?, do: :hospital, else: :clinic
  end

  # "jeddah hospital" -> "Jeddah Hospital"; names with any capitals are kept as written.
  defp tidy_name(name) do
    if name == String.downcase(name),
      do: name |> String.split(" ") |> Enum.map_join(" ", &String.capitalize/1),
      else: name
  end

  defp osm_address(tags) do
    case tags["addr:full"] do
      nil ->
        [tags["addr:street"], tags["addr:city"] || tags["addr:place"] || tags["is_in:town"]]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> case do
          [] -> nil
          parts -> Enum.join(parts, ", ")
        end

      full ->
        full
    end
  end

  defp first_tag(tags, keys), do: Enum.find_value(keys, &tags[&1])

  defp first_value(nil), do: nil
  defp first_value(value), do: value |> String.split(";") |> hd() |> String.trim()

  defp strip_county(nil), do: nil
  defp strip_county(county), do: county |> String.replace(~r/\s+County$/i, "") |> String.trim()

  defp split_list(value) do
    value
    |> String.split(";")
    |> Enum.map(&(&1 |> String.trim() |> String.replace("_", " ")))
    |> Enum.reject(&(&1 in ["", "general"]))
  end

  ## CSV

  @doc "Parses a CSV export (see the moduledoc for the columns)."
  def parse_csv(path) do
    [header | rows] = path |> File.read!() |> __MODULE__.CSV.parse_string(skip_headers: false)
    header = Enum.map(header, &(&1 |> String.trim() |> String.downcase()))

    for row <- rows, row = Map.new(Enum.zip(header, row)), row["name"] not in [nil, ""] do
      %{
        source_id: row["source_id"],
        name: row["name"],
        type: csv_type(row["type"]),
        latitude: to_float(row["latitude"]),
        longitude: to_float(row["longitude"]),
        address: blank(row["address"]),
        county: blank(row["county"]),
        phone: blank(row["phone"]),
        level: blank(row["level"]),
        emergency: String.downcase(row["emergency"] || "") in ~w(yes true 1),
        opening_hours: blank(row["opening_hours"]),
        services: split_list(row["services"] || "")
      }
    end
    |> Enum.reject(&(is_nil(&1.latitude) or is_nil(&1.longitude) or &1.source_id in [nil, ""]))
  end

  defp csv_type(type) do
    case String.downcase(type || "") do
      "hospital" -> :hospital
      "specialist" -> :specialist
      _ -> :clinic
    end
  end

  defp to_float(value) do
    case Float.parse(String.trim(value || "")) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value), do: String.trim(value)

  ## Storing

  defp upsert(rows, source) do
    now = DateTime.utc_now(:second)

    entries =
      Enum.map(rows, fn row ->
        Map.merge(row, %{source: source, partner: false, inserted_at: now, updated_at: now})
      end)

    Repo.transaction(
      fn ->
        entries
        |> Enum.chunk_every(1_000)
        |> Enum.each(fn chunk ->
          Repo.insert_all(Facility, chunk,
            on_conflict: {:replace, @upsert_fields},
            conflict_target: [:source, :source_id]
          )
        end)

        # Gone from the source: delete, unless a referral points at it.
        ids = Enum.map(entries, & &1.source_id)
        referenced = from(r in Referral, select: r.to_facility_id)

        {removed, _} =
          Repo.delete_all(
            from f in Facility,
              where: f.source == ^source and f.source_id not in ^ids,
              where: f.id not in subquery(referenced)
          )

        %{imported: length(entries), removed: removed}
      end,
      timeout: :infinity
    )
  end
end
