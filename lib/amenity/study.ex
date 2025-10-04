defmodule Amenity.Study do
  @moduledoc """
  The Study context - handles flashcards and spaced repetition learning.
  """

  import Ecto.Query, warn: false
  alias Amenity.Repo
  alias Amenity.Study.{FlashcardSet, Flashcard, FlashcardReview}

  ## Flashcard Sets

  @doc """
  Returns the list of flashcard sets for a user.
  """
  def list_flashcard_sets(user_id) do
    from(s in FlashcardSet,
      where: s.user_id == ^user_id,
      order_by: [desc: s.updated_at],
      preload: [:flashcards]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single flashcard set.
  """
  def get_flashcard_set!(id), do: Repo.get!(FlashcardSet, id) |> Repo.preload(:flashcards)

  @doc """
  Creates a flashcard set.
  """
  def create_flashcard_set(attrs \\ %{}) do
    %FlashcardSet{}
    |> FlashcardSet.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a flashcard set.
  """
  def update_flashcard_set(%FlashcardSet{} = flashcard_set, attrs) do
    flashcard_set
    |> FlashcardSet.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a flashcard set.
  """
  def delete_flashcard_set(%FlashcardSet{} = flashcard_set) do
    Repo.delete(flashcard_set)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking flashcard set changes.
  """
  def change_flashcard_set(%FlashcardSet{} = flashcard_set, attrs \\ %{}) do
    FlashcardSet.changeset(flashcard_set, attrs)
  end

  ## Flashcards

  @doc """
  Creates a flashcard.
  """
  def create_flashcard(attrs \\ %{}) do
    %Flashcard{}
    |> Flashcard.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a flashcard.
  """
  def update_flashcard(%Flashcard{} = flashcard, attrs) do
    flashcard
    |> Flashcard.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a flashcard.
  """
  def delete_flashcard(%Flashcard{} = flashcard) do
    Repo.delete(flashcard)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking flashcard changes.
  """
  def change_flashcard(%Flashcard{} = flashcard, attrs \\ %{}) do
    Flashcard.changeset(flashcard, attrs)
  end

  ## Flashcard Reviews (Spaced Repetition)

  @doc """
  Gets the next cards due for review for a user in a specific set.
  """
  def get_due_flashcards(user_id, flashcard_set_id, limit \\ 20) do
    now = DateTime.utc_now()
    
    # Get all flashcards in the set
    flashcard_ids = from(f in Flashcard,
      where: f.flashcard_set_id == ^flashcard_set_id,
      select: f.id
    ) |> Repo.all()

    # Get reviews for these flashcards
    reviewed_ids = from(r in FlashcardReview,
      where: r.user_id == ^user_id and r.flashcard_id in ^flashcard_ids,
      where: r.next_review_date > ^now,
      select: r.flashcard_id
    ) |> Repo.all()

    # Get cards that are due or never reviewed
    from(f in Flashcard,
      where: f.flashcard_set_id == ^flashcard_set_id,
      where: f.id not in ^reviewed_ids,
      order_by: [asc: f.position],
      limit: ^limit,
      preload: [:flashcard_set]
    )
    |> Repo.all()
  end

  @doc """
  Records a flashcard review and calculates next review date using SM-2 algorithm.
  """
  def record_review(user_id, flashcard_id, quality) do
    # Get existing review or create new one
    review = Repo.get_by(FlashcardReview, user_id: user_id, flashcard_id: flashcard_id) ||
             %FlashcardReview{user_id: user_id, flashcard_id: flashcard_id}

    # SM-2 Algorithm
    {new_ease_factor, new_interval, new_repetitions} = 
      calculate_sm2(review.ease_factor, review.interval, review.repetitions, quality)

    next_review_date = DateTime.add(DateTime.utc_now(), new_interval * 86400, :second)

    attrs = %{
      quality: quality,
      ease_factor: new_ease_factor,
      interval: new_interval,
      repetitions: new_repetitions,
      next_review_date: next_review_date
    }

    review
    |> FlashcardReview.changeset(attrs)
    |> Repo.insert_or_update()
  end

  # SM-2 Algorithm implementation
  defp calculate_sm2(ease_factor, interval, repetitions, quality) do
    new_ease_factor = max(1.3, ease_factor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)))

    {new_interval, new_repetitions} = cond do
      quality < 3 ->
        # Failed - reset
        {1, 0}
      
      repetitions == 0 ->
        {1, 1}
      
      repetitions == 1 ->
        {6, 2}
      
      true ->
        {round(interval * new_ease_factor), repetitions + 1}
    end

    {new_ease_factor, new_interval, new_repetitions}
  end

  @doc """
  Generates flashcards from a Bible chapter using OpenAI.
  """
  def generate_flashcards_from_chapter(user_id, book, chapter, verses, annotations \\ []) do
    # Create the flashcard set
    set_name = "#{book} #{chapter}"
    set_description = "Auto-generated flashcards for #{book} chapter #{chapter}"

    case create_flashcard_set(%{
           user_id: user_id,
           name: set_name,
           description: set_description
         }) do
      {:ok, flashcard_set} ->
        case call_openai_for_flashcards(book, chapter, verses, annotations) do
          {:ok, cards} ->
            # Create flashcards
            results =
              cards
              |> Enum.with_index()
              |> Enum.map(fn {{front, back}, index} ->
                create_flashcard(%{
                  flashcard_set_id: flashcard_set.id,
                  front: front,
                  back: back,
                  position: index
                })
              end)

            # Log any errors
            Enum.each(results, fn
              {:error, changeset} ->
                require Logger
                Logger.error("Failed to create flashcard: #{inspect(changeset.errors)}")

              _ ->
                :ok
            end)

            {:ok, flashcard_set}

          {:error, reason} ->
            require Logger
            Logger.error("Failed to generate flashcards: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, changeset} ->
        require Logger
        Logger.error("Failed to create flashcard set: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp call_openai_for_flashcards(book, chapter, verses, annotations) do
    api_key = System.get_env("OPENAI_API_KEY")
    
    require Logger
    Logger.info("API Key present: #{!is_nil(api_key)}, Length: #{if api_key, do: String.length(api_key), else: 0}")

    if !api_key do
      {:error, "OPENAI_API_KEY not set"}
    else
      # Combine verses into text
      chapter_text =
        verses
        |> Enum.map(fn verse -> "#{verse.verse}. #{verse.text}" end)
        |> Enum.join("\n")

      # Add annotations/notes
      notes_text =
        if annotations != [] do
          notes =
            annotations
            |> Enum.map(fn annotation ->
              "Verse #{annotation.verse} - Note: #{annotation.note || "Highlighted: #{annotation.content}"}"
            end)
            |> Enum.join("\n")

          "\n\nUSER'S PERSONAL NOTES (IMPORTANT - Create questions about these):\n#{notes}"
        else
          ""
        end

      num_questions = max(5, div(length(verses), 2) + length(annotations))
      
      prompt = """
      Create #{num_questions} flashcards for studying #{book} chapter #{chapter} from the Bible.
      
      REQUIREMENTS:
      - Questions must be SPECIFIC and have only ONE correct answer
      - Include verse references in questions (e.g., "In #{book} #{chapter}:1, what...")
      - Avoid vague questions like "What happened?" or "Who was there?"
      - Use concrete facts: names, numbers, specific actions, direct quotes
      - Keep questions SHORT (under 15 words)
      - Keep answers BRIEF (1-2 sentences maximum, preferably just a few words)
      - DO NOT use phrases like "According to your notes" or "The note says" in questions
      - Questions should be direct and natural, as if asking about the Bible text itself
      
      GOOD examples:
      - "In Genesis 1:3, what did God say?" → "Let there be light"
      - "How many days did creation take in Genesis 1?" → "Six days"
      
      BAD examples:
      - "What did God do?" → Too vague
      - "According to the notes, what is important about verse 3?" → Don't reference notes in question
      - "What happened in this chapter and why is it significant?" → Too long, multiple questions
      
      Chapter text:
      #{chapter_text}#{notes_text}
      
      IMPORTANT: If there are personal notes above, create questions about the content they highlight.
      Ask about the actual Bible content, NOT about what the notes say.
      
      Return ONLY a JSON array of objects with "front" and "back" keys.
      Example: [{"front": "In #{book} #{chapter}:1, what did God create?", "back": "The heavens and the earth"}]
      """

      body = %{
        model: "gpt-4o-mini",
        messages: [
          %{role: "system", content: "You are a Bible study assistant that creates effective flashcards."},
          %{role: "user", content: prompt}
        ],
        temperature: 0.7
      }

      case Req.post("https://api.openai.com/v1/chat/completions",
             json: body,
             headers: [{"Authorization", "Bearer #{api_key}"}]
           ) do
        {:ok, %{status: 200, body: response}} ->
          content = get_in(response, ["choices", Access.at(0), "message", "content"])
          require Logger
          Logger.info("OpenAI response: #{inspect(content)}")
          parse_flashcards_json(content)

        {:ok, %{status: status, body: body}} ->
          require Logger
          Logger.error("OpenAI API returned status #{status}: #{inspect(body)}")
          {:error, "OpenAI API returned status #{status}"}

        {:error, reason} ->
          require Logger
          Logger.error("OpenAI API request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp parse_flashcards_json(content) do
    # Remove markdown code blocks if present
    cleaned =
      content
      |> String.replace(~r/```json\n?/, "")
      |> String.replace(~r/```\n?/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, cards} when is_list(cards) ->
        parsed_cards =
          Enum.map(cards, fn card ->
            {Map.get(card, "front"), Map.get(card, "back")}
          end)

        {:ok, parsed_cards}

      _ ->
        {:error, "Failed to parse flashcards JSON"}
    end
  end

  @doc """
  Gets review statistics for a flashcard set.
  """
  def get_set_stats(user_id, flashcard_set_id) do
    total_cards = from(f in Flashcard,
      where: f.flashcard_set_id == ^flashcard_set_id,
      select: count(f.id)
    ) |> Repo.one()

    reviewed_cards = from(r in FlashcardReview,
      join: f in Flashcard, on: f.id == r.flashcard_id,
      where: r.user_id == ^user_id and f.flashcard_set_id == ^flashcard_set_id,
      select: count(r.id)
    ) |> Repo.one()

    due_cards = from(r in FlashcardReview,
      join: f in Flashcard, on: f.id == r.flashcard_id,
      where: r.user_id == ^user_id and f.flashcard_set_id == ^flashcard_set_id,
      where: r.next_review_date <= ^DateTime.utc_now(),
      select: count(r.id)
    ) |> Repo.one()

    %{
      total: total_cards,
      reviewed: reviewed_cards,
      new: total_cards - reviewed_cards,
      due: due_cards
    }
  end
end
