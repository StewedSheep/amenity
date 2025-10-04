defmodule Amenity.Trivia.RoomParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  schema "trivia_room_participants" do
    field :score, :integer, default: 0
    field :joined_at, :utc_datetime
    field :is_ready, :boolean, default: false

    belongs_to :room, Amenity.Trivia.Room
    belongs_to :user, Amenity.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:score, :joined_at, :room_id, :user_id, :is_ready])
    |> validate_required([:room_id, :user_id])
    |> unique_constraint([:room_id, :user_id])
  end
end
