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
  Ensures the user has a master set.
  """
  def list_flashcard_sets(user_id) do
    ensure_master_set(user_id)
    
    from(s in FlashcardSet,
      where: s.user_id == ^user_id,
      order_by: [desc: s.updated_at],
      preload: [:flashcards]
    )
    |> Repo.all()
  end

  @doc """
  Ensures a user has a master flashcard set with default cards.
  """
  def ensure_master_set(user_id) do
    # Check if user already has a master set
    existing = Repo.one(
      from s in FlashcardSet,
      where: s.user_id == ^user_id and s.name == "📚 Master Set"
    )

    if is_nil(existing) do
      create_master_set(user_id)
    end
  end

  @doc """
  Gets the user's master deck.
  """
  def get_master_deck(user_id) do
    Repo.one(
      from s in FlashcardSet,
      where: s.user_id == ^user_id and s.name == "📚 Master Set"
    )
  end

  defp create_master_set(user_id) do
    {:ok, set} = create_flashcard_set(%{
      user_id: user_id,
      name: "📚 Master Set",
      description: "Essential Bible knowledge flashcards"
    })

    # Create default master flashcards
    master_cards = [
      %{front: "Who is the author of the Gospel of John?", back: "The Apostle John"},
      %{front: "What is the first book of the Bible?", back: "Genesis"},
      %{front: "What is the last book of the Bible?", back: "Revelation"},
      %{front: "How many books are in the Bible?", back: "66 books (39 Old Testament, 27 New Testament)"},
      %{front: "What is the shortest verse in the Bible?", back: "\"Jesus wept.\" (John 11:35)"},
      %{front: "Who built the ark?", back: "Noah"},
      %{front: "Who was the first king of Israel?", back: "Saul"},
      %{front: "Who was the strongest man in the Bible?", back: "Samson"},
      %{front: "Who was swallowed by a great fish?", back: "Jonah"},
      %{front: "What are the fruits of the Spirit?", back: "Love, joy, peace, patience, kindness, goodness, faithfulness, gentleness, self-control (Galatians 5:22-23)"}
    ]

    Enum.with_index(master_cards, fn card, index ->
      create_flashcard(Map.merge(card, %{
        flashcard_set_id: set.id,
        position: index
      }))
    end)

    set
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
  Gets a single flashcard.
  """
  def get_flashcard!(id), do: Repo.get!(Flashcard, id)

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

  # SM-2 Algorithm implementation with shorter intervals
  # Again: 5 minutes, Hard: 1 day, Good: 3 days, Easy: 7 days
  defp calculate_sm2(ease_factor, interval, repetitions, quality) do
    new_ease_factor = max(1.3, ease_factor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)))

    {new_interval, new_repetitions} = cond do
      # Again (quality 0-2) - 5 minutes
      quality < 3 ->
        {0.0035, 0}  # 0.0035 days = ~5 minutes
      
      # Hard (quality 3) - 1 day
      quality == 3 ->
        {1, repetitions + 1}
      
      # Good (quality 4) - 3 days base
      quality == 4 ->
        if repetitions == 0 do
          {3, 1}
        else
          {round(interval * 1.5), repetitions + 1}
        end
      
      # Easy (quality 5) - 7 days base
      true ->
        if repetitions == 0 do
          {7, 1}
        else
          {round(interval * new_ease_factor), repetitions + 1}
        end
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
           description: set_description,
           ai_generated: true
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
      - Include verse references AND context in questions (e.g., "When God said 'Let there be light' in Genesis 1:3, what happened?")
      - Provide enough context so the question makes sense on its own WITHOUT looking up the verse
      - Avoid vague questions like "What happened in this verse?" or "Who was there?"
      - Use concrete facts: names, numbers, specific actions, direct quotes
      - Keep questions CLEAR but contextual (15-25 words is fine if needed for clarity)
      - Keep answers BRIEF (1-2 sentences maximum, preferably just a few words)
      - DO NOT use phrases like "According to your notes" or "The note says" in questions
      - Questions should be direct and natural, as if asking about the Bible text itself
      
      GOOD examples (notice the context):
      - "When God spoke on the first day of creation in Genesis 1:3, what did He say?" → "Let there be light"
      - "After God created light and darkness in Genesis 1, what did He call them?" → "Day and night"
      - "How many days did God work before resting in Genesis 1?" → "Six days"
      
      BAD examples:
      - "What did God do in this verse?" → Too vague, no context
      - "What happened in Genesis 1:3?" → No context about what's being asked
      - "According to the notes, what is important?" → Don't reference notes
      
      Chapter text:
      #{chapter_text}#{notes_text}
      
      IMPORTANT: If there are personal notes above, create questions about the content they highlight.
      Ask about the actual Bible content, NOT about what the notes say.
      Include enough context from the surrounding verses so questions are clear and self-contained.
      
      Return ONLY a JSON array of objects with "front" and "back" keys.
      Example: [{"front": "When God began creating in Genesis 1:1, what did He create?", "back": "The heavens and the earth"}]
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
