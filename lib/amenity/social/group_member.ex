defmodule Amenity.Social.GroupMember do
  use Ecto.Schema
  import Ecto.Changeset

  schema "group_members" do
    belongs_to :group, Amenity.Social.Group
    belongs_to :user, Amenity.Accounts.User
    field :role, :string, default: "member"
    field :joined_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @roles ~w(owner admin moderator member)

  @doc false
  def changeset(group_member, attrs) do
    group_member
    |> cast(attrs, [:group_id, :user_id, :role, :joined_at])
    |> validate_required([:group_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:group_id, :user_id])
    |> put_joined_at()
  end

  defp put_joined_at(changeset) do
    if get_field(changeset, :joined_at) do
      changeset
    else
      put_change(changeset, :joined_at, DateTime.utc_now(:second))
    end
  end
end
