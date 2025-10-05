defmodule Amenity.Trivia.Room do
  use Ecto.Schema
  import Ecto.Changeset

  schema "trivia_rooms" do
    belongs_to :host, Amenity.Accounts.User
    field :name, :string
    field :book, :string
    field :num_questions, :integer
    field :status, :string, default: "waiting"
    field :current_question_index, :integer, default: 0
    field :questions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:host_id, :name, :book, :num_questions, :status, :current_question_index, :questions])
    |> validate_required([:host_id, :name, :book, :num_questions])
    |> validate_inclusion(:num_questions, [5, 10, 15])
    |> validate_inclusion(:book, ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy"])
    |> validate_inclusion(:status, ["waiting", "playing", "finished"])
  end
end
