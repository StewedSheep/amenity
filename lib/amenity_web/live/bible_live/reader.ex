defmodule AmenityWeb.BibleLive.Reader do
  use AmenityWeb, :live_view

  alias Amenity.Bible

  @impl true
  def mount(%{"book" => book, "chapter" => chapter}, _session, socket) do
    chapter_num = String.to_integer(chapter)
    
    socket =
      socket
      |> assign(:book, book)
      |> assign(:chapter, chapter_num)
      |> assign(:loading, true)
      |> assign(:verses, [])
      |> assign(:error, nil)
      |> assign(:translation, "KJV")
    
    if connected?(socket) do
      send(self(), :load_chapter)
    end
    
    {:ok, socket}
  end

  @impl true
  def handle_info(:load_chapter, socket) do
    case Bible.fetch_chapter(socket.assigns.book, socket.assigns.chapter, socket.assigns.translation) do
      {:ok, %{verses: verses}} ->
        {:noreply,
         socket
         |> assign(:verses, verses)
         |> assign(:loading, false)}
      
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, reason)
         |> assign(:loading, false)}
    end
  end

  @impl true
  def handle_event("mark_as_read", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    
    case Bible.mark_chapter_as_read(user_id, socket.assigns.book, socket.assigns.chapter) do
      {:ok, _chapter_read} ->
        {:noreply,
         socket
         |> put_flash(:info, "✨ Chapter marked as read!")
         |> push_navigate(to: ~p"/bible")}
      
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not mark chapter as read")}
    end
  end

  def handle_event("next_chapter", _params, socket) do
    next_chapter = socket.assigns.chapter + 1
    {:noreply, push_navigate(socket, to: ~p"/bible/#{socket.assigns.book}/#{next_chapter}")}
  end

  def handle_event("prev_chapter", _params, socket) do
    if socket.assigns.chapter > 1 do
      prev_chapter = socket.assigns.chapter - 1
      {:noreply, push_navigate(socket, to: ~p"/bible/#{socket.assigns.book}/#{prev_chapter}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-purple-50 via-pink-50 to-yellow-50">
      <div class="max-w-4xl mx-auto px-4 py-8">
        <!-- Header with whimsical styling -->
        <div class="text-center mb-8">
          <h1 class="text-5xl font-bold mb-2 bg-gradient-to-r from-purple-600 via-pink-600 to-orange-500 bg-clip-text text-transparent animate-pulse">
            <%= @book %> <%= @chapter %>
          </h1>
          <p class="text-gray-600 text-lg">📖 <%= @translation %> Translation</p>
        </div>

        <!-- Navigation buttons -->
        <div class="flex justify-between mb-6">
          <button
            :if={@chapter > 1}
            phx-click="prev_chapter"
            class="btn btn-circle btn-lg bg-purple-500 hover:bg-purple-600 text-white shadow-lg hover:shadow-xl transform hover:scale-110 transition-all"
          >
            ←
          </button>
          <div :if={@chapter == 1} class="w-16"></div>
          
          <.link
            navigate={~p"/bible"}
            class="btn btn-ghost btn-lg text-purple-600 hover:text-purple-800"
          >
            📚 Book List
          </.link>
          
          <button
            phx-click="next_chapter"
            class="btn btn-circle btn-lg bg-pink-500 hover:bg-pink-600 text-white shadow-lg hover:shadow-xl transform hover:scale-110 transition-all"
          >
            →
          </button>
        </div>

        <!-- Loading state -->
        <div :if={@loading} class="text-center py-20">
          <div class="inline-block animate-spin rounded-full h-16 w-16 border-t-4 border-b-4 border-purple-500"></div>
          <p class="mt-4 text-xl text-gray-600">Loading chapter...</p>
        </div>

        <!-- Error state -->
        <div :if={@error} class="alert alert-error shadow-lg">
          <span>❌ Error: <%= @error %></span>
        </div>

        <!-- Verses -->
        <div :if={!@loading and !@error} class="space-y-4">
          <div
            :for={verse <- @verses}
            class="bg-white rounded-2xl p-6 shadow-md hover:shadow-xl transition-all transform hover:scale-[1.02] border-l-4 border-purple-400"
          >
            <div class="flex items-start gap-4">
              <span class="flex-shrink-0 w-10 h-10 bg-gradient-to-br from-purple-400 to-pink-400 rounded-full flex items-center justify-center text-white font-bold text-lg shadow-md">
                <%= verse.verse %>
              </span>
              <p class="text-gray-800 text-lg leading-relaxed flex-1">
                <%= verse.text %>
              </p>
            </div>
          </div>

          <!-- Mark as Read button -->
          <div class="text-center py-12">
            <button
              phx-click="mark_as_read"
              class="btn btn-lg bg-gradient-to-r from-green-400 via-blue-500 to-purple-600 text-white font-bold px-12 py-4 rounded-full shadow-2xl hover:shadow-3xl transform hover:scale-110 transition-all animate-bounce hover:animate-none"
            >
              ✅ Mark as Read!
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
