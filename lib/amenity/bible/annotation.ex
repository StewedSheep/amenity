defmodule Amenity.Bible.Annotation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bible_annotations" do
    belongs_to :user, Amenity.Accounts.User
    field :book, :string
    field :chapter, :integer
    field :verse, :integer
    field :content, :string
    field :note, :string
    field :color, :string, default: "yellow"

    timestamps(type: :utc_datetime)
  end

  @colors ~w(yellow blue green pink purple)

  @doc false
  def changeset(annotation, attrs) do
    annotation
    |> cast(attrs, [:user_id, :book, :chapter, :verse, :content, :note, :color])
    |> validate_required([:user_id, :book, :chapter, :verse, :content])
    |> validate_inclusion(:color, @colors)
    |> validate_length(:content, min: 1, max: 5000)
    |> validate_length(:note, max: 10000)
  end
end
