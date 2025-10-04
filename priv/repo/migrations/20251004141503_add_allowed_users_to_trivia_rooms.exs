defmodule Amenity.Repo.Migrations.AddAllowedUsersToTriviaRooms do
  use Ecto.Migration

  def change do
    alter table(:trivia_rooms) do
      add :allowed_user_ids, {:array, :integer}, default: []
    end
  end
end
