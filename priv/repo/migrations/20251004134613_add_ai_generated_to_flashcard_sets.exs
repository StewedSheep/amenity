defmodule Amenity.Repo.Migrations.AddAiGeneratedToFlashcardSets do
  use Ecto.Migration

  def change do
    alter table(:flashcard_sets) do
      add :ai_generated, :boolean, default: false, null: false
    end
  end
end
