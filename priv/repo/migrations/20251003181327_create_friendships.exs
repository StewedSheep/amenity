defmodule Amenity.Repo.Migrations.CreateFriendships do
  use Ecto.Migration

  def change do
    create table(:friendships) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :friend_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      # status: "pending", "accepted", "rejected", "blocked"

      timestamps(type: :utc_datetime)
    end

    create index(:friendships, [:user_id])
    create index(:friendships, [:friend_id])
    create index(:friendships, [:status])

    # Ensure no duplicate friendships (either direction)
    create unique_index(:friendships, [:user_id, :friend_id])

    # Constraint: user cannot friend themselves
    create constraint(:friendships, :no_self_friendship, check: "user_id != friend_id")
  end
end
