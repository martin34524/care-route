defmodule CareRoute.Geocoder do
  @moduledoc """
  Finds a place in Kenya by name, for patients who don't share their location.

  Uses OpenStreetMap's Nominatim service: only the typed place name is sent.
  Its usage policy asks for an identifying user agent and light use, so
  results are cached for the life of the app.
  """

  @url "https://nominatim.openstreetmap.org/search"
  @cache :care_route_geocoder

  @doc "Returns `{:ok, %{lat, lng, label}}`, `:not_found`, or `{:error, reason}`."
  def search(query) do
    query = query |> to_string() |> String.trim()

    cond do
      String.length(query) < 2 -> :not_found
      cached = cached(query) -> cached
      true -> query |> fetch() |> cache(query)
    end
  end

  defp fetch(query) do
    Req.new(
      url: @url,
      params: [q: query, countrycodes: "ke", format: "jsonv2", limit: 1],
      headers: [{"user-agent", "CareRoute AI (github.com/martin34524/care-route)"}],
      receive_timeout: 10_000,
      retry: false
    )
    |> Req.merge(Application.get_env(:care_route, :directory_req_options, []))
    |> Req.get()
    |> case do
      {:ok, %Req.Response{status: 200, body: [%{"lat" => lat, "lon" => lng} = place | _]}} ->
        {:ok, %{lat: to_float(lat), lng: to_float(lng), label: label(place, query)}}

      {:ok, %Req.Response{status: 200, body: []}} ->
        :not_found

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  # "Kisumu, Kisumu County, Kenya" -> "Kisumu"
  defp label(%{"display_name" => name}, _query) when is_binary(name),
    do: name |> String.split(",") |> hd() |> String.trim()

  defp label(_place, query), do: query

  defp to_float(value) when is_binary(value), do: String.to_float(value)
  defp to_float(value), do: value / 1

  defp cached(query) do
    ensure_table()

    case :ets.lookup(@cache, String.downcase(query)) do
      [{_key, result}] -> result
      [] -> nil
    end
  end

  # Only definite answers are cached; errors are retried next time.
  defp cache({:error, _} = error, _query), do: error

  defp cache(result, query) do
    ensure_table()
    :ets.insert(@cache, {String.downcase(query), result})
    result
  end

  defp ensure_table do
    if :ets.whereis(@cache) == :undefined do
      :ets.new(@cache, [:named_table, :public, :set, read_concurrency: true])
    end
  rescue
    # Another process created it at the same moment.
    ArgumentError -> :ok
  end
end
