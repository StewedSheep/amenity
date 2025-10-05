defmodule Amenity.Trivia.GameServer do
  use GenServer
  require Logger

  alias Amenity.Trivia
  alias Phoenix.PubSub

  @question_time 20_000  # 20 seconds per question
  @results_time 5_000    # 5 seconds to show results

  # Client API

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via_tuple(room_id))
  end

  def start_game(room_id, questions) do
    GenServer.call(via_tuple(room_id), {:start_game, questions})
  end

  def submit_answer(room_id, user_id, answer_index) do
    GenServer.cast(via_tuple(room_id), {:submit_answer, user_id, answer_index})
  end

  def get_state(room_id) do
    GenServer.call(via_tuple(room_id), :get_state)
  end

  defp via_tuple(room_id) do
    {:via, Registry, {Amenity.Trivia.GameRegistry, room_id}}
  end

  # Server Callbacks

  @impl true
  def init(room_id) do
    room = Trivia.get_room!(room_id)
    
    state = %{
      room_id: room_id,
      room: room,
      questions: [],
      current_question_index: 0,
      player_answers: %{},
      scores: %{},
      status: "waiting",
      player_ids: [],
      question_timer: nil,
      question_start_time: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_game, questions}, _from, state) do
    # Check if room still exists
    case Trivia.get_room(state.room_id) do
      nil ->
        {:reply, {:error, :room_deleted}, state}
      
      fresh_room ->
        # Try to update room status with retry on stale entry
        case try_update_room(fresh_room, %{status: "playing", questions: %{data: questions}}, 3) do
          {:ok, _} ->
            new_state = %{state | 
              questions: questions,
              status: "playing",
              current_question_index: 0
            }

            # Broadcast game started
            broadcast(state.room_id, {:game_started, %{questions_count: length(questions)}})
            
            # Start first question
            schedule_next_question(0)

            {:reply, :ok, new_state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:submit_answer, user_id, answer_index}, state) do
    # Record answer with timestamp
    timestamp = System.monotonic_time(:millisecond)
    
    player_answers = Map.put(state.player_answers, user_id, %{
      answer: answer_index,
      timestamp: timestamp
    })

    new_state = %{state | player_answers: player_answers}

    # Check if all players have answered
    if map_size(player_answers) == length(state.player_ids) do
      # Cancel the existing timer
      if state.question_timer do
        Process.cancel_timer(state.question_timer)
      end
      
      # Immediately end the question
      send(self(), :end_question)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:show_question, state) do
    question = Enum.at(state.questions, state.current_question_index)
    
    # Get current player IDs from Presence
    player_ids = 
      AmenityWeb.Presence.list("trivia:#{state.room_id}")
      |> Map.keys()
      |> Enum.map(&String.to_integer/1)
    
    # Broadcast current question (without correct answer)
    broadcast(state.room_id, {:show_question, %{
      index: state.current_question_index,
      question: question["question"],
      options: question["options"],
      total: length(state.questions),
      time_remaining: div(@question_time, 1000)
    }})

    # Schedule end of question and store the timer reference
    timer_ref = Process.send_after(self(), :end_question, @question_time)
    
    # Start countdown ticker
    Process.send_after(self(), :tick, 1000)

    {:noreply, %{state | 
      player_ids: player_ids, 
      question_timer: timer_ref,
      question_start_time: System.monotonic_time(:millisecond)
    }}
  end

  @impl true
  def handle_info(:tick, state) do
    # Calculate time remaining
    elapsed = System.monotonic_time(:millisecond) - state.question_start_time
    time_remaining = max(0, div(@question_time - elapsed, 1000))
    
    # Broadcast time update
    if time_remaining > 0 do
      broadcast(state.room_id, {:time_update, %{time_remaining: time_remaining}})
      # Schedule next tick
      Process.send_after(self(), :tick, 1000)
    end
    
    {:noreply, state}
  end

  @impl true
  def handle_info(:end_question, state) do
    question = Enum.at(state.questions, state.current_question_index)
    correct_answer = question["correct_answer"]

    # Calculate scores
    new_scores = calculate_scores(state.player_answers, correct_answer, state.scores, state.question_start_time)

    # Broadcast results
    broadcast(state.room_id, {:show_results, %{
      correct_answer: correct_answer,
      explanation: question["explanation"],
      player_answers: state.player_answers,
      scores: new_scores
    }})

    # Clear answers and timer for next question
    new_state = %{state | 
      player_answers: %{},
      scores: new_scores,
      question_timer: nil
    }

    # Schedule next question or end game
    next_index = state.current_question_index + 1
    
    if next_index < length(state.questions) do
      schedule_next_question(next_index)
      {:noreply, %{new_state | current_question_index: next_index}}
    else
      Process.send_after(self(), :end_game, @results_time)
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:end_game, state) do
    # Try to reload room and update status
    case Trivia.get_room(state.room_id) do
      nil ->
        # Room was deleted, just broadcast game ended
        broadcast(state.room_id, {:game_ended, %{scores: state.scores}})
      
      fresh_room ->
        # Update room status
        Trivia.update_room(fresh_room, %{status: "finished"})
        # Broadcast game ended with final scores
        broadcast(state.room_id, {:game_ended, %{scores: state.scores}})
    end

    {:noreply, %{state | status: "finished"}}
  end

  # Private Functions

  defp try_update_room(_room, _attrs, 0), do: {:error, :max_retries}
  
  defp try_update_room(room, attrs, retries_left) do
    case Trivia.update_room(room, attrs) do
      {:ok, updated_room} ->
        {:ok, updated_room}
      
      {:error, %Ecto.Changeset{errors: errors}} ->
        # Check if it's a stale entry error
        if Keyword.has_key?(errors, :updated_at) do
          # Reload and retry
          case Trivia.get_room(room.id) do
            nil -> {:error, :room_deleted}
            fresh_room -> try_update_room(fresh_room, attrs, retries_left - 1)
          end
        else
          {:error, :update_failed}
        end
      
      error ->
        error
    end
  end

  defp schedule_next_question(index) do
    Process.send_after(self(), :show_question, if(index == 0, do: 3000, else: @results_time))
  end

  defp calculate_scores(player_answers, correct_answer, current_scores, question_start_time) do
    Enum.reduce(player_answers, current_scores, fn {user_id, answer_data}, scores ->
      current_score = Map.get(scores, user_id, 0)
      
      if answer_data.answer == correct_answer do
        # Award points based on speed: 500-1000 points
        # Calculate elapsed time from when question started
        elapsed_time = answer_data.timestamp - question_start_time
        
        # Faster answers get more points (500 bonus for instant, 0 bonus for 20 seconds)
        # Clamp elapsed time to question duration
        clamped_elapsed = min(elapsed_time, @question_time)
        speed_bonus = div((@question_time - clamped_elapsed) * 500, @question_time)
        points = 500 + speed_bonus
        
        Map.put(scores, user_id, current_score + points)
      else
        scores
      end
    end)
  end

  defp broadcast(room_id, message) do
    PubSub.broadcast(Amenity.PubSub, "trivia:#{room_id}", message)
  end
end
