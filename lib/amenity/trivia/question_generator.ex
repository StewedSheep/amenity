defmodule Amenity.Trivia.QuestionGenerator do
  @moduledoc """
  Generates trivia questions using OpenAI API based on Books of Moses.
  """

  @doc """
  Generates a set of trivia questions for a given Book of Moses.
  """
  def generate_questions(book_of_moses, count, difficulty) do
    api_key = System.get_env("OPENAI_API_KEY")

    unless api_key do
      raise "OPENAI_API_KEY environment variable not set"
    end

    prompt = build_prompt(book_of_moses, count, difficulty)

    case call_openai(api_key, prompt) do
      {:ok, questions} -> {:ok, questions}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_prompt(book, count, difficulty) do
    """
    Generate exactly #{count} multiple-choice trivia questions about the Book of #{book} from the Bible.

    Requirements:
    - Difficulty level: #{difficulty}
    - Each question must have exactly 4 answer options (A, B, C, D)
    - Only ONE answer should be correct
    - Questions should test knowledge of events, characters, and teachings from #{book}
    - Return ONLY valid JSON, no additional text

    Format your response as a JSON array with this exact structure:
    [
      {
        "question": "Question text here?",
        "options": ["Option A", "Option B", "Option C", "Option D"],
        "correct_answer": 0
      }
    ]

    Where correct_answer is the index (0-3) of the correct option in the options array.
    """
  end

  defp call_openai(api_key, prompt) do
    url = "https://api.openai.com/v1/chat/completions"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        model: "gpt-4o-mini",
        messages: [
          %{
            role: "system",
            content:
              "You are a Bible trivia expert. Generate questions in valid JSON format only."
          },
          %{role: "user", content: prompt}
        ],
        temperature: 0.8
      })

    case Req.post(url, headers: headers, body: body) do
      {:ok, %{status: 200, body: response_body}} ->
        parse_openai_response(response_body)

      {:ok, %{status: status, body: body}} ->
        {:error, "OpenAI API returned status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to call OpenAI: #{inspect(reason)}"}
    end
  end

  defp parse_openai_response(response) do
    try do
      content = get_in(response, ["choices", Access.at(0), "message", "content"])

      if content do
        # Try to parse the JSON content
        case Jason.decode(content) do
          {:ok, questions} when is_list(questions) ->
            {:ok, questions}

          {:ok, _} ->
            {:error, "Response was not a list of questions"}

          {:error, _} ->
            {:error, "Failed to parse JSON from OpenAI response"}
        end
      else
        {:error, "No content in OpenAI response"}
      end
    rescue
      e -> {:error, "Error parsing response: #{inspect(e)}"}
    end
  end
end
