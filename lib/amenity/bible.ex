defmodule Amenity.Bible do
  @moduledoc """
  The Bible context - handles Bible API integration and chapter read tracking.
  """

  import Ecto.Query, warn: false
  alias Amenity.Repo
  alias Amenity.Bible.ChapterRead

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
end
