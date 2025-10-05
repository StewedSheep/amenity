defmodule AmenityWeb.BibleLive.Reader do
  use AmenityWeb, :live_view

  alias Amenity.Bible
  alias Amenity.Accounts

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
      |> assign(:annotations, [])
      |> assign(:show_annotation_modal, false)
      |> assign(:selected_verse, nil)
      |> assign(:is_read, false)
      |> assign(:generating_flashcards, false)
      |> assign(:show_action_menu, false)
      |> assign(:mark_with_flashcards, true)
      |> assign(:generated_flashcard_set, nil)
      |> assign(:show_flashcard_preview, false)

    if connected?(socket) do
      send(self(), :load_chapter)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_chapter, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Bible.fetch_chapter(
           socket.assigns.book,
           socket.assigns.chapter,
           socket.assigns.translation
         ) do
      {:ok, %{verses: verses}} ->
        # Load annotations for this chapter
        annotations =
          Bible.list_chapter_annotations(user_id, socket.assigns.book, socket.assigns.chapter)

        # Check if chapter is already read
        is_read = Bible.chapter_read?(user_id, socket.assigns.book, socket.assigns.chapter)

        {:noreply,
         socket
         |> assign(:verses, verses)
         |> assign(:annotations, annotations)
         |> assign(:is_read, is_read)
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, reason)
         |> assign(:loading, false)}
    end
  end

  def handle_info({:annotation_saved, _annotation}, socket) do
    user_id = socket.assigns.current_scope.user.id

    annotations =
      Bible.list_chapter_annotations(user_id, socket.assigns.book, socket.assigns.chapter)

    {:noreply,
     socket
     |> assign(:annotations, annotations)
     |> assign(:show_annotation_modal, false)
     |> put_flash(:info, "Annotation saved!")}
  end

  def handle_info({:annotation_deleted, _annotation}, socket) do
    user_id = socket.assigns.current_scope.user.id

    annotations =
      Bible.list_chapter_annotations(user_id, socket.assigns.book, socket.assigns.chapter)

    {:noreply,
     socket
     |> assign(:annotations, annotations)
     |> assign(:show_annotation_modal, false)
     |> put_flash(:info, "Annotation deleted!")}
  end

  @impl true
  def handle_event("open_annotation", %{"verse" => verse}, socket) do
    verse_num = String.to_integer(verse)

    {:noreply,
     socket
     |> assign(:selected_verse, verse_num)
     |> assign(:show_annotation_modal, true)}
  end

  def handle_event("close_annotation_modal", _params, socket) do
    {:noreply, assign(socket, :show_annotation_modal, false)}
  end

  def handle_event("toggle_flashcard_mode", _params, socket) do
    {:noreply, assign(socket, :mark_with_flashcards, !socket.assigns.mark_with_flashcards)}
  end

  def handle_event("mark_as_read", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Bible.mark_chapter_as_read(user_id, socket.assigns.book, socket.assigns.chapter) do
      {:ok, _chapter_read} ->
        # Check if this is the user's first chapter read
        user = socket.assigns.current_scope.user
        chapter_reads = Bible.list_chapter_reads(user_id)
        if length(chapter_reads) == 1 and "first_reader" not in user.achievements do
          Accounts.unlock_achievement(user, "first_reader")
        end

        if socket.assigns.mark_with_flashcards do
          # Generate flashcards
          send(self(), {:generate_flashcards, user_id})

          {:noreply,
           socket
           |> assign(:is_read, true)
           |> assign(:generating_flashcards, true)
           |> put_flash(:info, "✨ Chapter marked as read! Generating flashcards...")}
        else
          # Just mark as read
          {:noreply,
           socket
           |> assign(:is_read, true)
           |> put_flash(:info, "✨ Chapter marked as read!")}
        end

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not mark chapter as read")}
    end
  end

  def handle_event("unmark_as_read", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Bible.unmark_chapter_as_read(user_id, socket.assigns.book, socket.assigns.chapter) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:is_read, false)
         |> put_flash(:info, "Chapter unmarked")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not unmark chapter")}
    end
  end


  def handle_info({:generate_flashcards, user_id}, socket) do
    case Amenity.Study.generate_flashcards_from_chapter(
           user_id,
           socket.assigns.book,
           socket.assigns.chapter,
           socket.assigns.verses,
           socket.assigns.annotations
         ) do
      {:ok, flashcard_set} ->
        # Reload with flashcards preloaded
        flashcard_set = Amenity.Study.get_flashcard_set!(flashcard_set.id)
        
        {:noreply,
         socket
         |> assign(:generating_flashcards, false)
         |> assign(:generated_flashcard_set, flashcard_set)
         |> assign(:show_flashcard_preview, true)
         |> put_flash(:info, "✨ Flashcards generated successfully!")}

      {:error, reason} ->
        require Logger
        Logger.error("Flashcard generation failed: #{inspect(reason)}")

        {:noreply,
         socket
         |> assign(:generating_flashcards, false)
         |> put_flash(:error, "Failed to generate flashcards")}
    end
  end

  def handle_event("close_flashcard_preview", _params, socket) do
    {:noreply, assign(socket, :show_flashcard_preview, false)}
  end

  def handle_event("add_card_to_set", %{"card_id" => card_id, "value" => set_id}, socket) when set_id != "" do
    card = Enum.find(socket.assigns.generated_flashcard_set.flashcards, fn c -> 
      c.id == String.to_integer(card_id) 
    end)
    
    if card do
      case Amenity.Study.create_flashcard(%{
        flashcard_set_id: String.to_integer(set_id),
        front: card.front,
        back: card.back,
        position: 0
      }) do
        {:ok, _} ->
          {:noreply, put_flash(socket, :info, "✨ Card added to set!")}
        
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not add card")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_card_to_set", _params, socket) do
    {:noreply, socket}
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
          <h1 class="text-5xl font-bold mb-2 bg-gradient-to-r from-purple-600 via-pink-600 to-yellow-600 bg-clip-text text-transparent">
            {@book} {@chapter}
          </h1>
          <p class="text-gray-600 text-lg">📖 {@translation} Translation</p>
        </div>

    <!-- Loading state -->
        <div :if={@loading} class="text-center py-20">
          <div class="inline-block animate-spin rounded-full h-16 w-16 border-t-4 border-b-4 border-purple-500">
          </div>
          <p class="mt-4 text-xl text-gray-600">Loading chapter...</p>
        </div>

    <!-- Error state -->
        <div :if={@error} class="alert alert-error shadow-lg">
          <span>❌ Error: {@error}</span>
        </div>

    <!-- Verses -->
        <div
          :if={!@loading and !@error}
          class="space-y-4"
        >
          <div
            :for={verse <- @verses}
            class="bg-white rounded-2xl p-6 shadow-md hover:shadow-xl transition-shadow border-l-4 border-purple-400"
          >
            <div class="flex items-start gap-4">
              <span class="flex-shrink-0 w-10 h-10 bg-gradient-to-br from-purple-400 to-pink-400 rounded-full flex items-center justify-center text-white font-bold text-lg shadow-md">
                {verse.verse}
              </span>
              <div class="flex-1">
                <div class="relative">
                  <% verse_annotations = Enum.filter(@annotations, fn a -> a.verse == verse.verse end) %>
                  <div
                    id={"verse-#{verse.verse}"}
                    phx-click="open_annotation"
                    phx-value-verse={verse.verse}
                    class="text-gray-800 text-lg leading-relaxed cursor-pointer rounded p-2 transition-colors hover:bg-yellow-50"
                  >
                    <%= if verse_annotations != [] do %>
                      {render_multi_highlighted_text(verse.text, verse_annotations)}
                    <% else %>
                      {verse.text}
                    <% end %>
                  </div>

                  <%= if @show_annotation_modal && @selected_verse == verse.verse do %>
                    <div
                      class="absolute left-0 top-full mt-2 z-[100] w-full md:w-96"
                      phx-click-away="close_annotation_modal"
                    >
                      <.live_component
                        module={AmenityWeb.BibleLive.AnnotationComponent}
                        id={"annotation-#{@selected_verse}"}
                        user_id={@current_scope.user.id}
                        book={@book}
                        chapter={@chapter}
                        verse={@selected_verse}
                      />
                    </div>
                  <% end %>
                </div>
                <%= if verse_annotations != [] do %>
                  <div class="mt-3 space-y-2">
                    <%= for annotation <- verse_annotations do %>
                      <%= if annotation.note && annotation.note != "" do %>
                        <div class={[
                          "p-3 rounded-lg border-l-4",
                          annotation_color_class(annotation.color)
                        ]}>
                          <p class="text-sm text-gray-600 italic">{annotation.note}</p>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>

    <!-- Navigation buttons - Fixed to sides -->
      <button
        :if={@chapter > 1}
        phx-click="prev_chapter"
        class="fixed left-6 top-1/2 -translate-y-1/2 z-50 btn btn-circle btn-lg bg-purple-500 hover:bg-purple-600 text-white shadow-2xl hover:shadow-3xl hover:scale-110 transition-all"
      >
        ←
      </button>

      <button
        phx-click="next_chapter"
        class="fixed right-6 top-1/2 -translate-y-1/2 z-50 btn btn-circle btn-lg bg-pink-500 hover:bg-pink-600 text-white shadow-2xl hover:shadow-3xl hover:scale-110 transition-all"
      >
        →
      </button>

    <!-- Floating Action Buttons - Bottom Right -->
      <div class="fixed bottom-6 right-6 z-50 flex flex-col items-end gap-4">
        <%= if @generating_flashcards do %>
          <div class="btn bg-blue-600 text-white font-semibold px-6 py-3 rounded-full shadow-2xl cursor-wait">
            <span class="loading loading-spinner loading-sm"></span>
            Generating flashcards...
          </div>
        <% else %>
          <.link
            navigate={~p"/bible"}
            class="btn btn-lg bg-purple-500 hover:bg-purple-600 text-white rounded-2xl shadow-xl hover:shadow-2xl hover:scale-105 transition-all whitespace-nowrap px-8 py-4"
          >
            📚 Book List
          </.link>

          <%= if @is_read do %>
            <button
              phx-click="unmark_as_read"
              class="btn btn-lg bg-gradient-to-r from-green-400 via-blue-500 to-purple-600 hover:from-gray-500 hover:via-gray-600 hover:to-gray-700 text-white font-semibold px-8 py-4 rounded-2xl shadow-xl hover:shadow-2xl hover:scale-105 transition-all whitespace-nowrap"
            >
              ✅ Unmark as Read
            </button>
          <% else %>
            <!-- Mark as Read with Toggle -->
            <div class="bg-white rounded-2xl shadow-xl p-4 border-2 border-green-400">
              <!-- Toggle Switch -->
              <div class="flex items-center justify-between mb-3">
                <span class="text-sm font-semibold text-gray-700">Include Flashcards:</span>
                <button
                  phx-click="toggle_flashcard_mode"
                  class={"relative inline-flex h-8 w-14 items-center rounded-full transition-colors #{if @mark_with_flashcards, do: "bg-blue-500", else: "bg-gray-300"}"}
                >
                  <span class={"inline-block h-6 w-6 transform rounded-full bg-white transition-transform #{if @mark_with_flashcards, do: "translate-x-7", else: "translate-x-1"}"}></span>
                </button>
              </div>

              <!-- Main Action Button -->
              <button
                phx-click="mark_as_read"
                class={"btn btn-lg w-full rounded-xl shadow-lg hover:shadow-2xl hover:scale-105 transition-all text-white font-semibold #{if @mark_with_flashcards, do: "bg-blue-500 hover:bg-blue-600", else: "bg-green-500 hover:bg-green-600"}"}
              >
                <%= if @mark_with_flashcards do %>
                  🎴 Mark as Read + Flashcards
                <% else %>
                  ✓ Mark as Read Only
                <% end %>
              </button>
            </div>
          <% end %>
        <% end %>
      </div>

      <!-- Flashcard Preview Modal -->
      <%= if @show_flashcard_preview && @generated_flashcard_set do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50 p-4" phx-click="close_flashcard_preview">
          <div class="bg-white rounded-3xl p-8 max-w-4xl w-full max-h-[90vh] overflow-y-auto shadow-2xl" phx-click={JS.exec("phx-click", to: "#flashcard-preview-content")}>
            <div id="flashcard-preview-content">
              <div class="flex justify-between items-start mb-6">
                <div>
                  <h2 class="text-3xl font-bold text-gray-800 mb-2">Generated Flashcards</h2>
                  <p class="text-gray-600">{@generated_flashcard_set.name} • {length(@generated_flashcard_set.flashcards)} cards</p>
                </div>
                <button
                  phx-click="close_flashcard_preview"
                  class="text-gray-400 hover:text-gray-600 text-2xl"
                >
                  ✕
                </button>
              </div>

              <!-- Flashcard Grid -->
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
                <%= for card <- @generated_flashcard_set.flashcards do %>
                  <div class="bg-gradient-to-br from-blue-50 to-purple-50 rounded-2xl p-6 border-2 border-blue-200">
                    <div class="mb-4">
                      <div class="text-xs font-semibold text-blue-600 mb-2">QUESTION</div>
                      <div class="text-gray-800 font-medium">{card.front}</div>
                    </div>
                    <div class="mb-4">
                      <div class="text-xs font-semibold text-purple-600 mb-2">ANSWER</div>
                      <div class="text-gray-700">{card.back}</div>
                    </div>
                    
                    <!-- Add to Set Dropdown -->
                    <div class="pt-4 border-t border-blue-200">
                      <select
                        phx-change="add_card_to_set"
                        phx-value-card_id={card.id}
                        class="select select-sm select-bordered w-full"
                      >
                        <option value="">➕ Add to another set...</option>
                        <%= for set <- Amenity.Study.list_flashcard_sets(@current_scope.user.id) do %>
                          <%= if set.id != @generated_flashcard_set.id do %>
                            <option value={set.id}>{set.name}</option>
                          <% end %>
                        <% end %>
                      </select>
                    </div>
                  </div>
                <% end %>
              </div>

              <div class="flex gap-3">
                <button
                  phx-click="close_flashcard_preview"
                  class="btn btn-ghost flex-1"
                >
                  Close
                </button>
                <.link
                  navigate={~p"/study/flashcards/#{@generated_flashcard_set.id}"}
                  class="btn btn-primary flex-1"
                >
                  View Full Set →
                </.link>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp annotation_color_class("yellow"), do: "bg-yellow-50 border-yellow-400"
  defp annotation_color_class("blue"), do: "bg-blue-50 border-blue-400"
  defp annotation_color_class("green"), do: "bg-green-50 border-green-400"
  defp annotation_color_class("pink"), do: "bg-pink-50 border-pink-400"
  defp annotation_color_class("purple"), do: "bg-purple-50 border-purple-400"
  defp annotation_color_class(_), do: "bg-gray-50 border-gray-400"

  defp render_multi_highlighted_text(verse_text, annotations) do
    # Build a list of all highlight ranges
    highlights =
      annotations
      |> Enum.map(fn annotation ->
        regex = Regex.compile!(Regex.escape(annotation.content), "i")

        case Regex.run(regex, verse_text, return: :index) do
          [{start, length}] -> {start, length, annotation.color}
          nil -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn {start, _, _} -> start end)
      |> remove_overlaps()

    if highlights == [] do
      Phoenix.HTML.raw(verse_text)
    else
      # Render text with multiple highlights
      render_with_highlights(verse_text, highlights, 0, [])
    end
  end

  # Remove overlapping highlights - keep the first one
  defp remove_overlaps([]), do: []

  defp remove_overlaps([first | rest]) do
    {start1, length1, _} = first
    end1 = start1 + length1

    filtered_rest =
      rest
      |> Enum.reject(fn {start2, length2, _} ->
        end2 = start2 + length2
        # Check if they overlap
        (start2 < end1 && start2 >= start1) || (end2 > start1 && end2 <= end1) ||
          (start2 <= start1 && end2 >= end1)
      end)

    [first | remove_overlaps(filtered_rest)]
  end

  defp render_with_highlights(text, [], current_pos, acc) do
    # Add remaining text
    remaining = String.slice(text, current_pos, String.length(text))
    parts = Enum.reverse([{:text, remaining, nil} | acc])

    assigns = %{parts: parts}

    ~H"""
    <%= for part <- @parts do %>
      <%= case part do %>
        <% {:text, content, _} -> %>
          {content}
        <% {:highlight, content, color} -> %>
          <mark class={highlight_mark_class(color)}>{content}</mark>
      <% end %>
    <% end %>
    """
  end

  defp render_with_highlights(text, [{start, length, color} | rest], current_pos, acc) do
    # Add text before highlight
    before = String.slice(text, current_pos, start - current_pos)
    highlight = String.slice(text, start, length)

    new_acc = [{:highlight, highlight, color}, {:text, before, nil} | acc]
    render_with_highlights(text, rest, start + length, new_acc)
  end

  defp highlight_mark_class("yellow"), do: "bg-yellow-200 px-1 rounded"
  defp highlight_mark_class("blue"), do: "bg-blue-200 px-1 rounded"
  defp highlight_mark_class("green"), do: "bg-green-200 px-1 rounded"
  defp highlight_mark_class("pink"), do: "bg-pink-200 px-1 rounded"
  defp highlight_mark_class("purple"), do: "bg-purple-200 px-1 rounded"
  defp highlight_mark_class(_), do: "bg-gray-200 px-1 rounded"
end
