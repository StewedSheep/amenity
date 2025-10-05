defmodule Amenity.Workers.CleanupTriviaRoomsWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Amenity.Repo
  alias Amenity.Trivia.Room
  alias AmenityWeb.Presence
  alias Phoenix.PubSub
  import Ecto.Query

  @impl Oban.Worker
  def perform(_job) do
    # Find all active rooms
    rooms = 
      from(r in Room, where: r.status in ["waiting", "playing"])
      |> Repo.all()

    deleted_count = 
      rooms
      |> Enum.reduce(0, fn room, count ->
        # Check if room has any players via Presence
        players = Presence.list("trivia:#{room.id}")
        
        cond do
          # No players in room
          map_size(players) == 0 ->
            Repo.delete(room)
            PubSub.broadcast(Amenity.PubSub, "trivia:rooms", {:room_deleted, room.id})
            count + 1
          
          # Host not in room
          not Map.has_key?(players, Integer.to_string(room.host_id)) ->
            Repo.delete(room)
            PubSub.broadcast(Amenity.PubSub, "trivia:#{room.id}", :room_deleted)
            PubSub.broadcast(Amenity.PubSub, "trivia:rooms", {:room_deleted, room.id})
            count + 1
          
          # Room is older than 2 hours and still waiting
          room.status == "waiting" && 
          DateTime.diff(DateTime.utc_now(), room.inserted_at, :hour) > 2 ->
            Repo.delete(room)
            PubSub.broadcast(Amenity.PubSub, "trivia:#{room.id}", :room_deleted)
            PubSub.broadcast(Amenity.PubSub, "trivia:rooms", {:room_deleted, room.id})
            count + 1
          
          true ->
            count
        end
      end)

    if deleted_count > 0 do
      require Logger
      Logger.info("Cleaned up #{deleted_count} stale trivia rooms")
    end

    :ok
  end
end
