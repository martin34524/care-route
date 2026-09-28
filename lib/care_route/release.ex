defmodule CareRoute.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :care_route

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Seeds the facility directory and clinicians (safe to re-run; it updates by name):

      bin/care_route eval "CareRoute.Release.seed()"
  """
  def seed do
    load_app()
    {:ok, _} = Application.ensure_all_started(:care_route)
    Code.eval_file(Path.join(:code.priv_dir(@app), "repo/seeds.exs"))
    :ok
  end

  @doc """
  Clears all patient data and reseeds facilities, for demo rehearsals on a
  deployed app:

      bin/care_route eval "CareRoute.Release.demo_reset()"
  """
  def demo_reset do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)
    deleted = CareRoute.Demo.reset!()
    IO.puts("Deleted #{CareRoute.Demo.describe(deleted)}. Facilities and clinicians reseeded.")
  end

  @doc """
  Imports every hospital and clinic in Kenya from OpenStreetMap (safe to re-run):

      bin/care_route eval "CareRoute.Release.import_facilities()"
  """
  def import_facilities do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)
    {:ok, result} = CareRoute.Facilities.Import.run(:osm)
    IO.puts("Imported #{result.imported} facilities; removed #{result.removed}.")
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
