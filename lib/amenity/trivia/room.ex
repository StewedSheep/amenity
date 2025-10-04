defmodule Amenity.Trivia.Room do
  use Ecto.Schema
  import Ecto.Changeset

  schema "trivia_rooms" do
    field :name, :string
    field :description, :string
    field :difficulty, :string, default: "medium"
    field :max_players, :integer, default: 10
    field :status, :string, default: "waiting"
    field :allowed_user_ids, {:array, :integer}, default: []
    field :book_of_moses, :string, default: "Genesis"
    field :question_count, :integer, default: 5

    belongs_to :host, Amenity.Accounts.User
    has_many :participants, Amenity.Trivia.RoomParticipant

    timestamps()
  end

  @doc false
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :description, :difficulty, :max_players, :status, :host_id, :allowed_user_ids, :book_of_moses, :question_count])
    |> validate_required([:name, :host_id])
    |> validate_inclusion(:difficulty, ["easy", "medium", "hard"])
    |> validate_inclusion(:status, ["waiting", "in_progress", "completed"])
    |> validate_inclusion(:book_of_moses, ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy"])
    |> validate_number(:max_players, greater_than: 0, less_than_or_equal: 50)
    |> validate_number(:question_count, greater_than: 0, less_than_or_equal: 10)
  end
end
