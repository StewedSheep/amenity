defmodule Amenity.Repo do
  use Ecto.Repo,
    otp_app: :amenity,
    adapter: Ecto.Adapters.Postgres
end
