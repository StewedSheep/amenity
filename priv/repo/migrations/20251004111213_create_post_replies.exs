defmodule Amenity.Repo.Migrations.CreatePostReplies do
  use Ecto.Migration

  def change do
    create table(:post_replies) do
      add :content, :text, null: false
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :edited_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:post_replies, [:post_id])
    create index(:post_replies, [:user_id])
    create index(:post_replies, [:inserted_at])
  end
end
