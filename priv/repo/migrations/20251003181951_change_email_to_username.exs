defmodule Amenity.Repo.Migrations.ChangeEmailToUsername do
  use Ecto.Migration

  def change do
    # Rename email column to username
    rename table(:users), :email, to: :username

    # Drop the old email index
    drop unique_index(:users, [:email])

    # Create new username index
    create unique_index(:users, [:username])
  end
end
