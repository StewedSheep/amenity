defmodule Amenity.Repo.Migrations.CreateChapterReads do
  use Ecto.Migration

  def change do
    create table(:chapter_reads) do
      add :book, :string, null: false
      add :chapter, :integer, null: false
      add :last_read, {:array, :utc_datetime}, default: []
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:chapter_reads, [:user_id])
    create unique_index(:chapter_reads, [:user_id, :book, :chapter])
  end
end
