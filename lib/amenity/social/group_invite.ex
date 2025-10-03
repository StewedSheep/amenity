defmodule Amenity.Social.GroupInvite do
  use Ecto.Schema
  import Ecto.Changeset

  schema "group_invites" do
    belongs_to :group, Amenity.Social.Group
    belongs_to :inviter, Amenity.Accounts.User
    belongs_to :invitee, Amenity.Accounts.User
    field :status, :string, default: "pending"

    timestamps(type: :utc_datetime)
  end

  @statuses ~w(pending accepted rejected)

  @doc false
  def changeset(group_invite, attrs) do
    group_invite
    |> cast(attrs, [:group_id, :inviter_id, :invitee_id, :status])
    |> validate_required([:group_id, :inviter_id, :invitee_id])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:group_id, :invitee_id])
  end
end
