defmodule Amenity.Social do
  @moduledoc """
  The Social context for groups and group management.
  """

  import Ecto.Query, warn: false
  alias Amenity.Repo

  alias Amenity.Social.{Group, GroupMember, GroupInvite, Post, Reply}

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

  ## Posts

  @doc """
  Creates a post.
  """
  def create_post(attrs, user_id) do
    %Post{}
    |> Post.changeset(Map.put(attrs, "user_id", user_id))
    |> Repo.insert()
  end

  @doc """
  Gets a single post with user and replies preloaded.
  """
  def get_post!(id) do
    Post
    |> Repo.get!(id)
    |> Repo.preload([:user, replies: [:user]])
  end

  @doc """
  Gets a single post with reply count.
  """
  def get_post_with_reply_count!(id) do
    post = get_post!(id)
    reply_count = count_post_replies(id)
    Map.put(post, :reply_count, reply_count)
  end

  @doc """
  Lists all posts (public feed) with reply counts.
  """
  def list_posts do
    posts =
      from(p in Post,
        where: is_nil(p.group_id),
        join: u in assoc(p, :user),
        preload: [user: u],
        order_by: [desc: p.inserted_at]
      )
      |> Repo.all()

    # Add reply counts to each post
    Enum.map(posts, fn post ->
      reply_count = count_post_replies(post.id)
      Map.put(post, :reply_count, reply_count)
    end)
  end

  @doc """
  Lists posts for a specific group.
  """
  def list_group_posts(group_id) do
    from(p in Post,
      where: p.group_id == ^group_id,
      join: u in assoc(p, :user),
      preload: [user: u],
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Updates a post and sets edited_at timestamp.
  """
  def update_post(%Post{} = post, attrs) do
    post
    |> Post.changeset(Map.put(attrs, :edited_at, DateTime.utc_now()))
    |> Repo.update()
  end

  @doc """
  Deletes a post.
  """
  def delete_post(%Post{} = post) do
    Repo.delete(post)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking post changes.
  """
  def change_post(%Post{} = post, attrs \\ %{}) do
    Post.changeset(post, attrs)
  end

  @doc """
  Checks if a user can edit a post (must be the author).
  """
  def can_edit_post?(%Post{user_id: user_id}, current_user_id) do
    user_id == current_user_id
  end

  ## Replies

  @doc """
  Creates a reply to a post.
  """
  def create_reply(attrs, post_id, user_id) do
    %Reply{}
    |> Reply.changeset(Map.merge(attrs, %{"post_id" => post_id, "user_id" => user_id}))
    |> Repo.insert()
  end

  @doc """
  Updates a reply.
  """
  def update_reply(%Reply{} = reply, attrs) do
    reply
    |> Reply.changeset(Map.put(attrs, "edited_at", DateTime.utc_now()))
    |> Repo.update()
  end

  @doc """
  Deletes a reply.
  """
  def delete_reply(%Reply{} = reply) do
    Repo.delete(reply)
  end

  @doc """
  Gets a single reply.
  """
  def get_reply!(id) do
    Repo.get!(Reply, id)
  end

  @doc """
  Counts replies for a post.
  """
  def count_post_replies(post_id) do
    from(r in Reply, where: r.post_id == ^post_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking reply changes.
  """
  def change_reply(%Reply{} = reply, attrs \\ %{}) do
    Reply.changeset(reply, attrs)
  end

  @doc """
  Checks if a user can edit a reply (must be the author).
  """
  def can_edit_reply?(%Reply{user_id: user_id}, current_user_id) do
    user_id == current_user_id
  end
end
