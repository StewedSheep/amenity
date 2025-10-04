defmodule Amenity.Repo.Migrations.CreateFlashcards do
  use Ecto.Migration

  def change do
    create table(:flashcard_sets) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :is_public, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create table(:flashcards) do
      add :flashcard_set_id, references(:flashcard_sets, on_delete: :delete_all), null: false
      add :front, :text, null: false
      add :back, :text, null: false
      add :position, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create table(:flashcard_reviews) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :flashcard_id, references(:flashcards, on_delete: :delete_all), null: false
      add :quality, :integer, null: false
      # Quality: 0-5 (Anki style)
      # 0: Complete blackout
      # 1: Incorrect, but remembered
      # 2: Incorrect, but easy to recall
      # 3: Correct, but difficult
      # 4: Correct, with hesitation
      # 5: Perfect recall
      
      add :ease_factor, :float, default: 2.5
      add :interval, :integer, default: 0
      add :repetitions, :integer, default: 0
      add :next_review_date, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:flashcard_sets, [:user_id])
    create index(:flashcards, [:flashcard_set_id])
    create index(:flashcard_reviews, [:user_id, :flashcard_id])
    create index(:flashcard_reviews, [:next_review_date])
  end
end
