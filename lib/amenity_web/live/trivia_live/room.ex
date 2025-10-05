defmodule AmenityWeb.TriviaLive.Room do
  use AmenityWeb, :live_view

  alias Amenity.Trivia
  alias AmenityWeb.Presence
  alias Phoenix.PubSub

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    room = Trivia.get_room!(room_id)
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:room, room)
      |> assign(:room_id, String.to_integer(room_id))
      |> assign(:user, user)
      |> assign(:is_host, room.host_id == user.id)
      |> assign(:players, %{})
      |> assign(:game_status, room.status)
      |> assign(:current_question, nil)
      |> assign(:current_question_index, 0)
      |> assign(:total_questions, 0)
      |> assign(:selected_answer, nil)
      |> assign(:show_results, false)
      |> assign(:results, nil)
      |> assign(:scores, %{})
      |> assign(:final_scores, nil)
      |> assign(:generating_questions, false)
      |> assign(:time_remaining, nil)

    if connected?(socket) do
      # Subscribe to game events
      PubSub.subscribe(Amenity.PubSub, "trivia:#{room_id}")

      # Track presence
      {:ok, _} =
        Presence.track(self(), "trivia:#{room_id}", user.id, %{
          username: user.username,
          joined_at: System.system_time(:second)
        })

      # If user is not the host and joins another room, delete their hosted room
      if room.host_id != user.id do
        Trivia.delete_user_rooms(user.id)
      end

      {:ok, handle_presence_diff(socket)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    if socket.assigns.is_host do
      # Broadcast to all players that questions are being generated
      PubSub.broadcast(Amenity.PubSub, "trivia:#{socket.assigns.room_id}", :generating_questions)
      
      # Show loading state and trigger async generation
      send(self(), :generate_and_start_game)
      {:noreply, assign(socket, :generating_questions, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:generate_and_start_game, socket) do
    # Generate questions (this happens asynchronously)
    case Amenity.Trivia.generate_questions(socket.assigns.room.book, socket.assigns.room.num_questions) do
      {:ok, questions} ->
        # Now start the GameServer with the questions
        case DynamicSupervisor.start_child(
               Amenity.Trivia.GameSupervisor,
               {Amenity.Trivia.GameServer, socket.assigns.room_id}
             ) do
          {:ok, _pid} ->
            case Amenity.Trivia.GameServer.start_game(socket.assigns.room_id, questions) do
              :ok ->
                # Broadcast to all players that generation is done
                PubSub.broadcast(Amenity.PubSub, "trivia:#{socket.assigns.room_id}", :questions_ready)
                {:noreply, assign(socket, :generating_questions, false)}
              {:error, reason} ->
                PubSub.broadcast(Amenity.PubSub, "trivia:#{socket.assigns.room_id}", :questions_ready)
                {:noreply, 
                 socket
                 |> assign(:generating_questions, false)
                 |> put_flash(:error, "Failed to start game: #{inspect(reason)}")}
            end

          {:error, {:already_started, _pid}} ->
            case Amenity.Trivia.GameServer.start_game(socket.assigns.room_id, questions) do
              :ok ->
                PubSub.broadcast(Amenity.PubSub, "trivia:#{socket.assigns.room_id}", :questions_ready)
                {:noreply, assign(socket, :generating_questions, false)}
              {:error, reason} ->
                PubSub.broadcast(Amenity.PubSub, "trivia:#{socket.assigns.room_id}", :questions_ready)
                {:noreply,
                 socket
                 |> assign(:generating_questions, false)
                 |> put_flash(:error, "Failed to start game: #{inspect(reason)}")}
            end

          {:error, reason} ->
            PubSub.broadcast(Amenity.PubSub, "trivia:#{socket.assigns.room_id}", :questions_ready)
            {:noreply,
             socket
             |> assign(:generating_questions, false)
             |> put_flash(:error, "Failed to start game: #{inspect(reason)}")}
        end
      
      {:error, reason} ->
        PubSub.broadcast(Amenity.PubSub, "trivia:#{socket.assigns.room_id}", :questions_ready)
        {:noreply,
         socket
         |> assign(:generating_questions, false)
         |> put_flash(:error, "Failed to generate questions: #{inspect(reason)}")}
    end
  end

  def handle_event("select_answer", %{"index" => index_str}, socket) do
    if socket.assigns.game_status == "playing" && !socket.assigns.selected_answer do
      index = String.to_integer(index_str)

      Amenity.Trivia.GameServer.submit_answer(
        socket.assigns.room_id,
        socket.assigns.user.id,
        index
      )

      {:noreply, assign(socket, :selected_answer, index)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("leave_room", _params, socket) do
    if socket.assigns.is_host do
      # Delete room and kick all users
      Trivia.delete_room(socket.assigns.room)
      PubSub.broadcast(Amenity.PubSub, "trivia:#{socket.assigns.room_id}", :room_deleted)
      PubSub.broadcast(Amenity.PubSub, "trivia:rooms", {:room_deleted, socket.assigns.room_id})
    end

    {:noreply, push_navigate(socket, to: ~p"/study/trivia")}
  end

  @impl true
  def handle_info(%{event: "presence_diff"}, socket) do
    socket = handle_presence_diff(socket)
    
    # Only check for room deletion if room still exists
    if socket.assigns.room do
      cond do
        # If no players left, delete room
        map_size(socket.assigns.players) == 0 ->
          # Try to delete, ignore if already gone
          case Trivia.delete_room(socket.assigns.room) do
            {:ok, _} -> 
              PubSub.broadcast(Amenity.PubSub, "trivia:rooms", {:room_deleted, socket.assigns.room_id})
            {:error, _} -> :ok
          end
          
          {:noreply, 
           socket
           |> assign(:room, nil)  # Mark as deleted
           |> put_flash(:info, "Room closed - no players remaining")
           |> push_navigate(to: ~p"/study/trivia")}
        
        # If host left but others remain, delete room and kick everyone (only check in waiting state)
        socket.assigns.game_status == "waiting" && 
        not Map.has_key?(socket.assigns.players, socket.assigns.room.host_id) ->
          # Try to delete, ignore if already gone
          case Trivia.delete_room(socket.assigns.room) do
            {:ok, _} ->
              PubSub.broadcast(Amenity.PubSub, "trivia:#{socket.assigns.room_id}", :room_deleted)
              PubSub.broadcast(Amenity.PubSub, "trivia:rooms", {:room_deleted, socket.assigns.room_id})
            {:error, _} -> :ok
          end
          
          {:noreply, 
           socket
           |> assign(:room, nil)  # Mark as deleted
           |> put_flash(:info, "Room closed - host has left")
           |> push_navigate(to: ~p"/study/trivia")}
        
        true ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end
  def handle_info({:game_started, %{questions_count: count}}, socket) do
    {:noreply,
     socket
     |> assign(:game_status, "playing")
     |> assign(:total_questions, count)}
  end

  def handle_info({:show_question, question_data}, socket) do
    {:noreply,
     socket
     |> assign(:current_question, question_data)
     |> assign(:current_question_index, question_data.index)
     |> assign(:selected_answer, nil)
     |> assign(:show_results, false)
     |> assign(:time_remaining, question_data.time_remaining)}
  end

  def handle_info({:time_update, %{time_remaining: time}}, socket) do
    {:noreply, assign(socket, :time_remaining, time)}
  end

  def handle_info({:show_results, results_data}, socket) do
    {:noreply,
     socket
     |> assign(:show_results, true)
     |> assign(:results, results_data)
     |> assign(:scores, results_data.scores)}
  end

  def handle_info({:game_ended, %{scores: final_scores}}, socket) do
    {:noreply,
     socket
     |> assign(:game_status, "finished")
     |> assign(:final_scores, final_scores)}
  end

  def handle_info(:generating_questions, socket) do
    {:noreply, assign(socket, :generating_questions, true)}
  end

  def handle_info(:questions_ready, socket) do
    {:noreply, assign(socket, :generating_questions, false)}
  end

  def handle_info(:room_deleted, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Room was closed by the host")
     |> push_navigate(to: ~p"/study/trivia")}
  end

  @impl true
  def terminate(_reason, socket) do
    # If host leaves, delete the room
    if socket.assigns.is_host && socket.assigns.room do
      Trivia.delete_room(socket.assigns.room)
      PubSub.broadcast(Amenity.PubSub, "trivia:#{socket.assigns.room_id}", :room_deleted)
      PubSub.broadcast(Amenity.PubSub, "trivia:rooms", {:room_deleted, socket.assigns.room_id})
    end

    :ok
  end

  defp handle_presence_diff(socket) do
    players =
      Presence.list("trivia:#{socket.assigns.room_id}")
      |> Enum.map(fn {user_id, %{metas: [meta | _]}} ->
        {String.to_integer(user_id), meta}
      end)
      |> Map.new()

    assign(socket, :players, players)
  end

  defp is_winner?(final_scores, user_id) do
    case Enum.sort_by(final_scores, fn {_, score} -> -score end) do
      [{winner_id, _} | _] -> winner_id == user_id
      _ -> false
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-purple-50 via-pink-50 to-orange-50">
      <div class="max-w-6xl mx-auto px-4 py-8">
        <!-- Header -->
        <div class="mb-6 flex justify-between items-center">
          <div>
            <h1 class="text-3xl font-bold text-gray-800">{@room.name}</h1>
            <p class="text-gray-800">
              {@room.book} • {@room.num_questions} questions
            </p>
          </div>
          <button phx-click="leave_room" class="btn btn-ghost">
            ← Leave Room
          </button>
        </div>

        <%= if @game_status == "waiting" do %>
          <!-- Waiting Room -->
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <!-- Players List -->
            <div class="lg:col-span-2">
              <div class="bg-white rounded-3xl p-8 shadow-xl">
                <h2 class="text-2xl font-bold text-gray-800 mb-6">
                  Players ({map_size(@players)})
                </h2>

                <div class="space-y-3">
                  <%= for {user_id, player} <- @players do %>
                    <div class="flex items-center gap-3 p-4 bg-gradient-to-r from-purple-50 to-pink-50 rounded-xl">
                      <div class="w-12 h-12 bg-gradient-to-br from-purple-500 to-pink-500 rounded-full flex items-center justify-center text-white font-bold text-xl">
                        {String.first(player.username)}
                      </div>
                      <div class="flex-1">
                        <p class="font-semibold text-gray-800">{player.username}</p>
                        <%= if user_id == @room.host_id do %>
                          <span class="text-xs bg-yellow-400 text-yellow-900 px-2 py-1 rounded-full">
                            👑 Host
                          </span>
                        <% end %>
                      </div>
                      <!-- Animated waiting indicator -->
                      <div class="flex gap-1">
                        <div
                          class="w-2 h-2 bg-purple-500 rounded-full animate-bounce"
                          style="animation-delay: 0ms"
                        >
                        </div>
                        <div
                          class="w-2 h-2 bg-pink-500 rounded-full animate-bounce"
                          style="animation-delay: 150ms"
                        >
                        </div>
                        <div
                          class="w-2 h-2 bg-orange-500 rounded-full animate-bounce"
                          style="animation-delay: 300ms"
                        >
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
            <!-- Game Info & Start -->
            <div class="space-y-6">
              <div class="bg-gradient-to-br from-purple-100 to-pink-100 rounded-3xl p-6 shadow-xl border-2 border-purple-300">
                <h3 class="font-bold text-purple-900 mb-4 text-lg">🎮 Game Settings</h3>
                <div class="space-y-3">
                  <div class="flex justify-between items-center p-3 bg-white/80 rounded-xl">
                    <span class="text-purple-700 font-semibold">📖 Book:</span>
                    <span class="font-bold text-purple-900">{@room.book}</span>
                  </div>
                  <div class="flex justify-between items-center p-3 bg-white/80 rounded-xl">
                    <span class="text-pink-700 font-semibold">❓ Questions:</span>
                    <span class="font-bold text-pink-900">{@room.num_questions}</span>
                  </div>
                  <div class="flex justify-between items-center p-3 bg-white/80 rounded-xl">
                    <span class="text-orange-700 font-semibold">👥 Players:</span>
                    <span class="font-bold text-orange-900">{map_size(@players)}</span>
                  </div>
                </div>
              </div>

              <%= if @is_host do %>
                <button
                  phx-click="start_game"
                  class="btn btn-primary btn-lg w-full rounded-full"
                  disabled={map_size(@players) < 1 || @generating_questions}
                >
                  <%= if @generating_questions do %>
                    <span class="loading loading-spinner"></span> Generating Questions...
                  <% else %>
                    🚀 Start Game
                  <% end %>
                </button>
              <% else %>
                <div class="bg-yellow-50 border-2 border-yellow-400 rounded-2xl p-4 text-center">
                  <p class="text-yellow-800 font-semibold">Waiting for host to start...</p>
                  <div class="mt-2 flex justify-center gap-2">
                    <div class="w-3 h-3 bg-yellow-500 rounded-full animate-pulse"></div>
                    <div
                      class="w-3 h-3 bg-yellow-500 rounded-full animate-pulse"
                      style="animation-delay: 200ms"
                    >
                    </div>
                    <div
                      class="w-3 h-3 bg-yellow-500 rounded-full animate-pulse"
                      style="animation-delay: 400ms"
                    >
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if @game_status == "playing" do %>
          <!-- Game Play -->
          <div class="space-y-6">
            <!-- Progress Bar -->
            <div class="bg-white rounded-2xl p-4 shadow-lg">
              <div class="flex justify-between items-center mb-2">
                <span class="text-sm font-semibold text-gray-800">
                  Question {@current_question_index + 1} of {@total_questions}
                </span>
                <span class="text-sm font-semibold text-purple-600">
                  Score: {Map.get(@scores, @user.id, 0)}
                </span>
              </div>
              <div class="w-full bg-gray-200 rounded-full h-3">
                <div
                  class="bg-gradient-to-r from-purple-500 to-pink-500 h-3 rounded-full transition-all"
                  style={"width: #{(@current_question_index + 1) / @total_questions * 100}%"}
                >
                </div>
              </div>
            </div>

            <%= if @current_question && !@show_results do %>
              <!-- Question -->
              <div class="bg-white rounded-3xl p-12 shadow-2xl animate-fade-in">
                <!-- Countdown Timer -->
                <div class="flex justify-center mb-6">
                  <div class={"flex items-center justify-center w-20 h-20 rounded-full text-3xl font-bold #{if @time_remaining && @time_remaining <= 5, do: "bg-red-500 text-white animate-pulse", else: "bg-purple-500 text-white"}"}>
                    {@time_remaining || 20}
                  </div>
                </div>
                
                <h2 class="text-3xl font-bold text-gray-800 text-center mb-8">
                  {@current_question.question}
                </h2>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <%= for {option, index} <- Enum.with_index(@current_question.options) do %>
                    <button
                      phx-click="select_answer"
                      phx-value-index={index}
                      disabled={@selected_answer != nil}
                      class={"btn btn-lg h-auto py-6 text-left justify-start transition-all #{if @selected_answer == index, do: "bg-yellow-500 hover:bg-yellow-600 border-yellow-500", else: "bg-white hover:bg-purple-50 border-2 border-purple-400 hover:border-purple-600 font-semibold"}"}
                    >
                      <span class={"font-bold mr-3 text-xl #{if @selected_answer == index, do: "text-gray-900", else: "text-gray-800"}"}>
                        {["A", "B", "C", "D"] |> Enum.at(index)}.
                      </span>
                      <span class={if @selected_answer == index, do: "text-gray-900", else: "text-gray-800"}>{option}</span>
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%= if @show_results && @results do %>
              <!-- Results -->
              <div class="bg-white rounded-3xl p-12 shadow-2xl animate-fade-in">
                <div class="text-center mb-8">
                  <%= if Map.get(@results.player_answers, @user.id) && Map.get(@results.player_answers, @user.id).answer == @results.correct_answer do %>
                    <div class="text-6xl mb-4">🎉</div>
                    <h2 class="text-3xl font-bold text-green-600">Correct!</h2>
                  <% else %>
                    <div class="text-6xl mb-4">😅</div>
                    <h2 class="text-3xl font-bold text-red-600">Incorrect</h2>
                  <% end %>
                </div>

                <div class="bg-blue-50 border-2 border-blue-400 rounded-2xl p-6 mb-6">
                  <p class="text-sm font-semibold text-blue-800 mb-2">Correct Answer:</p>
                  <p class="text-lg text-blue-900">
                    {Enum.at(@current_question.options, @results.correct_answer)}
                  </p>
                  <%= if @results.explanation do %>
                    <p class="text-sm text-blue-700 mt-2">{@results.explanation}</p>
                  <% end %>
                </div>
                <!-- Leaderboard -->
                <div>
                  <h3 class="font-bold text-gray-900 mb-4">Current Standings</h3>
                  <div class="space-y-2">
                    <%= for {{user_id, score}, rank} <- @results.scores |> Enum.sort_by(fn {_, s} -> -s end) |> Enum.with_index(1) do %>
                      <div class="flex items-center gap-3 p-3 bg-gray-50 rounded-xl">
                        <span class="text-2xl font-bold text-gray-700">#{rank}</span>
                        <span class="flex-1 font-semibold text-gray-900">
                          {Map.get(@players, user_id, %{username: "Unknown"}).username}
                        </span>
                        <span class="font-bold text-purple-600">{score}</span>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>

        <%= if @game_status == "finished" && @final_scores do %>
          <!-- Achievement Notification -->
          <%= if is_winner?(@final_scores, @user.id) do %>
            <div class="fixed top-20 right-8 z-50 animate-slide-in-right">
              <div class="bg-gradient-to-r from-yellow-400 via-orange-400 to-yellow-400 rounded-2xl p-6 shadow-2xl border-4 border-yellow-500 max-w-sm animate-bounce-in">
                <div class="flex items-center gap-4">
                  <div class="text-6xl">🏆</div>
                  <div class="text-left">
                    <p class="text-sm font-bold text-yellow-900 mb-1">ACHIEVEMENT UNLOCKED!</p>
                    <p class="text-lg font-bold text-white">First Victory</p>
                    <p class="text-sm text-yellow-100">Win your first trivia battle</p>
                  </div>
                </div>
              </div>
            </div>
          <% end %>

          <!-- Final Results -->
          <div class="bg-white rounded-3xl p-12 shadow-2xl text-center">
            <div class="text-8xl mb-6">🏆</div>
            <h1 class="text-4xl font-bold text-gray-800 mb-8">Game Over!</h1>

            <div class="max-w-md mx-auto space-y-3">
              <%= for {{user_id, score}, rank} <- @final_scores |> Enum.sort_by(fn {_, s} -> -s end) |> Enum.with_index(1) do %>
                <div class={"flex items-center gap-4 p-4 rounded-2xl #{if rank == 1, do: "bg-gradient-to-r from-yellow-400 to-orange-400", else: "bg-gray-100"}"}>
                  <span class={"text-3xl #{if rank == 1, do: "animate-bounce"}"}>
                    {if rank == 1, do: "👑", else: "#{rank}"}
                  </span>
                  <span class={"flex-1 font-bold text-lg #{if rank == 1, do: "text-white", else: "text-gray-800"}"}>
                    {Map.get(@players, user_id, %{username: "Unknown"}).username}
                  </span>
                  <span class={"font-bold text-2xl #{if rank == 1, do: "text-white", else: "text-purple-600"}"}>
                    {score}
                  </span>
                </div>
              <% end %>
            </div>

            <div class="mt-8 flex gap-4 justify-center">
              <.link navigate={~p"/study/trivia"} class="btn btn-primary btn-lg rounded-full">
                Back to Rooms
              </.link>
            </div>
          </div>
        <% end %>

        <!-- Generating Questions Overlay -->
        <%= if @generating_questions do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-70">
            <div class="bg-white rounded-3xl p-12 text-center shadow-2xl max-w-md mx-4">
              <div class="text-6xl mb-4 animate-bounce">🤖</div>
              <h2 class="text-3xl font-bold text-gray-800 mb-3">Generating Questions...</h2>
              <p class="text-gray-900 mb-6">Our AI is creating trivia questions about {@room.book}</p>
              <div class="flex justify-center gap-2">
                <div class="w-3 h-3 bg-purple-500 rounded-full animate-bounce" style="animation-delay: 0ms"></div>
                <div class="w-3 h-3 bg-pink-500 rounded-full animate-bounce" style="animation-delay: 150ms"></div>
                <div class="w-3 h-3 bg-orange-500 rounded-full animate-bounce" style="animation-delay: 300ms"></div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>

    <style>
      @keyframes fade-in {
        from {
          opacity: 0;
          transform: translateY(20px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }

      .animate-fade-in {
        animation: fade-in 0.5s ease-out;
      }

      @keyframes slide-in-right {
        from {
          opacity: 0;
          transform: translateX(100%);
        }
        to {
          opacity: 1;
          transform: translateX(0);
        }
      }

      @keyframes bounce-in {
        0% {
          transform: scale(0.3);
          opacity: 0;
        }
        50% {
          transform: scale(1.05);
        }
        70% {
          transform: scale(0.9);
        }
        100% {
          transform: scale(1);
          opacity: 1;
        }
      }

      .animate-slide-in-right {
        animation: slide-in-right 0.6s ease-out;
      }

      .animate-bounce-in {
        animation: bounce-in 0.8s cubic-bezier(0.68, -0.55, 0.265, 1.55);
      }
    </style>
    """
  end
end
