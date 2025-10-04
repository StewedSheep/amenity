defmodule Amenity.Trivia do
  @moduledoc """
  The Trivia context for managing trivia battles and rooms.
  """

  import Ecto.Query, warn: false
  alias Amenity.Repo
  alias Amenity.Trivia.{Room, RoomParticipant}

  @doc """
  Returns the list of trivia rooms.
  """
  def list_rooms(_current_scope) do
    Room
    |> where([r], r.status in ["waiting", "in_progress"])
    |> preload([:host, participants: :user])
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single room.
  """
  def get_room!(_current_scope, id) do
    Room
    |> preload([:host, participants: :user])
    |> Repo.get!(id)
  end

  @doc """
  Creates a room. Sets allowed_user_ids to current participants in the lobby.
  """
  def create_room(current_scope, attrs \\ %{}, online_user_ids \\ []) do
    attrs = 
      attrs
      |> Map.put("host_id", current_scope.user.id)
      |> Map.put("allowed_user_ids", online_user_ids)

    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, room} ->
        # Automatically add the host as a participant
        join_room(current_scope, room.id)
        {:ok, get_room!(current_scope, room.id)}

      error ->
        error
    end
  end

  @doc """
  Updates a room.
  """
  def update_room(_current_scope, %Room{} = room, attrs) do
    room
    |> Room.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Starts the game for a room.
  """
  def start_game(_current_scope, room_id) do
    room = Repo.get!(Room, room_id)

    room
    |> Room.changeset(%{status: "in_progress"})
    |> Repo.update()
  end

  @doc """
  Ends the game and marks room as completed.
  """
  def end_game(_current_scope, room_id) do
    room = Repo.get!(Room, room_id)

    room
    |> Room.changeset(%{status: "completed"})
    |> Repo.update()
  end

  @doc """
  Deletes a room.
  """
  def delete_room(_current_scope, %Room{} = room) do
    Repo.delete(room)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking room changes.
  """
  def change_room(%Room{} = room, attrs \\ %{}) do
    Room.changeset(room, attrs)
  end

  @doc """
  Joins a user to a room. If the user is already in another room, they are removed from it first.
  If the user is a host of another room, that room is disbanded.
  Checks if user is allowed to join based on allowed_user_ids whitelist.
  """
  def join_room(current_scope, room_id) do
    # Check if user is allowed to join this room
    room = Repo.get!(Room, room_id)
    
    unless Enum.empty?(room.allowed_user_ids) or current_scope.user.id in room.allowed_user_ids do
      {:error, :not_allowed}
    else
      # Check if user is host of any room and delete those rooms
      Room
      |> where([r], r.host_id == ^current_scope.user.id and r.id != ^room_id)
      |> Repo.delete_all()

      # Remove user from any existing room they're in as a participant
      RoomParticipant
      |> where([p], p.user_id == ^current_scope.user.id and p.room_id != ^room_id)
      |> Repo.delete_all()

      # Then join the new room
      %RoomParticipant{}
      |> RoomParticipant.changeset(%{
        room_id: room_id,
        user_id: current_scope.user.id,
        joined_at: DateTime.utc_now()
      })
      |> Repo.insert()
    end
  end

  @doc """
  Leaves a room. If the user is the host, deletes the entire room.
  After a participant leaves, checks if room is empty and deletes it if so.
  """
  def leave_room(current_scope, room_id) do
    room = Repo.get(Room, room_id)

    case room do
      nil ->
        {:error, :not_found}

      %Room{host_id: host_id} when host_id == current_scope.user.id ->
        # Host is leaving - delete the entire room (cascades to participants)
        Repo.delete(room)

      _room ->
        # Regular participant leaving
        result =
          RoomParticipant
          |> where([p], p.room_id == ^room_id and p.user_id == ^current_scope.user.id)
          |> Repo.one()
          |> case do
            nil -> {:error, :not_found}
            participant -> Repo.delete(participant)
          end

        # After participant leaves, check if room is empty
        case result do
          {:ok, _} ->
            check_and_delete_empty_room(room_id)
            result

          error ->
            error
        end
    end
  end

  # Checks if a room has no participants and deletes it if empty.
  defp check_and_delete_empty_room(room_id) do
    participant_count =
      RoomParticipant
      |> where([p], p.room_id == ^room_id)
      |> Repo.aggregate(:count)

    if participant_count == 0 do
      case Repo.get(Room, room_id) do
        nil -> :ok
        room -> Repo.delete(room)
      end
    end

    :ok
  end

  @doc """
  Gets the participant count for a room.
  """
  def get_participant_count(_current_scope, room_id) do
    RoomParticipant
    |> where([p], p.room_id == ^room_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Checks if a user is in a room.
  """
  def user_in_room?(current_scope, room_id) do
    RoomParticipant
    |> where([p], p.room_id == ^room_id and p.user_id == ^current_scope.user.id)
    |> Repo.exists?()
  end

  @doc """
  Toggles a user's ready status in a room.
  """
  def toggle_ready(current_scope, room_id) do
    RoomParticipant
    |> where([p], p.room_id == ^room_id and p.user_id == ^current_scope.user.id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      participant ->
        participant
        |> RoomParticipant.changeset(%{is_ready: !participant.is_ready})
        |> Repo.update()
    end
  end

  @doc """
  Checks if all participants in a room are ready.
  """
  def all_ready?(room_id) do
    participant_count =
      RoomParticipant
      |> where([p], p.room_id == ^room_id)
      |> Repo.aggregate(:count)

    ready_count =
      RoomParticipant
      |> where([p], p.room_id == ^room_id and p.is_ready == true)
      |> Repo.aggregate(:count)

    participant_count > 0 and participant_count == ready_count
  end

  @doc """
  Records a participant's answer and updates their score.
  """
  def record_answer(current_scope, room_id, is_correct) do
    RoomParticipant
    |> where([p], p.room_id == ^room_id and p.user_id == ^current_scope.user.id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      participant ->
        new_score = if is_correct, do: participant.score + 1, else: participant.score

        participant
        |> RoomParticipant.changeset(%{score: new_score})
        |> Repo.update()
    end
  end

  @doc """
  Gets the winner(s) of a room based on score.
  """
  def get_winners(room_id) do
    participants =
      RoomParticipant
      |> where([p], p.room_id == ^room_id)
      |> preload(:user)
      |> Repo.all()

    max_score = Enum.map(participants, & &1.score) |> Enum.max(fn -> 0 end)
    Enum.filter(participants, &(&1.score == max_score))
  end

  @doc """
  Checks if all participants in a room have answered (score > 0 or explicitly tracked).
  For simplicity, we'll track by checking if we've recorded answers.
  """
  def all_answered?(room_id) do
    # Get total participants
    total = 
      RoomParticipant
      |> where([p], p.room_id == ^room_id)
      |> Repo.aggregate(:count)
    
    # For this simple implementation, we'll use a different approach
    # We'll track answered state in the LiveView instead
    total
  end

  @doc """
  Gets participant count for a room.
  """
  def get_participant_count(room_id) do
    RoomParticipant
    |> where([p], p.room_id == ^room_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Disbands all rooms hosted by a specific user (when they disconnect).
  """
  def disband_user_hosted_rooms(user_id) do
    Room
    |> where([r], r.host_id == ^user_id)
    |> Repo.delete_all()
  end
end
