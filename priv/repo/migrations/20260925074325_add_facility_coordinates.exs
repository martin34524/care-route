defmodule CareRoute.Repo.Migrations.AddFacilityCoordinates do
  use Ecto.Migration

  def change do
    alter table(:facilities) do
      add :latitude, :float
      add :longitude, :float
      add :address, :string
    end
  end
end
