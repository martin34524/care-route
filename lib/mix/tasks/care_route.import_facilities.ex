defmodule Mix.Tasks.CareRoute.ImportFacilities do
  @shortdoc "Imports real health facilities (OpenStreetMap, or a CSV export)"
  @moduledoc """
      mix care_route.import_facilities                       # all of Kenya from OpenStreetMap
      mix care_route.import_facilities --file osm.json       # a saved Overpass response
      mix care_route.import_facilities --csv facilities.csv  # e.g. a KMHFL export

  See `CareRoute.Facilities.Import` for the CSV columns. Safe to re-run.
  In a release: `bin/care_route eval "CareRoute.Release.import_facilities()"`.
  """
  use Mix.Task

  alias CareRoute.Facilities.Import

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [file: :string, csv: :string])

    {:ok, %{imported: imported, removed: removed}} =
      case opts[:csv] do
        nil -> Import.run(:osm, file: opts[:file])
        path -> Import.run_csv(path)
      end

    Mix.shell().info(
      "Imported #{imported} facilities; removed #{removed} no longer in the source."
    )
  end
end
