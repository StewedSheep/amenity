defmodule AmenityWeb.BibleLive.Index do
  use AmenityWeb, :live_view

  alias Amenity.Bible

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:books, [])
      |> assign(:loading, true)
      |> assign(:search, "")
      |> assign(:chapter_reads, %{})

    if connected?(socket) do
      send(self(), :load_books)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_books, socket) do
    {:ok, books} = Bible.fetch_books()
    user_id = socket.assigns.current_scope.user.id
    chapter_reads = Bible.list_user_chapter_reads(user_id)

    # Create a map for quick lookup
    reads_map =
      chapter_reads
      |> Enum.reduce(%{}, fn read, acc ->
        key = "#{read.book}_#{read.chapter}"
        Map.put(acc, key, true)
      end)

    {:noreply,
     socket
     |> assign(:books, books)
     |> assign(:chapter_reads, reads_map)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, assign(socket, :search, search)}
  end

  defp filtered_books(books, search) do
    if search == "" do
      books
    else
      search_lower = String.downcase(search)

      Enum.filter(books, fn book ->
        String.contains?(String.downcase(book.name), search_lower) or
          String.contains?(String.downcase(book.abbr), search_lower)
      end)
    end
  end

  defp chapter_read?(chapter_reads, book, chapter) do
    Map.has_key?(chapter_reads, "#{book}_#{chapter}")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 via-purple-50 to-pink-50">
      <div class="max-w-7xl mx-auto px-4 py-8">
        <!-- Header -->
        <div class="text-center mb-12">
          <h1 class="text-6xl font-bold mb-4 bg-gradient-to-r from-blue-600 via-purple-600 to-pink-600 bg-clip-text text-transparent">
            📖 Bible Reader
          </h1>
          <p class="text-xl text-gray-600">Choose a book and chapter to start reading!</p>
        </div>
        
    <!-- Search bar -->
        <div class="max-w-2xl mx-auto mb-8">
          <form phx-change="search" class="relative">
            <input
              type="text"
              name="search"
              value={@search}
              placeholder="🔍 Search for a book..."
              class="input input-bordered input-lg w-full bg-white shadow-lg rounded-full pl-6 pr-12 text-lg"
              phx-debounce="300"
            />
          </form>
        </div>
        
    <!-- Loading state -->
        <div :if={@loading} class="text-center py-20">
          <div class="inline-block animate-spin rounded-full h-16 w-16 border-t-4 border-b-4 border-purple-500">
          </div>
          <p class="mt-4 text-xl text-gray-600">Loading books...</p>
        </div>
        
    <!-- Books grid -->
        <div :if={!@loading} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <div
            :for={book <- filtered_books(@books, @search)}
            class="bg-white rounded-3xl p-6 shadow-lg hover:shadow-2xl transition-all transform hover:scale-105 border-t-4 border-purple-400"
          >
            <h2 class="text-2xl font-bold text-gray-800 mb-4 flex items-center gap-2">
              <span class="text-3xl">📚</span>
              {book.name}
            </h2>

            <div class="text-black flex flex-wrap gap-2">
              <.link
                :for={chapter <- 1..book.chapters}
                navigate={~p"/bible/#{book.abbr}/#{chapter}"}
                class={[
                  "btn btn-sm rounded-full font-semibold transition-all transform hover:scale-110",
                  if(chapter_read?(@chapter_reads, book.abbr, chapter),
                    do: "bg-gradient-to-r from-green-400 to-emerald-500 text-white shadow-md",
                    else: "btn-ghost hover:bg-purple-100"
                  )
                ]}
              >
                <%= if chapter_read?(@chapter_reads, book.abbr, chapter) do %>
                  ✓ {chapter}
                <% else %>
                  {chapter}
                <% end %>
              </.link>
            </div>
          </div>
        </div>
        
    <!-- Empty state -->
        <div :if={!@loading and filtered_books(@books, @search) == []} class="text-center py-20">
          <p class="text-2xl text-gray-600">No books found matching "{@search}"</p>
        </div>
      </div>
    </div>
    """
  end
end
