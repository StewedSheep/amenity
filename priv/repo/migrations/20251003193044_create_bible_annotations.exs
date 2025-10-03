defmodule Amenity.Repo.Migrations.CreateBibleAnnotations do
  use Ecto.Migration

  def change do
    create table(:bible_annotations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :book, :string, null: false
      add :chapter, :integer, null: false
      add :verse, :integer, null: false
      add :content, :text, null: false
      add :note, :text
      add :color, :string, default: "yellow"
      # color options: yellow, blue, green, pink, purple

      timestamps(type: :utc_datetime)
    end

    create index(:bible_annotations, [:user_id])
    create index(:bible_annotations, [:book, :chapter])
    create index(:bible_annotations, [:user_id, :book, :chapter, :verse])
  end
end
