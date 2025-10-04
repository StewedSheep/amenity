defmodule Amenity.Bible.ChapterRead do
  use Ecto.Schema
  import Ecto.Changeset

  schema "chapter_reads" do
    field :book, :string
    field :chapter, :integer
    field :last_read, {:array, :utc_datetime}, default: []
    belongs_to :user, Amenity.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chapter_read, attrs) do
    chapter_read
    |> cast(attrs, [:book, :chapter, :last_read, :user_id])
    |> validate_required([:book, :chapter, :user_id])
    |> validate_number(:chapter, greater_than: 0)
    |> unique_constraint([:user_id, :book, :chapter])
  end

  @doc """
  Adds a new timestamp to the last_read array
  """
  def mark_as_read(chapter_read) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    updated_reads = [now | chapter_read.last_read]

    change(chapter_read, last_read: updated_reads)
  end
end
