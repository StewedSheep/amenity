defmodule Amenity.Study.FlashcardSet do
  use Ecto.Schema
  import Ecto.Changeset

  schema "flashcard_sets" do
    belongs_to :user, Amenity.Accounts.User
    field :name, :string
    field :description, :string
    field :is_public, :boolean, default: false

    has_many :flashcards, Amenity.Study.Flashcard

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(flashcard_set, attrs) do
    flashcard_set
    |> cast(attrs, [:user_id, :name, :description, :is_public])
    |> validate_required([:user_id, :name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
