defmodule Amenity.Trivia do
  @moduledoc """
  The Trivia context for managing trivia battles.
  """

  import Ecto.Query
  alias Amenity.Repo
  alias Amenity.Trivia.Room
  alias Amenity.Trivia.GameStats

  @doc """
  Lists all active trivia rooms.
  """
  def list_active_rooms do
    Room
    |> where([r], r.status in ["waiting", "playing"])
    |> preload(:host)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single room.
  """
  def get_room!(id) do
    Room
    |> preload(:host)
    |> Repo.get!(id)
  end

  @doc """
  Gets a single room, returns nil if not found.
  """
  def get_room(id) do
    Room
    |> preload(:host)
    |> Repo.get(id)
  end

  @doc """
  Creates a room.
  """
  def create_room(attrs \\ %{}) do
    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a room.
  """
  def update_room(%Room{} = room, attrs) do
    room
    |> Room.changeset(attrs)
    |> Repo.update(stale_error_field: :updated_at)
  end

  @doc """
  Deletes a room.
  """
  def delete_room(%Room{} = room) do
    Repo.delete(room)
  end

  @doc """
  Deletes all rooms hosted by a user.
  """
  def delete_user_rooms(user_id) do
    from(r in Room, where: r.host_id == ^user_id)
    |> Repo.delete_all()
  end

  @doc """
  Generates trivia questions using OpenAI.
  """
  def generate_questions(book, num_questions) do
    api_key = System.get_env("OPENAI_API_KEY")

    if !api_key do
      {:error, "OpenAI API key not configured"}
    else
      prompt = """
      Create #{num_questions} multiple choice trivia questions about the book of #{book} from the Bible.
      
      REQUIREMENTS:
      - Each question should have 4 answer options (A, B, C, D)
      - Only ONE answer should be correct
      - Questions should test knowledge of specific events, people, and details
      - Mix difficulty levels
      - Include verse references when relevant
      
      Return ONLY a JSON array of objects with this structure:
      [
        {
          "question": "Question text here?",
          "options": ["Option A", "Option B", "Option C", "Option D"],
          "correct_answer": 0,
          "explanation": "Brief explanation with verse reference"
        }
      ]
      
      The correct_answer is the index (0-3) of the correct option.
      """

      body = %{
        model: "gpt-4o-mini",
        messages: [
          %{role: "system", content: "You are a Bible trivia expert that creates engaging multiple choice questions."},
          %{role: "user", content: prompt}
        ],
        temperature: 0.8
      }

      case Req.post("https://api.openai.com/v1/chat/completions",
             json: body,
             headers: [{"Authorization", "Bearer #{api_key}"}]
           ) do
        {:ok, %{status: 200, body: response_body}} ->
          content = get_in(response_body, ["choices", Access.at(0), "message", "content"])

          case Jason.decode(content) do
            {:ok, questions} when is_list(questions) ->
              {:ok, questions}

            _ ->
              {:error, "Failed to parse questions"}
          end

        {:ok, %{status: status}} ->
          {:error, "OpenAI API returned status #{status}"}

        {:error, reason} ->
          {:error, "Failed to call OpenAI: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Creates game stats for a user after a trivia game.
  """
  def create_game_stats(attrs \\ %{}) do
    %GameStats{}
    |> GameStats.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets aggregated trivia statistics for a user.
  Returns a map with total correct and incorrect answers.
  """
  def get_user_stats(user_id) do
    require Logger
    
    stats = 
      GameStats
      |> where([gs], gs.user_id == ^user_id)
      |> select([gs], %{
        total_correct: sum(gs.correct_answers),
        total_incorrect: sum(gs.incorrect_answers),
        total_score: sum(gs.total_score),
        games_played: count(gs.id)
      })
      |> Repo.one()

    Logger.info("Raw stats from DB for user #{user_id}: #{inspect(stats)}")

    # Handle case where user has no stats yet or aggregates return nil
    # sum() returns Decimal, count() returns integer
    result = %{
      total_correct: to_integer_safe(stats.total_correct),
      total_incorrect: to_integer_safe(stats.total_incorrect),
      total_score: to_integer_safe(stats.total_score),
      games_played: stats.games_played || 0
    }
    
    Logger.info("Processed stats for user #{user_id}: #{inspect(result)}")
    result
  end

  # Helper to safely convert Decimal or nil to integer
  defp to_integer_safe(nil), do: 0
  defp to_integer_safe(value) when is_integer(value), do: value
  defp to_integer_safe(%Decimal{} = value), do: Decimal.to_integer(value)
end
