defmodule Amenity.Repo.Migrations.CreateTriviaGameStats do
  use Ecto.Migration

  def change do
    create table(:trivia_game_stats) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :room_id, references(:trivia_rooms, on_delete: :delete_all), null: false
      add :correct_answers, :integer, default: 0, null: false
      add :incorrect_answers, :integer, default: 0, null: false
      add :total_score, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:trivia_game_stats, [:user_id])
    create index(:trivia_game_stats, [:room_id])
  end
end
