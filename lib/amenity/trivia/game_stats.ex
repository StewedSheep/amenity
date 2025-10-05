defmodule Amenity.Trivia.GameStats do
  use Ecto.Schema
  import Ecto.Changeset

  schema "trivia_game_stats" do
    field :correct_answers, :integer, default: 0
    field :incorrect_answers, :integer, default: 0
    field :total_score, :integer, default: 0

    belongs_to :user, Amenity.Accounts.User
    belongs_to :room, Amenity.Trivia.Room

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game_stats, attrs) do
    game_stats
    |> cast(attrs, [:user_id, :room_id, :correct_answers, :incorrect_answers, :total_score])
    |> validate_required([:user_id, :room_id, :correct_answers, :incorrect_answers, :total_score])
    |> validate_number(:correct_answers, greater_than_or_equal_to: 0)
    |> validate_number(:incorrect_answers, greater_than_or_equal_to: 0)
    |> validate_number(:total_score, greater_than_or_equal_to: 0)
  end
end
