defmodule Amenity.Bible do
  @moduledoc """
  The Bible context - handles Bible API integration and chapter read tracking.
  """

  import Ecto.Query, warn: false
  alias Amenity.Repo
  alias Amenity.Bible.{ChapterRead, Annotation}

  @bolls_api_base "https://bolls.life"

  @doc """
  Fetches a chapter from the Bolls.life API.
  Returns the chapter text with HTML tags stripped (except S and i tags which are ignored).
  """
  def fetch_chapter(book, chapter, translation \\ "KJV") do
    url = "#{@bolls_api_base}/get-text/#{translation}/#{book}/#{chapter}/"
    
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        verses = parse_chapter_response(body)
        {:ok, %{book: book, chapter: chapter, translation: translation, verses: verses}}
      
      {:ok, %{status: status}} ->
        {:error, "API returned status #{status}"}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches the list of available books from the API.
  Only returns the Books of Moses (Torah/Pentateuch).
  """
  def fetch_books(translation \\ "KJV") do
    # Return only the Books of Moses
    {:ok, get_default_books()}
  end

  defp parse_chapter_response(body) when is_list(body) do
    Enum.map(body, fn verse ->
      text = clean_verse_text(verse["text"] || "")
      %{
        verse: verse["verse"],
        text: text
      }
    end)
  end

  defp parse_chapter_response(body) when is_map(body) do
    verses = body["verses"] || []
    parse_chapter_response(verses)
  end

  defp parse_chapter_response(_), do: []

  defp clean_verse_text(text) do
    text
    |> String.replace(~r/<S>.*?<\/S>/i, "")
    |> String.replace(~r/<i>.*?<\/i>/i, "")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
  end

  @doc """
  Gets or creates a chapter read record for a user.
  """
  def get_or_create_chapter_read(user_id, book, chapter) do
    case Repo.get_by(ChapterRead, user_id: user_id, book: book, chapter: chapter) do
      nil ->
        %ChapterRead{}
        |> ChapterRead.changeset(%{user_id: user_id, book: book, chapter: chapter})
        |> Repo.insert()
      
      chapter_read ->
        {:ok, chapter_read}
    end
  end

  @doc """
  Marks a chapter as read by adding current timestamp to last_read array.
  """
  def mark_chapter_as_read(user_id, book, chapter) do
    {:ok, chapter_read} = get_or_create_chapter_read(user_id, book, chapter)
    
    chapter_read
    |> ChapterRead.mark_as_read()
    |> Repo.update()
  end

  @doc """
  Gets all chapter reads for a user.
  """
  def list_user_chapter_reads(user_id) do
    ChapterRead
    |> where([cr], cr.user_id == ^user_id)
    |> order_by([cr], desc: cr.updated_at)
    |> Repo.all()
  end

  @doc """
  Checks if a user has read a specific chapter.
  """
  def chapter_read?(user_id, book, chapter) do
    ChapterRead
    |> where([cr], cr.user_id == ^user_id and cr.book == ^book and cr.chapter == ^chapter)
    |> Repo.exists?()
  end

  defp get_default_books do
    # Books of Moses (Torah/Pentateuch)
    [
      %{name: "Genesis", abbr: "Gen", chapters: 50},
      %{name: "Exodus", abbr: "Exod", chapters: 40},
      %{name: "Leviticus", abbr: "Lev", chapters: 27},
      %{name: "Numbers", abbr: "Num", chapters: 36},
      %{name: "Deuteronomy", abbr: "Deut", chapters: 34}
    ]
  end

  ## Annotations

  @doc """
  Creates an annotation for a specific verse.
  """
  def create_annotation(attrs) do
    %Annotation{}
    |> Annotation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an annotation.
  """
  def update_annotation(%Annotation{} = annotation, attrs) do
    annotation
    |> Annotation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an annotation.
  """
  def delete_annotation(%Annotation{} = annotation) do
    Repo.delete(annotation)
  end

  @doc """
  Gets a single annotation by ID.
  """
  def get_annotation!(id), do: Repo.get!(Annotation, id)

  @doc """
  Lists all annotations for a user in a specific chapter.
  """
  def list_chapter_annotations(user_id, book, chapter) do
    from(a in Annotation,
      where: a.user_id == ^user_id and a.book == ^book and a.chapter == ^chapter,
      order_by: [asc: a.verse]
    )
    |> Repo.all()
  end

  @doc """
  Gets annotation for a specific verse (if exists).
  """
  def get_verse_annotation(user_id, book, chapter, verse) do
    Repo.get_by(Annotation, user_id: user_id, book: book, chapter: chapter, verse: verse)
  end

  @doc """
  Lists all annotations for a specific verse.
  """
  def list_verse_annotations(user_id, book, chapter, verse) do
    from(a in Annotation,
      where: a.user_id == ^user_id and a.book == ^book and a.chapter == ^chapter and a.verse == ^verse,
      order_by: [desc: a.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists all annotations for a user across all books.
  """
  def list_user_annotations(user_id) do
    from(a in Annotation,
      where: a.user_id == ^user_id,
      order_by: [desc: a.updated_at]
    )
    |> Repo.all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking annotation changes.
  """
  def change_annotation(%Annotation{} = annotation, attrs \\ %{}) do
    Annotation.changeset(annotation, attrs)
  end
end
