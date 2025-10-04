defmodule Amenity.Repo.Migrations.AddBookAndQuestionCountToTriviaRooms do
  use Ecto.Migration

  def change do
    alter table(:trivia_rooms) do
      add :book_of_moses, :string, default: "Genesis"
      add :question_count, :integer, default: 5
    end
  end
end
