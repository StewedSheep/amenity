defmodule Amenity.Study.FlashcardReview do
  use Ecto.Schema
  import Ecto.Changeset

  schema "flashcard_reviews" do
    belongs_to :user, Amenity.Accounts.User
    belongs_to :flashcard, Amenity.Study.Flashcard
    field :quality, :integer
    field :ease_factor, :float, default: 2.5
    field :interval, :integer, default: 0
    field :repetitions, :integer, default: 0
    field :next_review_date, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(flashcard_review, attrs) do
    flashcard_review
    |> cast(attrs, [:user_id, :flashcard_id, :quality, :ease_factor, :interval, :repetitions, :next_review_date])
    |> validate_required([:user_id, :flashcard_id, :quality])
    |> validate_inclusion(:quality, 0..5)
    |> validate_number(:ease_factor, greater_than_or_equal_to: 1.3)
    |> validate_number(:interval, greater_than_or_equal_to: 0)
    |> validate_number(:repetitions, greater_than_or_equal_to: 0)
  end
end
