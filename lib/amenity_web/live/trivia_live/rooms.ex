defmodule AmenityWeb.TriviaLive.Rooms do
  use AmenityWeb, :live_view

  alias Amenity.Trivia
  alias AmenityWeb.Presence

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Amenity.PubSub, "trivia:lobby")
    end

    rooms = Trivia.list_rooms(socket.assigns.current_scope)

    socket =
      socket
      |> assign(:rooms, rooms)
      |> assign(:show_create_form, false)
      |> assign(:form, to_form(Trivia.change_room(%Amenity.Trivia.Room{})))
      |> assign(:online_users, [])
      |> assign(:game_state, nil)
      |> assign(:countdown, nil)
      |> assign(:current_room_id, nil)
      |> assign(:question_timer, nil)
      |> assign(:answered_users, MapSet.new())

    socket =
      if connected?(socket) do
        Presence.track(self(), "trivia:lobby", socket.assigns.current_scope.user.id, %{
          username: socket.assigns.current_scope.user.username,
          joined_at: System.system_time(:second)
        })

        online_users =
          Presence.list("trivia:lobby")
          |> Map.values()
          |> Enum.map(fn data ->
            data[:metas]
            |> List.first()
          end)
          |> Enum.reject(&is_nil/1)

        assign(socket, :online_users, online_users)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_create_form", _params, socket) do
    {:noreply, assign(socket, :show_create_form, !socket.assigns.show_create_form)}
  end

  @impl true
  def handle_event("validate", %{"room" => room_params}, socket) do
    changeset =
      %Amenity.Trivia.Room{}
      |> Trivia.change_room(room_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("create_room", %{"room" => room_params}, socket) do
    case Trivia.create_room(socket.assigns.current_scope, room_params) do
      {:ok, _room} ->
        Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", :room_updated)
        rooms = Trivia.list_rooms(socket.assigns.current_scope)

        socket =
          socket
          |> assign(:rooms, rooms)
          |> assign(:show_create_form, false)
          |> assign(:form, to_form(Trivia.change_room(%Amenity.Trivia.Room{})))
          |> put_flash(:info, "Room created successfully!")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("join_room", %{"room-id" => room_id}, socket) do
    room_id = String.to_integer(room_id)

    case Trivia.join_room(socket.assigns.current_scope, room_id) do
      {:ok, _participant} ->
        Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", :room_updated)
        rooms = Trivia.list_rooms(socket.assigns.current_scope)

        socket =
          socket
          |> assign(:rooms, rooms)
          |> put_flash(:info, "Joined room successfully!")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not join room")}
    end
  end

  @impl true
  def handle_event("leave_room", %{"room-id" => room_id}, socket) do
    room_id = String.to_integer(room_id)
    room = Enum.find(socket.assigns.rooms, &(&1.id == room_id))
    is_host = room && room.host_id == socket.assigns.current_scope.user.id

    case Trivia.leave_room(socket.assigns.current_scope, room_id) do
      {:ok, _} ->
        Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", :room_updated)
        rooms = Trivia.list_rooms(socket.assigns.current_scope)

        flash_message =
          if is_host do
            "Room deleted successfully! All participants have been removed."
          else
            "Left room successfully!"
          end

        socket =
          socket
          |> assign(:rooms, rooms)
          |> put_flash(:info, flash_message)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not leave room")}
    end
  end

  @impl true
  def handle_event("toggle_ready", %{"room-id" => room_id}, socket) do
    room_id = String.to_integer(room_id)

    case Trivia.toggle_ready(socket.assigns.current_scope, room_id) do
      {:ok, _participant} ->
        Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", :room_updated)
        rooms = Trivia.list_rooms(socket.assigns.current_scope)
        {:noreply, assign(socket, :rooms, rooms)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update ready status")}
    end
  end

  @impl true
  def handle_event("start_game", %{"room-id" => room_id}, socket) do
    room_id = String.to_integer(room_id)
    
    # Start the game
    Trivia.start_game(socket.assigns.current_scope, room_id)
    
    # Broadcast game start to all players
    Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", {:game_started, room_id})
    
    # Start countdown for host
    socket =
      socket
      |> assign(:current_room_id, room_id)
      |> assign(:game_state, :countdown)
      |> assign(:countdown, 3)
    
    # Schedule countdown ticks that will be broadcast to all
    schedule_countdown(room_id, 3)
    
    {:noreply, socket}
  end

  defp schedule_countdown(room_id, count) when count > 0 do
    Process.send_after(self(), {:broadcast_countdown, room_id, count}, 1000)
  end

  defp schedule_countdown(_room_id, _count), do: :ok

  @impl true
  def handle_event("answer_question", %{"room-id" => room_id, "answer" => answer}, socket) do
    room_id = String.to_integer(room_id)
    is_correct = answer == "no"
    
    Trivia.record_answer(socket.assigns.current_scope, room_id, is_correct)
    
    # Broadcast that someone answered
    Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", {:player_answered, room_id, socket.assigns.current_scope.user.id})
    
    socket = assign(socket, :game_state, :answered)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("close_game", _params, socket) do
    rooms = Trivia.list_rooms(socket.assigns.current_scope)
    
    socket =
      socket
      |> assign(:game_state, nil)
      |> assign(:countdown, nil)
      |> assign(:current_room_id, nil)
      |> assign(:winners, nil)
      |> assign(:rooms, rooms)
    
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "presence_diff"}, socket) do
    online_users =
      Presence.list("trivia:lobby")
      |> Map.values()
      |> Enum.map(fn data ->
        data[:metas]
        |> List.first()
      end)
      |> Enum.reject(&is_nil/1)

    {:noreply, assign(socket, :online_users, online_users)}
  end

  @impl true
  def handle_info(:room_updated, socket) do
    rooms = Trivia.list_rooms(socket.assigns.current_scope)
    {:noreply, assign(socket, :rooms, rooms)}
  end

  @impl true
  def handle_info({:game_started, room_id}, socket) do
    # Check if user is in this room
    room = Enum.find(socket.assigns.rooms, &(&1.id == room_id))
    
    if room && Enum.any?(room.participants, &(&1.user_id == socket.assigns.current_scope.user.id)) do
      socket =
        socket
        |> assign(:current_room_id, room_id)
        |> assign(:game_state, :countdown)
        |> assign(:countdown, 3)
      
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:broadcast_countdown, room_id, count}, socket) do
    # Broadcast countdown update to all players
    Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", {:countdown_update, room_id, count - 1})
    
    if count > 1 do
      schedule_countdown(room_id, count - 1)
    else
      # Countdown finished, broadcast question start
      Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", {:show_question, room_id})
      # Auto-end game after 10 seconds
      Process.send_after(self(), {:broadcast_end_game, room_id}, 10_000)
    end
    
    {:noreply, socket}
  end

  @impl true
  def handle_info({:countdown_update, room_id, new_count}, socket) do
    if socket.assigns.current_room_id == room_id do
      {:noreply, assign(socket, :countdown, new_count)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:show_question, room_id}, socket) do
    if socket.assigns.current_room_id == room_id do
      socket =
        socket
        |> assign(:game_state, :question)
        |> assign(:countdown, nil)
        |> assign(:question_timer, 10)
        |> assign(:answered_users, MapSet.new())
      
      # Start question timer countdown
      Process.send_after(self(), {:question_timer_tick, room_id}, 1000)
      
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:question_timer_tick, room_id}, socket) do
    if socket.assigns.current_room_id == room_id and socket.assigns.question_timer do
      new_timer = socket.assigns.question_timer - 1
      
      # Broadcast timer update to all players
      Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", {:timer_update, room_id, new_timer})
      
      if new_timer > 0 do
        Process.send_after(self(), {:question_timer_tick, room_id}, 1000)
        {:noreply, assign(socket, :question_timer, new_timer)}
      else
        # Time's up, end game
        Process.send(self(), {:broadcast_end_game, room_id}, [])
        {:noreply, assign(socket, :question_timer, 0)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:timer_update, room_id, new_timer}, socket) do
    if socket.assigns.current_room_id == room_id do
      {:noreply, assign(socket, :question_timer, new_timer)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:player_answered, room_id, user_id}, socket) do
    if socket.assigns.current_room_id == room_id do
      # Track who answered (only for host to check)
      answered_users = MapSet.put(socket.assigns.answered_users, user_id)
      socket = assign(socket, :answered_users, answered_users)
      
      # Check if everyone answered (only host checks and triggers end)
      room = Enum.find(socket.assigns.rooms, &(&1.id == room_id))
      
      if room && MapSet.size(answered_users) >= length(room.participants) do
        # Everyone answered! End game immediately
        Process.send(self(), {:broadcast_end_game, room_id}, [])
      end
      
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:broadcast_end_game, room_id}, socket) do
    Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", {:end_game, room_id})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:end_game, room_id}, socket) do
    if socket.assigns.current_room_id == room_id do
      Trivia.end_game(socket.assigns.current_scope, room_id)
      winners = Trivia.get_winners(room_id)
      
      socket =
        socket
        |> assign(:game_state, :results)
        |> assign(:winners, winners)
      
      Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", :room_updated)
      
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <!-- Game Overlay -->
      <%= if @game_state do %>
        <div class="fixed inset-0 bg-black bg-opacity-90 z-50 flex items-center justify-center">
          <div class="text-center">
            <%= cond do %>
              <% @game_state == :countdown -> %>
                <div class="text-white">
                  <h2 class="text-6xl font-bold mb-8">Get Ready!</h2>
                  <div class="text-9xl font-bold animate-pulse">{@countdown}</div>
                </div>
              
              <% @game_state == :question -> %>
                <div class="bg-white rounded-3xl p-12 max-w-2xl">
                  <div class="flex justify-between items-center mb-8">
                    <h2 class="text-4xl font-bold text-gray-800">Are you gay?</h2>
                    <div class="text-3xl font-bold text-purple-600">
                      ⏱️ {@question_timer}s
                    </div>
                  </div>
                  <div class="space-y-4">
                    <button
                      phx-click="answer_question"
                      phx-value-room-id={@current_room_id}
                      phx-value-answer="yes"
                      class="btn btn-lg btn-error w-full text-2xl rounded-full"
                    >
                      Yes
                    </button>
                    <button
                      phx-click="answer_question"
                      phx-value-room-id={@current_room_id}
                      phx-value-answer="no"
                      class="btn btn-lg btn-success w-full text-2xl rounded-full"
                    >
                      No
                    </button>
                  </div>
                </div>
              
              <% @game_state == :answered -> %>
                <div class="text-white">
                  <h2 class="text-5xl font-bold mb-4">Answer Submitted!</h2>
                  <p class="text-2xl">Waiting for other players...</p>
                  <%= if @question_timer do %>
                    <p class="text-xl mt-4 opacity-75">⏱️ {@question_timer}s remaining</p>
                  <% end %>
                </div>
              
              <% @game_state == :results -> %>
                <div class="bg-white rounded-3xl p-12 max-w-2xl">
                  <% current_user_won = Enum.any?(@winners, &(&1.user_id == @current_scope.user.id)) %>
                  
                  <%= if current_user_won do %>
                    <h2 class="text-5xl font-bold mb-8 text-gray-800">🎉 Game Over! 🎉</h2>
                    <%= if length(@winners) == 1 do %>
                      <p class="text-4xl font-bold text-purple-600 mb-4">You Won! 🏆</p>
                      <p class="text-2xl text-gray-600">Congratulations, champion!</p>
                    <% else %>
                      <p class="text-3xl mb-4">It's a tie!</p>
                      <div class="space-y-2">
                        <%= for winner <- @winners do %>
                          <p class="text-2xl font-bold text-purple-600">{winner.user.username}</p>
                        <% end %>
                      </div>
                    <% end %>
                  <% else %>
                    <h2 class="text-5xl font-bold mb-8 text-red-600">💀 You Lost 💀</h2>
                    <p class="text-3xl font-bold text-gray-800 mb-4">You are bad and you lost.</p>
                    <p class="text-xl text-gray-600 mb-6">Maybe try being better next time? 🤷</p>
                    
                    <div class="border-t-2 border-gray-200 pt-6 mt-6">
                      <%= if length(@winners) == 1 do %>
                        <p class="text-2xl mb-2 text-gray-600">Winner:</p>
                        <p class="text-3xl font-bold text-purple-600">{hd(@winners).user.username}</p>
                      <% else %>
                        <p class="text-2xl mb-2 text-gray-600">Winners:</p>
                        <div class="space-y-2">
                          <%= for winner <- @winners do %>
                            <p class="text-2xl font-bold text-purple-600">{winner.user.username}</p>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                  
                  <button
                    phx-click="close_game"
                    class="btn btn-primary btn-lg rounded-full mt-8"
                  >
                    Back to Lobby
                  </button>
                </div>
              
              <% true -> %>
                <div></div>
            <% end %>
          </div>
        </div>
      <% end %>

      <div class="min-h-screen bg-gradient-to-br from-purple-50 via-pink-50 to-blue-50">
        <div class="max-w-7xl mx-auto px-4 py-8">
          <!-- Header -->
          <div class="text-center mb-8">
            <h1 class="text-5xl font-bold mb-4">
              ⚔️
              <span class="bg-gradient-to-r from-purple-600 via-pink-600 to-blue-600 bg-clip-text text-transparent">
                Trivia Battle Rooms
              </span>
            </h1>
            <p class="text-xl text-gray-600">Join a room or create your own battle!</p>
            
    <!-- Online Users Indicator -->
            <div class="mt-4 inline-flex items-center gap-2 bg-green-100 px-4 py-2 rounded-full">
              <span class="relative flex h-3 w-3">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75">
                </span>
                <span class="relative inline-flex rounded-full h-3 w-3 bg-green-500"></span>
              </span>
              <span class="text-green-800 font-semibold">
                {length(@online_users)} {if length(@online_users) == 1, do: "player", else: "players"} online
              </span>
            </div>
          </div>
          
    <!-- Create Room Button (only show if rooms exist) -->
          <%= if !Enum.empty?(@rooms) do %>
            <div class="mb-8 flex justify-center">
              <button
                phx-click="toggle_create_form"
                class="btn btn-primary btn-lg rounded-full px-8"
              >
                <%= if @show_create_form do %>
                  ✕ Cancel
                <% else %>
                  ➕ Create New Room
                <% end %>
              </button>
            </div>
          <% end %>
          
    <!-- Create Room Form -->
          <%= if @show_create_form do %>
            <div class="max-w-2xl mx-auto mb-8 bg-white rounded-3xl p-8 shadow-xl">
              <h2 class="text-2xl font-bold mb-6 text-gray-800">Create a New Room</h2>

              <.form
                for={@form}
                id="create-room-form"
                phx-submit="create_room"
                phx-change="validate"
              >
                <div class="space-y-4">
                  <.input
                    field={@form[:name]}
                    type="text"
                    label="Room Name"
                    placeholder="My Awesome Trivia Room"
                    required
                  />

                  <.input
                    field={@form[:description]}
                    type="textarea"
                    label="Description"
                    placeholder="Describe your room..."
                  />

                  <.input
                    field={@form[:difficulty]}
                    type="select"
                    label="Difficulty"
                    options={[{"Easy", "easy"}, {"Medium", "medium"}, {"Hard", "hard"}]}
                  />

                  <.input
                    field={@form[:max_players]}
                    type="number"
                    label="Max Players"
                    min="2"
                    max="50"
                  />

                  <div class="flex gap-4">
                    <button type="submit" class="btn btn-primary flex-1 rounded-full">
                      Create Room
                    </button>
                  </div>
                </div>
              </.form>
            </div>
          <% end %>
          
    <!-- Rooms Grid -->
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for room <- @rooms do %>
              <div class="bg-white rounded-2xl p-6 shadow-lg hover:shadow-xl transition-all">
                <!-- Room Header -->
                <div class="flex items-start justify-between mb-4">
                  <div class="flex-1">
                    <h3 class="text-xl font-bold text-gray-800 mb-1">{room.name}</h3>
                    <p class="text-sm text-gray-500">
                      Hosted by {room.host.username}
                    </p>
                  </div>
                  <div class={[
                    "badge badge-lg",
                    room.status == "waiting" && "badge-success animate-pulse",
                    room.status == "in_progress" && "badge-warning",
                    room.status == "completed" && "badge-neutral"
                  ]}>
                    <%= if room.status == "waiting" do %>
                      <span class="inline-flex items-center gap-1">
                        <span class="animate-spin" style="animation-duration: 2s;">⏳</span>
                        <span>WAITING</span>
                      </span>
                    <% else %>
                      {String.upcase(room.status)}
                    <% end %>
                  </div>
                </div>
                
    <!-- Room Description -->
                <%= if room.description do %>
                  <p class="text-gray-600 text-sm mb-4 line-clamp-2">{room.description}</p>
                <% end %>
                
    <!-- Room Info -->
                <div class="mb-4">
                  <div class="flex items-center gap-4 mb-3 text-sm">
                    <div class="flex items-center gap-1">
                      <span class="text-purple-500">👥</span>
                      <span class="text-gray-700">
                        {length(room.participants)}/{room.max_players}
                      </span>
                    </div>
                    <div class={[
                      "badge",
                      room.difficulty == "easy" && "badge-success",
                      room.difficulty == "medium" && "badge-warning",
                      room.difficulty == "hard" && "badge-error"
                    ]}>
                      {String.upcase(room.difficulty)}
                    </div>
                  </div>
                  <!-- Participants List -->
                  <%= if length(room.participants) > 0 do %>
                    <div class="flex flex-wrap gap-2">
                      <%= for participant <- Enum.take(room.participants, 5) do %>
                        <div class={[
                          "badge badge-sm gap-1",
                          participant.is_ready && "badge-success",
                          !participant.is_ready && "badge-outline"
                        ]}>
                          <%= if participant.is_ready do %>
                            <span>✓</span>
                          <% else %>
                            <span class="relative flex h-2 w-2">
                              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-purple-400 opacity-75">
                              </span>
                              <span class="relative inline-flex rounded-full h-2 w-2 bg-purple-500">
                              </span>
                            </span>
                          <% end %>
                          {participant.user.username}
                        </div>
                      <% end %>
                      <%= if length(room.participants) > 5 do %>
                        <div class="badge badge-ghost badge-sm">
                          +{length(room.participants) - 5} more
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
                
    <!-- Action Buttons -->
                <%= if Enum.any?(room.participants, &(&1.user_id == @current_scope.user.id)) do %>
                  <div class="space-y-2">
                    <% current_participant =
                      Enum.find(room.participants, &(&1.user_id == @current_scope.user.id)) %>
                    <% all_ready = Trivia.all_ready?(room.id) %>

                    <%!-- Ready/Play Buttons --%>
                    <%= if room.status == "waiting" do %>
                      <% has_min_players = length(room.participants) >= 2 %>
                      <%= if room.host_id == @current_scope.user.id and all_ready and has_min_players do %>
                        <%!-- Host sees PLAY button when all ready and min 2 players --%>
                        <button
                          phx-click="start_game"
                          phx-value-room-id={room.id}
                          class="btn btn-success w-full rounded-full animate-pulse"
                        >
                          ▶️ START GAME
                        </button>
                      <% else %>
                        <%!-- All players see READY button --%>
                        <button
                          phx-click="toggle_ready"
                          phx-value-room-id={room.id}
                          class={[
                            "btn w-full rounded-full",
                            current_participant.is_ready && "btn-success",
                            !current_participant.is_ready && "btn-outline btn-primary"
                          ]}
                        >
                          <%= if current_participant.is_ready do %>
                            ✓ READY
                          <% else %>
                            ⏱️ READY UP
                          <% end %>
                        </button>
                        
                        <%!-- Show waiting message if host and all ready but not enough players --%>
                        <%= if room.host_id == @current_scope.user.id and all_ready and !has_min_players do %>
                          <div class="text-center text-sm text-warning mt-1">
                            ⚠️ Need at least 2 players to start
                          </div>
                        <% end %>
                      <% end %>
                    <% end %>

                    <%!-- Leave/Delete Button --%>
                    <button
                      phx-click="leave_room"
                      phx-value-room-id={room.id}
                      class="btn btn-outline btn-error w-full rounded-full btn-sm"
                    >
                      <%= if room.host_id == @current_scope.user.id do %>
                        🗑️ Delete Room
                      <% else %>
                        Leave Room
                      <% end %>
                    </button>
                  </div>
                <% else %>
                  <%= if length(room.participants) < room.max_players and room.status == "waiting" do %>
                    <button
                      phx-click="join_room"
                      phx-value-room-id={room.id}
                      class="btn btn-primary w-full rounded-full"
                    >
                      Join Room
                    </button>
                  <% else %>
                    <button class="btn btn-disabled w-full rounded-full" disabled>
                      {if room.status != "waiting", do: "In Progress", else: "Room Full"}
                    </button>
                  <% end %>
                <% end %>
              </div>
            <% end %>
          </div>
          
    <!-- Empty State -->
          <%= if Enum.empty?(@rooms) do %>
            <div class="text-center py-16">
              <div class="text-6xl mb-4">🎮</div>
              <h3 class="text-2xl font-bold text-gray-700 mb-2">No Active Rooms</h3>
              <p class="text-gray-500 mb-6">Be the first to create a trivia battle room!</p>
              <button
                phx-click="toggle_create_form"
                class="btn btn-primary btn-lg rounded-full"
              >
                Create First Room
              </button>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
