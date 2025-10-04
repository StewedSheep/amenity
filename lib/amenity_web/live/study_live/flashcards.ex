defmodule AmenityWeb.StudyLive.Flashcards do
  use AmenityWeb, :live_view

  alias Amenity.Study

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    flashcard_sets = Study.list_flashcard_sets(user_id)

    {:ok,
     socket
     |> assign(:flashcard_sets, flashcard_sets)
     |> assign(:show_create_modal, false)}
  end

  @impl true
  def handle_event("show_create_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, true)}
  end

  def handle_event("hide_create_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, false)}
  end

  def handle_event("modal_content_click", _params, socket) do
    # Do nothing - prevents click from bubbling to background
    {:noreply, socket}
  end

  def handle_event("create_set", %{"name" => name, "description" => description}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Study.create_flashcard_set(%{
      user_id: user_id,
      name: name,
      description: description
    }) do
      {:ok, _set} ->
        flashcard_sets = Study.list_flashcard_sets(user_id)

        {:noreply,
         socket
         |> assign(:flashcard_sets, flashcard_sets)
         |> assign(:show_create_modal, false)
         |> put_flash(:info, "Flashcard set created!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create flashcard set")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 via-purple-50 to-pink-50">
      <div class="max-w-7xl mx-auto px-4 py-8">
        <!-- Header -->
        <div class="mb-8">
          <.link navigate={~p"/study"} class="text-blue-600 hover:text-blue-800 mb-4 inline-block">
            ← Back to Study
          </.link>
          <div class="flex justify-between items-center">
            <div>
              <h1 class="text-5xl font-bold mb-2">
                🎴 <span class="bg-gradient-to-r from-blue-600 via-purple-600 to-pink-600 bg-clip-text text-transparent">Flashcards</span>
              </h1>
              <p class="text-xl text-gray-600">Manage your flashcard sets</p>
            </div>
            <button
              phx-click="show_create_modal"
              class="btn btn-primary btn-lg rounded-full"
            >
              ➕ Create New Set
            </button>
          </div>
        </div>

        <!-- Flashcard Sets Grid -->
        <%= if @flashcard_sets == [] do %>
          <div class="text-center py-20 bg-white rounded-3xl shadow-lg">
            <div class="text-6xl mb-4">🎴</div>
            <p class="text-2xl text-gray-600 mb-4">No flashcard sets yet</p>
            <p class="text-gray-500 mb-6">Create your first set to start studying!</p>
            <button
              phx-click="show_create_modal"
              class="btn btn-primary btn-lg rounded-full"
            >
              ➕ Create Your First Set
            </button>
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for set <- @flashcard_sets do %>
              <.link
                navigate={~p"/study/flashcards/#{set.id}"}
                class="bg-white rounded-2xl p-6 shadow-lg hover:shadow-2xl transition-all hover:scale-105 border-t-4 border-blue-400"
              >
                <h3 class="text-xl font-bold text-gray-800 mb-2">{set.name}</h3>
                <%= if set.description do %>
                  <p class="text-gray-600 text-sm mb-4 line-clamp-2">{set.description}</p>
                <% end %>
                <div class="flex items-center justify-between text-sm text-gray-500 mt-4">
                  <span>🎴 {length(set.flashcards)} cards</span>
                  <span class="text-blue-600 font-semibold">Study →</span>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>

        <!-- Info Section -->
        <div class="mt-12 bg-white rounded-3xl p-8 shadow-lg">
          <h2 class="text-2xl font-bold text-gray-800 mb-4">How Flashcards Work</h2>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div>
              <div class="text-3xl mb-2">📚</div>
              <h3 class="font-bold text-gray-800 mb-2">Create Sets</h3>
              <p class="text-gray-600 text-sm">Organize your flashcards into themed sets for focused study sessions.</p>
            </div>
            <div>
              <div class="text-3xl mb-2">🧠</div>
              <h3 class="font-bold text-gray-800 mb-2">Spaced Repetition</h3>
              <p class="text-gray-600 text-sm">Our SM-2 algorithm optimizes review timing for maximum retention.</p>
            </div>
            <div>
              <div class="text-3xl mb-2">📈</div>
              <h3 class="font-bold text-gray-800 mb-2">Track Progress</h3>
              <p class="text-gray-600 text-sm">Monitor your learning with detailed statistics and review history.</p>
            </div>
          </div>
        </div>
      </div>

      <!-- Create Set Modal -->
      <%= if @show_create_modal do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50" phx-click="hide_create_modal">
          <div class="bg-white rounded-2xl p-8 max-w-md w-full mx-4 shadow-2xl" phx-click="modal_content_click">
            <h2 class="text-2xl font-bold text-gray-800 mb-6">Create Flashcard Set</h2>

            <form phx-submit="create_set" class="space-y-4">
              <div>
                <label class="block text-sm font-semibold text-gray-700 mb-2">Set Name</label>
                <input
                  type="text"
                  name="name"
                  required
                  class="input input-bordered w-full"
                  placeholder="e.g., Books of the Bible"
                />
              </div>

              <div>
                <label class="block text-sm font-semibold text-gray-700 mb-2">Description (Optional)</label>
                <textarea
                  name="description"
                  rows="3"
                  class="textarea textarea-bordered w-full"
                  placeholder="What will you study in this set?"
                ></textarea>
              </div>

              <div class="flex gap-3 pt-4">
                <button type="button" phx-click="hide_create_modal" class="btn btn-ghost flex-1">
                  Cancel
                </button>
                <button type="submit" class="btn btn-primary flex-1">
                  Create Set
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
