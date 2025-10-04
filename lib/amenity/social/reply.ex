defmodule Amenity.Social.Reply do
  use Ecto.Schema
  import Ecto.Changeset

  schema "post_replies" do
    field :content, :string
    field :edited_at, :utc_datetime

    belongs_to :post, Amenity.Social.Post
    belongs_to :user, Amenity.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(reply, attrs) do
    reply
    |> cast(attrs, [:content, :post_id, :user_id, :edited_at])
    |> validate_required([:content, :post_id, :user_id])
    |> validate_length(:content, min: 1, max: 10_000)
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:user_id)
  end
end
