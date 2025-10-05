defmodule Amenity.Repo.Migrations.AddProfilePictureUrlToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :profile_picture_url, :string
    end
  end
end
