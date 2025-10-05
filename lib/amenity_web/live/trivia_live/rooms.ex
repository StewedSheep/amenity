defmodule AmenityWeb.TriviaLive.Rooms do
  use AmenityWeb, :live_view

  alias Amenity.Trivia

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    rooms = Trivia.list_active_rooms()
    
    # Get player counts for each room (only when connected)
    room_player_counts = if connected?(socket) do
      Phoenix.PubSub.subscribe(Amenity.PubSub, "trivia:rooms")
      # Schedule periodic player count updates
      :timer.send_interval(2000, self(), :refresh_player_counts)
      get_room_player_counts(rooms)
    else
      %{}
    end

    {:ok,
     socket
     |> assign(:rooms, rooms)
     |> assign(:room_player_counts, room_player_counts)
     |> assign(:show_create_modal, false)
     |> assign(:user_id, user_id)
     |> assign(:selected_book, nil)
     |> assign(:selected_num_questions, nil)}
  end

  @impl true
  def handle_event("toggle_create_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, !socket.assigns.show_create_modal)}
  end

  def handle_event("hide_create_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, false)
     |> assign(:selected_book, nil)
     |> assign(:selected_num_questions, nil)}
  end

  def handle_event("select_book", %{"book" => book}, socket) do
    {:noreply, assign(socket, :selected_book, book)}
  end

  def handle_event("select_num_questions", %{"num" => num}, socket) do
    {:noreply, assign(socket, :selected_num_questions, String.to_integer(num))}
  end

  def handle_event("create_room", %{"name" => name}, socket) do
    book = socket.assigns.selected_book
    num_q = socket.assigns.selected_num_questions

    if book && num_q do
      user_id = socket.assigns.user_id

      # Delete any existing rooms hosted by this user
      Trivia.delete_user_rooms(user_id)

      case Trivia.create_room(%{
             host_id: user_id,
             name: name,
             book: book,
             num_questions: num_q
         }) do
      {:ok, room} ->
        # Broadcast room created
        Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:rooms", {:room_created, room})

        {:noreply,
         socket
         |> assign(:show_create_modal, false)
         |> push_navigate(to: ~p"/study/trivia/#{room.id}")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not create room")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select book and number of questions")}
    end
  end

  def handle_event("modal_content_click", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_player_counts, socket) do
    # Refresh player counts for all rooms
    {:noreply, assign(socket, :room_player_counts, get_room_player_counts(socket.assigns.rooms))}
  end

  def handle_info({:room_created, _room}, socket) do
    rooms = Trivia.list_active_rooms()
    {:noreply, 
     socket
     |> assign(:rooms, rooms)
     |> assign(:room_player_counts, get_room_player_counts(rooms))}
  end

  def handle_info({:room_deleted, _room_id}, socket) do
    rooms = Trivia.list_active_rooms()
    {:noreply,
     socket
     |> assign(:rooms, rooms)
     |> assign(:room_player_counts, get_room_player_counts(rooms))}
  end

  defp get_room_player_counts(rooms) do
    rooms
    |> Enum.map(fn room ->
      player_count = 
        case AmenityWeb.Presence.list("trivia:#{room.id}") do
          players when is_map(players) -> map_size(players)
          _ -> 0
        end
      {room.id, player_count}
    end)
    |> Map.new()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-purple-50 via-pink-50 to-orange-50">
      <div class="max-w-7xl mx-auto px-4 py-8">
        <!-- Header -->
        <div class="mb-8">
          <.link navigate={~p"/study"} class="text-purple-600 hover:text-purple-800 mb-4 inline-block">
            ← Back to Study
          </.link>
          <div class="flex justify-between items-start">
            <div>
              <h1 class="text-5xl font-bold mb-2 text-gray-800">
                ⚔️ Trivia Battle
              </h1>
              <p class="text-gray-800 text-lg">Challenge your Bible knowledge in real-time!</p>
            </div>
            
            <!-- Create Room Dropdown -->
            <div class="relative">
              <button
                phx-click="toggle_create_dropdown"
                class="btn btn-primary btn-lg rounded-full"
              >
                ➕ Create Room
              </button>
              
              <%= if @show_create_modal do %>
                <div class="absolute right-0 mt-2 w-96 bg-white rounded-2xl shadow-2xl p-6 z-50 border-2 border-purple-300">
                  <h3 class="text-xl font-bold text-gray-800 mb-4">Create Trivia Room</h3>
                  
                  <form phx-submit="create_room" class="space-y-4">
                    <div>
                      <label class="block text-sm font-semibold text-gray-700 mb-2">Room Name</label>
                      <input
                        type="text"
                        name="name"
                        required
                        class="input input-bordered w-full"
                        value={"#{@current_scope.user.username}'s room"}
                      />
                    </div>

                    <div>
                      <label class="block text-sm font-semibold text-gray-700 mb-3">Book of Moses</label>
                      <div class="grid grid-cols-2 gap-2">
                        <%= for book <- ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy"] do %>
                          <button
                            type="button"
                            phx-click="select_book"
                            phx-value-book={book}
                            class={"btn btn-sm transition-all #{if @selected_book == book, do: "bg-purple-600 hover:bg-purple-700 text-white border-purple-600", else: "bg-white hover:bg-purple-50 text-gray-700 border-2 border-purple-300 hover:border-purple-400"}"}
                          >
                            {book}
                          </button>
                        <% end %>
                      </div>
                    </div>

                    <div>
                      <label class="block text-sm font-semibold text-gray-700 mb-3">Number of Questions</label>
                      <div class="grid grid-cols-3 gap-2">
                        <%= for num <- [5, 10, 15] do %>
                          <button
                            type="button"
                            phx-click="select_num_questions"
                            phx-value-num={num}
                            class={"btn btn-sm transition-all #{if @selected_num_questions == num, do: "bg-pink-600 hover:bg-pink-700 text-white border-pink-600", else: "bg-white hover:bg-pink-50 text-gray-700 border-2 border-pink-300 hover:border-pink-400"}"}
                          >
                            {num}
                          </button>
                        <% end %>
                      </div>
                    </div>

                    <div class="flex gap-2 pt-2">
                      <button type="button" phx-click="hide_create_modal" class="btn btn-ghost flex-1 btn-sm">
                        Cancel
                      </button>
                      <button type="submit" class="btn btn-primary flex-1 btn-sm">
                        Create
                      </button>
                    </div>
                  </form>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Active Rooms -->
        <%= if @rooms == [] do %>
          <div class="text-center py-20 bg-white rounded-3xl shadow-lg">
            <div class="text-8xl mb-4">🎮</div>
            <p class="text-2xl text-gray-800 mb-4">No active rooms</p>
            <p class="text-gray-700">Create a room to start playing!</p>
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for room <- @rooms do %>
              <.link
                navigate={~p"/study/trivia/#{room.id}"}
                class="bg-white rounded-2xl p-6 shadow-lg hover:shadow-2xl transition-all hover:scale-105 border-t-4 border-purple-400"
              >
                <div class="flex items-start justify-between mb-4">
                  <div>
                    <h3 class="text-xl font-bold text-gray-800 mb-1">{room.name}</h3>
                    <p class="text-sm text-gray-700">Host: {room.host.username}</p>
                  </div>
                  <span class={
                    "badge #{if room.status == "waiting", do: "badge-success", else: "badge-warning"}"
                  }>
                    {room.status}
                  </span>
                </div>

                <div class="space-y-2 text-sm text-gray-800">
                  <div class="flex items-center gap-2">
                    <span>📖</span>
                    <span>{room.book}</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <span>❓</span>
                    <span>{room.num_questions} questions</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <span>👥</span>
                    <span>{Map.get(@room_player_counts, room.id, 0)} players</span>
                  </div>
                </div>

                <div class="mt-4 pt-4 border-t border-gray-200">
                  <span class="text-purple-600 font-semibold">Join Room →</span>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>

        <!-- How to Play -->
        <div class="mt-12 bg-white rounded-3xl p-8 shadow-lg">
          <h2 class="text-2xl font-bold text-gray-800 mb-4">How to Play</h2>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div>
              <div class="text-3xl mb-2">1️⃣</div>
              <h3 class="font-bold text-gray-800 mb-2">Create or Join</h3>
              <p class="text-gray-800 text-sm">
                Create a new room or join an existing one
              </p>
            </div>
            <div>
              <div class="text-3xl mb-2">2️⃣</div>
              <h3 class="font-bold text-gray-800 mb-2">Answer Fast</h3>
              <p class="text-gray-800 text-sm">
                Answer questions quickly to earn bonus points
              </p>
            </div>
            <div>
              <div class="text-3xl mb-2">3️⃣</div>
              <h3 class="font-bold text-gray-800 mb-2">Win!</h3>
              <p class="text-gray-800 text-sm">
                Player with the highest score wins the battle
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
