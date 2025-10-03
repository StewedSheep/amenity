defmodule Amenity.Accounts.Friendship do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friendships" do
    belongs_to :user, Amenity.Accounts.User
    belongs_to :friend, Amenity.Accounts.User
    field :status, :string, default: "pending"

    timestamps(type: :utc_datetime)
  end

  @statuses ~w(pending accepted rejected blocked)

  def changeset(friendship, attrs) do
    friendship
    |> cast(attrs, [:user_id, :friend_id, :status])
    |> validate_required([:user_id, :friend_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_not_self()
    |> unique_constraint([:user_id, :friend_id])
  end

  defp validate_not_self(changeset) do
    user_id = get_field(changeset, :user_id)
    friend_id = get_field(changeset, :friend_id)

    if user_id && friend_id && user_id == friend_id do
      add_error(changeset, :friend_id, "cannot friend yourself")
    else
      changeset
    end
  end
end
