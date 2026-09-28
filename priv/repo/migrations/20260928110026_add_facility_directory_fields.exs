defmodule CareRoute.Repo.Migrations.AddFacilityDirectoryFields do
  use Ecto.Migration

  # Facilities now come from a real directory (OpenStreetMap, later KMHFL) as
  # well as the demo seeds. Only partner facilities receive referrals.
  def change do
    alter table(:facilities) do
      # "seed", "osm", "kmhfl" or "csv", and the id in that source.
      add :source, :string, null: false, default: "seed"
      add :source_id, :string
      # Uses CareRoute's clinician dashboard, so referrals actually reach it.
      add :partner, :boolean, null: false, default: false
      add :county, :string
      add :phone, :string
      # e.g. a KEPH level ("Level 4") when the source has one.
      add :level, :string
      add :emergency, :boolean, null: false, default: false
      add :opening_hours, :string
    end

    create unique_index(:facilities, [:source, :source_id])
    # Bounding-box prefilter for nearest-facility searches.
    create index(:facilities, [:latitude, :longitude])

    # The seeded demo facilities are the CareRoute partners.
    execute "UPDATE facilities SET partner = true WHERE source = 'seed'", ""
  end
end
