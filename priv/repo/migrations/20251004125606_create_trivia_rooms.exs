defmodule Amenity.Repo.Migrations.CreateTriviaRooms do
  use Ecto.Migration

  def change do
    create table(:trivia_rooms) do
      add :name, :string, null: false
      add :description, :text
      add :difficulty, :string, default: "medium"
      add :max_players, :integer, default: 10
      add :status, :string, default: "waiting"
      add :host_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:trivia_rooms, [:host_id])
    create index(:trivia_rooms, [:status])

    create table(:trivia_room_participants) do
      add :room_id, references(:trivia_rooms, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :score, :integer, default: 0
      add :joined_at, :utc_datetime

      timestamps()
    end

    create index(:trivia_room_participants, [:room_id])
    create index(:trivia_room_participants, [:user_id])
    create unique_index(:trivia_room_participants, [:room_id, :user_id])
  end
end
