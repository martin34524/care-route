defmodule CareRoute.Repo do
  use Ecto.Repo,
    otp_app: :care_route,
    adapter: Ecto.Adapters.Postgres
end
