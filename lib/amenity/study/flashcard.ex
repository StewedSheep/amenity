defmodule Amenity.Study.Flashcard do
  use Ecto.Schema
  import Ecto.Changeset

  schema "flashcards" do
    belongs_to :flashcard_set, Amenity.Study.FlashcardSet
    field :front, :string
    field :back, :string
    field :position, :integer, default: 0

    has_many :reviews, Amenity.Study.FlashcardReview

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(flashcard, attrs) do
    flashcard
    |> cast(attrs, [:flashcard_set_id, :front, :back, :position])
    |> validate_required([:flashcard_set_id, :front, :back])
    |> validate_length(:front, min: 1, max: 5000)
    |> validate_length(:back, min: 1, max: 5000)
  end
end
