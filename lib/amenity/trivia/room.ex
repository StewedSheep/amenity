defmodule Amenity.Trivia.Room do
  use Ecto.Schema
  import Ecto.Changeset

  schema "trivia_rooms" do
    field :name, :string
    field :description, :string
    field :difficulty, :string, default: "medium"
    field :max_players, :integer, default: 10
    field :status, :string, default: "waiting"

    belongs_to :host, Amenity.Accounts.User
    has_many :participants, Amenity.Trivia.RoomParticipant

    timestamps()
  end

  @doc false
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :description, :difficulty, :max_players, :status, :host_id])
    |> validate_required([:name, :host_id])
    |> validate_inclusion(:difficulty, ["easy", "medium", "hard"])
    |> validate_inclusion(:status, ["waiting", "in_progress", "completed"])
    |> validate_number(:max_players, greater_than: 0, less_than_or_equal: 50)
  end
end
