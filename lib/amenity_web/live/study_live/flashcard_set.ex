defmodule AmenityWeb.StudyLive.FlashcardSet do
  use AmenityWeb, :live_view

  alias Amenity.Study

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    flashcard_set = Study.get_flashcard_set!(id)
    user_id = socket.assigns.current_scope.user.id

    # Verify ownership
    if flashcard_set.user_id != user_id do
      {:ok,
       socket
       |> put_flash(:error, "You don't have access to this flashcard set")
       |> push_navigate(to: ~p"/study/flashcards")}
    else
      stats = Study.get_set_stats(user_id, String.to_integer(id))

      {:ok,
       socket
       |> assign(:flashcard_set, flashcard_set)
       |> assign(:stats, stats)
       |> assign(:show_add_card_modal, false)
       |> assign(:editing_card, nil)}
    end
  end

  @impl true
  def handle_event("show_add_card_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_card_modal, true)
     |> assign(:editing_card, nil)}
  end

  def handle_event("hide_add_card_modal", _params, socket) do
    {:noreply, assign(socket, :show_add_card_modal, false)}
  end

  def handle_event("modal_content_click", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("edit_card", %{"id" => id}, socket) do
    card = Enum.find(socket.assigns.flashcard_set.flashcards, fn c -> c.id == String.to_integer(id) end)

    {:noreply,
     socket
     |> assign(:show_add_card_modal, true)
     |> assign(:editing_card, card)}
  end

  def handle_event("save_card", %{"front" => front, "back" => back}, socket) do
    if socket.assigns.editing_card do
      # Update existing card
      case Study.update_flashcard(socket.assigns.editing_card, %{front: front, back: back}) do
        {:ok, _card} ->
          flashcard_set = Study.get_flashcard_set!(socket.assigns.flashcard_set.id)

          {:noreply,
           socket
           |> assign(:flashcard_set, flashcard_set)
           |> assign(:show_add_card_modal, false)
           |> put_flash(:info, "Card updated!")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not update card")}
      end
    else
      # Create new card
      position = length(socket.assigns.flashcard_set.flashcards)

      case Study.create_flashcard(%{
        flashcard_set_id: socket.assigns.flashcard_set.id,
        front: front,
        back: back,
        position: position
      }) do
        {:ok, _card} ->
          flashcard_set = Study.get_flashcard_set!(socket.assigns.flashcard_set.id)

          {:noreply,
           socket
           |> assign(:flashcard_set, flashcard_set)
           |> assign(:show_add_card_modal, false)
           |> put_flash(:info, "Card added!")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not add card")}
      end
    end
  end

  def handle_event("delete_card", %{"id" => id}, socket) do
    card = Enum.find(socket.assigns.flashcard_set.flashcards, fn c -> c.id == String.to_integer(id) end)

    case Study.delete_flashcard(card) do
      {:ok, _} ->
        flashcard_set = Study.get_flashcard_set!(socket.assigns.flashcard_set.id)

        {:noreply,
         socket
         |> assign(:flashcard_set, flashcard_set)
         |> put_flash(:info, "Card deleted!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete card")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 via-purple-50 to-pink-50">
      <div class="max-w-7xl mx-auto px-4 py-8">
        <!-- Header -->
        <div class="mb-8">
          <.link navigate={~p"/study/flashcards"} class="text-blue-600 hover:text-blue-800 mb-4 inline-block">
            ← Back to Flashcards
          </.link>
          <div class="flex justify-between items-start">
            <div>
              <h1 class="text-4xl font-bold text-gray-800 mb-2">{@flashcard_set.name}</h1>
              <%= if @flashcard_set.description do %>
                <p class="text-gray-600 text-lg">{@flashcard_set.description}</p>
              <% end %>
            </div>
            <div class="flex gap-3">
              <%= if length(@flashcard_set.flashcards) > 0 do %>
                <.link
                  navigate={~p"/study/flashcards/#{@flashcard_set.id}/study"}
                  class="btn btn-primary btn-lg rounded-full"
                >
                  🎴 Start Studying
                </.link>
              <% end %>
              <button
                phx-click="show_add_card_modal"
                class="btn btn-secondary btn-lg rounded-full"
              >
                ➕ Add Card
              </button>
            </div>
          </div>
        </div>

        <!-- Stats -->
        <div class="grid grid-cols-4 gap-4 mb-8">
          <div class="bg-white rounded-2xl p-6 shadow-lg text-center">
            <div class="text-3xl font-bold text-blue-600">{@stats.total}</div>
            <div class="text-gray-600 text-sm">Total Cards</div>
          </div>
          <div class="bg-white rounded-2xl p-6 shadow-lg text-center">
            <div class="text-3xl font-bold text-green-600">{@stats.reviewed}</div>
            <div class="text-gray-600 text-sm">Reviewed</div>
          </div>
          <div class="bg-white rounded-2xl p-6 shadow-lg text-center">
            <div class="text-3xl font-bold text-yellow-600">{@stats.new}</div>
            <div class="text-gray-600 text-sm">New</div>
          </div>
          <div class="bg-white rounded-2xl p-6 shadow-lg text-center">
            <div class="text-3xl font-bold text-purple-600">{@stats.due}</div>
            <div class="text-gray-600 text-sm">Due</div>
          </div>
        </div>

        <!-- Cards List -->
        <%= if @flashcard_set.flashcards == [] do %>
          <div class="text-center py-20 bg-white rounded-3xl shadow-lg">
            <div class="text-6xl mb-4">🎴</div>
            <p class="text-2xl text-gray-600 mb-4">No cards yet</p>
            <p class="text-gray-500 mb-6">Add your first card to start studying!</p>
            <button
              phx-click="show_add_card_modal"
              class="btn btn-primary btn-lg rounded-full"
            >
              ➕ Add Your First Card
            </button>
          </div>
        <% else %>
          <div class="space-y-4">
            <%= for card <- @flashcard_set.flashcards do %>
              <div class="bg-white rounded-2xl p-6 shadow-lg hover:shadow-xl transition-shadow">
                <div class="flex justify-between items-start gap-4">
                  <div class="flex-1 grid grid-cols-2 gap-6">
                    <div>
                      <div class="text-sm font-semibold text-gray-500 mb-2">FRONT</div>
                      <p class="text-gray-800">{card.front}</p>
                    </div>
                    <div>
                      <div class="text-sm font-semibold text-gray-500 mb-2">BACK</div>
                      <p class="text-gray-800">{card.back}</p>
                    </div>
                  </div>
                  <div class="flex gap-2">
                    <button
                      phx-click="edit_card"
                      phx-value-id={card.id}
                      class="btn btn-sm btn-ghost"
                    >
                      ✏️
                    </button>
                    <button
                      phx-click="delete_card"
                      phx-value-id={card.id}
                      data-confirm="Delete this card?"
                      class="btn btn-sm btn-ghost text-red-600"
                    >
                      🗑️
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Add/Edit Card Modal -->
      <%= if @show_add_card_modal do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50" phx-click="hide_add_card_modal">
          <div class="bg-white rounded-2xl p-8 max-w-2xl w-full mx-4 shadow-2xl" phx-click="modal_content_click">
            <h2 class="text-2xl font-bold text-gray-800 mb-6">
              <%= if @editing_card, do: "Edit Card", else: "Add New Card" %>
            </h2>

            <form phx-submit="save_card" class="space-y-4">
              <div>
                <label class="block text-sm font-semibold text-gray-700 mb-2">Front (Question)</label>
                <textarea
                  name="front"
                  rows="4"
                  required
                  class="textarea textarea-bordered w-full"
                  placeholder="What is the question or prompt?"
                >{if @editing_card, do: @editing_card.front, else: ""}</textarea>
              </div>

              <div>
                <label class="block text-sm font-semibold text-gray-700 mb-2">Back (Answer)</label>
                <textarea
                  name="back"
                  rows="4"
                  required
                  class="textarea textarea-bordered w-full"
                  placeholder="What is the answer?"
                >{if @editing_card, do: @editing_card.back, else: ""}</textarea>
              </div>

              <div class="flex gap-3 pt-4">
                <button type="button" phx-click="hide_add_card_modal" class="btn btn-ghost flex-1">
                  Cancel
                </button>
                <button type="submit" class="btn btn-primary flex-1">
                  <%= if @editing_card, do: "Update Card", else: "Add Card" %>
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
