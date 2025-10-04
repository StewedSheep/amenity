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
      |> assign(:questions, [])
      |> assign(:current_question_index, 0)
      |> assign(:current_question, nil)
      |> assign(:player_scores, %{})

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
    # Get all online user IDs from presence
    online_user_ids =
      Presence.list("trivia:lobby")
      |> Map.keys()
      |> Enum.map(&String.to_integer/1)
    
    case Trivia.create_room(socket.assigns.current_scope, room_params, online_user_ids) do
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
        # Subscribe to room-specific topic for game updates
        Phoenix.PubSub.subscribe(Amenity.PubSub, "trivia:room:#{room_id}")
        
        Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", :room_updated)
        rooms = Trivia.list_rooms(socket.assigns.current_scope)

        socket =
          socket
          |> assign(:rooms, rooms)
          |> assign(:current_room_id, room_id)
          |> put_flash(:info, "Joined room successfully!")

        {:noreply, socket}

      {:error, :not_allowed} ->
        {:noreply, put_flash(socket, :error, "You are not allowed to join this room. Only players who were online when the room was created can join.")}

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
    room = Enum.find(socket.assigns.rooms, &(&1.id == room_id))
    
    unless room do
      {:noreply, put_flash(socket, :error, "Room not found")}
    else
      participant_ids = Enum.map(room.participants, & &1.user_id)
      
      # First, generate questions via OpenAI
      case Amenity.Trivia.QuestionGenerator.generate_questions(
             room.book_of_moses,
             room.question_count,
             room.difficulty
           ) do
        {:ok, questions} ->
          # AFTER questions are ready, start the GameServer
          case Trivia.start_game_server(room_id) do
            {:ok, _pid} ->
              room_data = %{
                book_of_moses: room.book_of_moses,
                question_count: room.question_count,
                difficulty: room.difficulty,
                participant_ids: participant_ids
              }
              
              # Tell GameServer to start with pre-generated questions
              case Amenity.Trivia.GameServer.start_game(room_id, room_data, questions) do
                {:ok, _questions} ->
                  Trivia.start_game(socket.assigns.current_scope, room_id)
                  
                  # Subscribe to room-specific GameServer broadcasts
                  Phoenix.PubSub.subscribe(Amenity.PubSub, "trivia:room:#{room_id}")
                  
                  socket =
                    socket
                    |> assign(:current_room_id, room_id)
                    |> assign(:game_state, :countdown)
                    |> assign(:countdown, 3)
                    |> assign(:questions, questions)
                    |> assign(:current_question_index, 0)
                    |> assign(:player_scores, Map.new(participant_ids, fn id -> {id, 0} end))
                  
                  {:noreply, socket}
                
                {:error, reason} ->
                  {:noreply, put_flash(socket, :error, "Failed to start game: #{inspect(reason)}")}
              end
            
            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Failed to start game server: #{inspect(reason)}")}
          end
        
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to generate questions: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("answer_question", %{"room-id" => room_id, "answer-index" => answer_index}, socket) do
    room_id = String.to_integer(room_id)
    answer_index = String.to_integer(answer_index)
    time_remaining = socket.assigns.question_timer || 0
    
    # Tell GameServer about the answer (it calculates points and manages state)
    Amenity.Trivia.GameServer.answer_question(
      room_id,
      socket.assigns.current_scope.user.id,
      answer_index,
      time_remaining
    )
    
    # Update database
    current_question = socket.assigns.current_question
    is_correct = answer_index == current_question["correct_answer"]
    Trivia.record_answer(socket.assigns.current_scope, room_id, is_correct)
    
    # Update local UI state
    socket = assign(socket, :game_state, :answered)
    
    {:noreply, socket}
  end

  defp calculate_points(time_remaining) do
    max(10, min(100, 10 + trunc(time_remaining * 9)))
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
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    online_users =
      Presence.list("trivia:lobby")
      |> Map.values()
      |> Enum.map(fn data ->
        data[:metas]
        |> List.first()
      end)
      |> Enum.reject(&is_nil/1)

    # Check for users who left (in the leaves map)
    if map_size(diff.leaves) > 0 do
      Enum.each(diff.leaves, fn {user_id_str, _} ->
        user_id = String.to_integer(user_id_str)
        # Disband any rooms hosted by users who left
        Trivia.disband_user_hosted_rooms(user_id)
      end)
      
      # Broadcast room update to refresh everyone's list
      Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", :room_updated)
    end

    {:noreply, assign(socket, :online_users, online_users)}
  end

  @impl true
  def handle_info(:room_updated, socket) do
    rooms = Trivia.list_rooms(socket.assigns.current_scope)
    {:noreply, assign(socket, :rooms, rooms)}
  end

  @impl true
  def handle_info({:game_started, questions, countdown}, socket) do
    # This comes from GameServer on room-specific topic
    # Subscribe to the room-specific topic to receive game updates
    participant_ids = Enum.map(socket.assigns.rooms, fn room ->
      if Enum.any?(room.participants, &(&1.user_id == socket.assigns.current_scope.user.id)) do
        room.participants |> Enum.map(& &1.user_id)
      else
        []
      end
    end) |> List.flatten() |> Enum.uniq()
    
    player_scores = Map.new(participant_ids, fn id -> {id, 0} end)
    
    socket =
      socket
      |> assign(:game_state, :countdown)
      |> assign(:countdown, countdown)
      |> assign(:questions, questions)
      |> assign(:current_question_index, 0)
      |> assign(:player_scores, player_scores)
    
    {:noreply, socket}
  end

  # GameServer broadcasts - LiveView just listens and updates UI
  
  @impl true
  def handle_info({:game_tick, :countdown, value}, socket) do
    {:noreply, assign(socket, :countdown, value)}
  end

  @impl true
  def handle_info({:game_tick, :question, timer_value, player_scores}, socket) do
    socket =
      socket
      |> assign(:question_timer, timer_value)
      |> assign(:player_scores, player_scores)
    
    {:noreply, socket}
  end

  @impl true
  def handle_info({:show_question, question, index, timer_value, player_scores}, socket) do
    socket =
      socket
      |> assign(:game_state, :question)
      |> assign(:countdown, nil)
      |> assign(:current_question, question)
      |> assign(:current_question_index, index)
      |> assign(:question_timer, timer_value)
      |> assign(:player_scores, player_scores)
      |> assign(:answered_users, MapSet.new())
    
    {:noreply, socket}
  end

  @impl true
  def handle_info({:player_answered, user_id, points, player_scores}, socket) do
    # GameServer broadcasts when someone answers
    answered_users = MapSet.put(socket.assigns.answered_users, user_id)
    
    socket =
      socket
      |> assign(:answered_users, answered_users)
      |> assign(:player_scores, player_scores)
    
    {:noreply, socket}
  end

  @impl true
  def handle_info({:game_over, winners, player_scores}, socket) do
    # GameServer broadcasts game over with winners and final scores
    # Update database
    if socket.assigns.current_room_id do
      Trivia.end_game(socket.assigns.current_scope, socket.assigns.current_room_id)
    end
    
    # Get room to map user IDs to user objects
    room = Enum.find(socket.assigns.rooms, &(&1.id == socket.assigns.current_room_id))
    
    # Map winners to include user objects
    winners_with_users = Enum.map(winners, fn %{user_id: user_id, score: score} ->
      participant = Enum.find(room.participants, &(&1.user_id == user_id))
      %{user_id: user_id, user: participant.user, score: score}
    end)
    
    socket =
      socket
      |> assign(:game_state, :results)
      |> assign(:winners, winners_with_users)
      |> assign(:player_scores, player_scores)
    
    Phoenix.PubSub.broadcast(Amenity.PubSub, "trivia:lobby", :room_updated)
    
    {:noreply, socket}
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
                <div class="bg-white rounded-3xl p-12 max-w-4xl">
                  <%!-- Question Header --%>
                  <div class="flex justify-between items-start mb-6">
                    <div class="flex-1">
                      <div class="text-sm text-gray-500 mb-2">
                        Question {@current_question_index + 1} of {length(@questions)}
                      </div>
                      <h2 class="text-3xl font-bold text-gray-800">{@current_question["question"]}</h2>
                    </div>
                    <div class="text-4xl font-bold text-purple-600 ml-4">
                      ⏱️ {@question_timer}s
                    </div>
                  </div>
                  
                  <%!-- Score Display --%>
                  <div class="mb-6 p-4 bg-purple-50 rounded-xl">
                    <div class="text-sm font-semibold text-purple-800 mb-2">Current Scores:</div>
                    <div class="flex flex-wrap gap-3">
                      <%= for {user_id, score} <- Enum.sort_by(@player_scores, fn {_, s} -> -s end) do %>
                        <% room = Enum.find(@rooms, &(&1.id == @current_room_id)) %>
                        <% participant = Enum.find(room.participants, &(&1.user_id == user_id)) %>
                        <div class={[
                          "badge badge-lg gap-2",
                          user_id == @current_scope.user.id && "badge-primary"
                        ]}>
                          <span>{participant.user.username}</span>
                          <span class="font-bold">{score} pts</span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                  
                  <%!-- Answer Options --%>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <%= for {option, index} <- Enum.with_index(@current_question["options"]) do %>
                      <button
                        phx-click="answer_question"
                        phx-value-room-id={@current_room_id}
                        phx-value-answer-index={index}
                        class="btn btn-lg btn-outline w-full text-left justify-start h-auto py-4 px-6 rounded-2xl hover:scale-105 transition-transform"
                      >
                        <span class="font-bold mr-3">{String.at("ABCD", index)}.</span>
                        <span class="text-lg">{option}</span>
                      </button>
                    <% end %>
                  </div>
                  
                  <%!-- Points Info --%>
                  <div class="mt-6 text-center text-sm text-gray-500">
                    💡 Answer quickly! Points: {calculate_points(@question_timer)} (max 100, min 10)
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
                      <p class="text-2xl text-gray-600 mb-4">Final Score: {hd(@winners).score} points</p>
                      <p class="text-xl text-gray-500">Congratulations, champion!</p>
                    <% else %>
                      <p class="text-3xl mb-4">It's a tie!</p>
                      <p class="text-2xl text-gray-600 mb-4">Final Score: {hd(@winners).score} points</p>
                      <div class="space-y-2">
                        <%= for winner <- @winners do %>
                          <p class="text-2xl font-bold text-purple-600">{winner.user.username}</p>
                        <% end %>
                      </div>
                    <% end %>
                  <% else %>
                    <h2 class="text-5xl font-bold mb-8 text-red-600">💀 You Lost 💀</h2>
                    <p class="text-3xl font-bold text-gray-800 mb-4">You are bad and you lost.</p>
                    <p class="text-xl text-gray-600 mb-2">Your score: {Map.get(@player_scores, @current_scope.user.id, 0)} points</p>
                    <p class="text-lg text-gray-500 mb-6">Maybe try being better next time? 🤷</p>
                    
                    <div class="border-t-2 border-gray-200 pt-6 mt-6">
                      <%= if length(@winners) == 1 do %>
                        <p class="text-2xl mb-2 text-gray-600">Winner:</p>
                        <p class="text-3xl font-bold text-purple-600">{hd(@winners).user.username}</p>
                        <p class="text-xl text-gray-500">{hd(@winners).score} points</p>
                      <% else %>
                        <p class="text-2xl mb-2 text-gray-600">Winners:</p>
                        <div class="space-y-2">
                          <%= for winner <- @winners do %>
                            <div>
                              <p class="text-2xl font-bold text-purple-600">{winner.user.username}</p>
                              <p class="text-lg text-gray-500">{winner.score} points</p>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                  
                  <%!-- Final Leaderboard --%>
                  <div class="border-t-2 border-gray-200 pt-6 mt-6">
                    <p class="text-xl font-bold text-gray-700 mb-4">Final Leaderboard:</p>
                    <div class="space-y-2">
                      <%= for {{user_id, score}, rank} <- Enum.sort_by(@player_scores, fn {_, s} -> -s end) |> Enum.with_index(1) do %>
                        <% room = Enum.find(@rooms, &(&1.id == @current_room_id)) %>
                        <% participant = Enum.find(room.participants, &(&1.user_id == user_id)) %>
                        <div class={[
                          "flex justify-between items-center p-3 rounded-lg",
                          user_id == @current_scope.user.id && "bg-purple-100"
                        ]}>
                          <div class="flex items-center gap-3">
                            <span class="text-2xl font-bold text-gray-400">#{rank}</span>
                            <span class="font-semibold">{participant.user.username}</span>
                          </div>
                          <span class="font-bold text-purple-600">{score} pts</span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                  
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

                  <.input
                    field={@form[:book_of_moses]}
                    type="select"
                    label="Book of Moses"
                    options={[
                      {"Genesis", "Genesis"},
                      {"Exodus", "Exodus"},
                      {"Leviticus", "Leviticus"},
                      {"Numbers", "Numbers"},
                      {"Deuteronomy", "Deuteronomy"}
                    ]}
                  />

                  <.input
                    field={@form[:question_count]}
                    type="number"
                    label="Number of Questions"
                    min="1"
                    max="10"
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
