defmodule Amenity.Repo.Migrations.CreateTriviaRooms do
  use Ecto.Migration

  def change do
    create table(:trivia_rooms) do
      add :name, :string, null: false
      add :host_id, references(:users, on_delete: :delete_all), null: false
      add :book, :string, null: false
      add :num_questions, :integer, null: false
      add :status, :string, default: "waiting", null: false
      add :current_question_index, :integer, default: 0
      add :questions, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:trivia_rooms, [:host_id])
    create index(:trivia_rooms, [:status])
  end
end
