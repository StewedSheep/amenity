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
