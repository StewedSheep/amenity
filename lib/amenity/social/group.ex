defmodule Amenity.Social.Group do
  use Ecto.Schema
  import Ecto.Changeset

  schema "groups" do
    field :name, :string
    field :description, :string
    field :is_private, :boolean, default: false
    field :avatar_url, :string

    belongs_to :owner, Amenity.Accounts.User
    has_many :group_members, Amenity.Social.GroupMember
    has_many :members, through: [:group_members, :user]
    has_many :group_invites, Amenity.Social.GroupInvite

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :description, :owner_id, :is_private, :avatar_url])
    |> validate_required([:name, :owner_id])
    |> validate_length(:name, min: 3, max: 100)
    |> validate_length(:description, max: 500)
  end
end
