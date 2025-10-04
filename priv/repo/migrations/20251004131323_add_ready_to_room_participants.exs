defmodule Amenity.Repo.Migrations.AddReadyToRoomParticipants do
  use Ecto.Migration

  def change do
    alter table(:trivia_room_participants) do
      add :is_ready, :boolean, default: false, null: false
    end
  end
end
