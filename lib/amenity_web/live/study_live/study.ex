defmodule AmenityWeb.StudyLive.Study do
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
      # Get cards due for review
      due_cards = Study.get_due_flashcards(user_id, String.to_integer(id))

      if due_cards == [] do
        {:ok,
         socket
         |> put_flash(:info, "No cards to review right now!")
         |> push_navigate(to: ~p"/study/flashcards/#{id}")}
      else
        {:ok,
         socket
         |> assign(:flashcard_set, flashcard_set)
         |> assign(:due_cards, due_cards)
         |> assign(:current_index, 0)
         |> assign(:show_answer, false)
         |> assign(:cards_reviewed, 0)
         |> assign(:session_complete, false)}
      end
    end
  end

  @impl true
  def handle_event("show_answer", _params, socket) do
    {:noreply, assign(socket, :show_answer, true)}
  end

  def handle_event("rate", %{"quality" => quality_str}, socket) do
    quality = String.to_integer(quality_str)
    user_id = socket.assigns.current_scope.user.id
    current_card = Enum.at(socket.assigns.due_cards, socket.assigns.current_index)

    # Record the review
    Study.record_review(user_id, current_card.id, quality)

    # Move to next card
    next_index = socket.assigns.current_index + 1
    cards_reviewed = socket.assigns.cards_reviewed + 1

    if next_index >= length(socket.assigns.due_cards) do
      # Session complete
      {:noreply,
       socket
       |> assign(:session_complete, true)
       |> assign(:cards_reviewed, cards_reviewed)}
    else
      {:noreply,
       socket
       |> assign(:current_index, next_index)
       |> assign(:show_answer, false)
       |> assign(:cards_reviewed, cards_reviewed)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 via-purple-50 to-pink-50">
      <div class="max-w-4xl mx-auto px-4 py-8">
        <%= if @session_complete do %>
          <!-- Session Complete -->
          <div class="text-center py-20">
            <div class="text-8xl mb-6">🎉</div>
            <h1 class="text-4xl font-bold text-gray-800 mb-4">Session Complete!</h1>
            <p class="text-xl text-gray-600 mb-8">
              You reviewed {@cards_reviewed} cards
            </p>
            <div class="flex gap-4 justify-center">
              <.link
                navigate={~p"/study/flashcards/#{@flashcard_set.id}"}
                class="btn btn-primary btn-lg rounded-full"
              >
                Back to Set
              </.link>
              <.link
                navigate={~p"/study/flashcards"}
                class="btn btn-ghost btn-lg rounded-full"
              >
                All Sets
              </.link>
            </div>
          </div>
        <% else %>
          <!-- Study Session -->
          <% current_card = Enum.at(@due_cards, @current_index)
          progress = (@current_index + 1) / length(@due_cards) * 100 %>
          
    <!-- Header -->
          <div class="mb-8">
            <.link
              navigate={~p"/study/flashcards/#{@flashcard_set.id}"}
              class="text-blue-600 hover:text-blue-800 mb-4 inline-block"
            >
              ← Exit Study Session
            </.link>
            <h1 class="text-3xl font-bold text-gray-800 mb-2">{@flashcard_set.name}</h1>
            <div class="flex items-center gap-4">
              <div class="flex-1 bg-gray-200 rounded-full h-3">
                <div
                  class="bg-gradient-to-r from-blue-500 to-purple-500 h-3 rounded-full transition-all"
                  style={"width: #{progress}%"}
                >
                </div>
              </div>
              <span class="text-gray-600 font-semibold">
                {@current_index + 1} / {length(@due_cards)}
              </span>
            </div>
          </div>
          
    <!-- Flashcard -->
          <div class="bg-white rounded-3xl shadow-2xl p-12 mb-8 min-h-[400px] flex flex-col justify-center">
            <div class="text-center">
              <div class="text-sm font-semibold text-gray-500 mb-4">
                {if @show_answer, do: "ANSWER", else: "QUESTION"}
              </div>

              <%= if @show_answer do %>
                <!-- Show both question and answer -->
                <div class="mb-8 pb-8 border-b-2 border-gray-200">
                  <p class="text-xl text-gray-600">{current_card.front}</p>
                </div>
                <div>
                  <p class="text-3xl font-bold text-gray-800">{current_card.back}</p>
                </div>
              <% else %>
                <!-- Show only question -->
                <p class="text-3xl font-bold text-gray-800">{current_card.front}</p>
              <% end %>
            </div>
          </div>
          
    <!-- Actions -->
          <%= if @show_answer do %>
            <!-- Rating Buttons -->
            <div class="text-center mb-4">
              <p class="text-gray-600 mb-4">How well did you know this?</p>
            </div>
            <div class="grid grid-cols-3 gap-4">
              <button
                phx-click="rate"
                phx-value-quality="1"
                class="btn btn-lg bg-red-500 hover:bg-red-600 text-white rounded-2xl h-auto py-6"
              >
                <div>
                  <div class="text-2xl mb-1">😰</div>
                  <div class="font-bold">Again</div>
                  <div class="text-xs opacity-80">1 day</div>
                </div>
              </button>

              <button
                phx-click="rate"
                phx-value-quality="3"
                class="btn btn-lg bg-yellow-500 hover:bg-yellow-600 text-white rounded-2xl h-auto py-6"
              >
                <div>
                  <div class="text-2xl mb-1">🤔</div>
                  <div class="font-bold">Hard</div>
                  <div class="text-xs opacity-80">&lt; 3 days</div>
                </div>
              </button>

              <button
                phx-click="rate"
                phx-value-quality="4"
                class="btn btn-lg bg-blue-500 hover:bg-blue-600 text-white rounded-2xl h-auto py-6"
              >
                <div>
                  <div class="text-2xl mb-1">😊</div>
                  <div class="font-bold">Good</div>
                  <div class="text-xs opacity-80">&lt; 1 week</div>
                </div>
              </button>

              <button
                phx-click="rate"
                phx-value-quality="5"
                class="btn btn-lg bg-green-500 hover:bg-green-600 text-white rounded-2xl h-auto py-6 col-span-3"
              >
                <div>
                  <div class="text-2xl mb-1">🎯</div>
                  <div class="font-bold">Easy</div>
                  <div class="text-xs opacity-80">&lt; 2 weeks</div>
                </div>
              </button>
            </div>
          <% else %>
            <!-- Show Answer Button -->
            <div class="text-center">
              <button
                phx-click="show_answer"
                class="btn btn-primary btn-lg rounded-full px-12"
              >
                Show Answer
              </button>
            </div>
          <% end %>
          
    <!-- Keyboard Shortcuts Hint -->
          <div class="text-center mt-8 text-sm text-gray-500">
            <p>💡 Tip: Rate your recall honestly for optimal learning</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
