defmodule Amenity.Social do
  @moduledoc """
  The Social context for groups and group management.
  """

  import Ecto.Query, warn: false
  alias Amenity.Repo

  alias Amenity.Social.{Group, GroupMember, GroupInvite}

  ## Groups

  @doc """
  Creates a group and adds the creator as owner.
  """
  def create_group(attrs, owner_id) do
    Repo.transaction(fn ->
      with {:ok, group} <-
             %Group{}
             |> Group.changeset(Map.put(attrs, :owner_id, owner_id))
             |> Repo.insert(),
           {:ok, _member} <-
             %GroupMember{}
             |> GroupMember.changeset(%{
               group_id: group.id,
               user_id: owner_id,
               role: "owner"
             })
             |> Repo.insert() do
        group
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Gets a single group.
  """
  def get_group!(id), do: Repo.get!(Group, id)

  @doc """
  Lists all public groups.
  """
  def list_public_groups do
    from(g in Group,
      where: g.is_private == false,
      order_by: [desc: g.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists groups a user is a member of.
  """
  def list_user_groups(user_id) do
    from(g in Group,
      join: gm in GroupMember,
      on: gm.group_id == g.id,
      where: gm.user_id == ^user_id,
      order_by: [desc: gm.joined_at]
    )
    |> Repo.all()
  end

  @doc """
  Updates a group.
  """
  def update_group(%Group{} = group, attrs) do
    group
    |> Group.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a group.
  """
  def delete_group(%Group{} = group) do
    Repo.delete(group)
  end

  ## Group Members

  @doc """
  Adds a user to a group.
  """
  def add_member(group_id, user_id, role \\ "member") do
    %GroupMember{}
    |> GroupMember.changeset(%{
      group_id: group_id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end

  @doc """
  Removes a user from a group.
  """
  def remove_member(group_id, user_id) do
    from(gm in GroupMember,
      where: gm.group_id == ^group_id and gm.user_id == ^user_id
    )
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Lists members of a group.
  """
  def list_group_members(group_id) do
    from(gm in GroupMember,
      where: gm.group_id == ^group_id,
      join: u in assoc(gm, :user),
      select: {gm, u},
      order_by: [asc: gm.role, asc: gm.joined_at]
    )
    |> Repo.all()
  end

  @doc """
  Checks if a user is a member of a group.
  """
  def member?(group_id, user_id) do
    from(gm in GroupMember,
      where: gm.group_id == ^group_id and gm.user_id == ^user_id
    )
    |> Repo.exists?()
  end

  @doc """
  Gets a user's role in a group.
  """
  def get_member_role(group_id, user_id) do
    case Repo.get_by(GroupMember, group_id: group_id, user_id: user_id) do
      nil -> nil
      member -> member.role
    end
  end

  ## Group Invites

  @doc """
  Sends a group invite.
  """
  def send_invite(group_id, inviter_id, invitee_id) do
    %GroupInvite{}
    |> GroupInvite.changeset(%{
      group_id: group_id,
      inviter_id: inviter_id,
      invitee_id: invitee_id,
      status: "pending"
    })
    |> Repo.insert()
  end

  @doc """
  Accepts a group invite.
  """
  def accept_invite(invite_id, user_id) do
    invite = Repo.get!(GroupInvite, invite_id)

    if invite.invitee_id == user_id do
      Repo.transaction(fn ->
        with {:ok, invite} <-
               invite
               |> GroupInvite.changeset(%{status: "accepted"})
               |> Repo.update(),
             {:ok, _member} <- add_member(invite.group_id, user_id) do
          invite
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Rejects a group invite.
  """
  def reject_invite(invite_id, user_id) do
    invite = Repo.get!(GroupInvite, invite_id)

    if invite.invitee_id == user_id do
      invite
      |> GroupInvite.changeset(%{status: "rejected"})
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Lists pending invites for a user.
  """
  def list_pending_invites(user_id) do
    from(gi in GroupInvite,
      where: gi.invitee_id == ^user_id and gi.status == "pending",
      join: g in assoc(gi, :group),
      join: inviter in assoc(gi, :inviter),
      select: {gi, g, inviter},
      order_by: [desc: gi.inserted_at]
    )
    |> Repo.all()
  end
end
