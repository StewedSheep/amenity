defmodule Amenity.Social.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :title, :string
    field :content, :string
    field :images, {:array, :string}, default: []
    field :edited_at, :utc_datetime

    belongs_to :user, Amenity.Accounts.User
    belongs_to :group, Amenity.Social.Group
    has_many :replies, Amenity.Social.Reply

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :content, :images, :user_id, :group_id, :edited_at])
    |> validate_required([:title, :content, :user_id])
    |> validate_length(:title, min: 3, max: 200)
    |> validate_length(:content, min: 10, max: 10_000)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:group_id)
  end
end
