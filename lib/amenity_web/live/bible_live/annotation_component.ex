defmodule AmenityWeb.BibleLive.AnnotationComponent do
  use AmenityWeb, :live_component

  alias Amenity.Bible

  @impl true
  def update(assigns, socket) do
    # Load all annotations for this verse
    annotations =
      Bible.list_verse_annotations(assigns.user_id, assigns.book, assigns.chapter, assigns.verse)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:annotations, annotations)
     |> assign(:show_form, false)
     |> assign(:editing_annotation, nil)
     |> assign_form()}
  end

  defp assign_form(socket) do
    annotation = socket.assigns[:editing_annotation] || %Bible.Annotation{}
    changeset = Bible.change_annotation(annotation)
    assign(socket, :form, to_form(changeset))
  end

  @impl true
  def handle_event("show_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_annotation, nil)
     |> assign_form()}
  end

  def handle_event("edit_annotation", %{"id" => id}, socket) do
    annotation = Enum.find(socket.assigns.annotations, fn a -> a.id == String.to_integer(id) end)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_annotation, annotation)
     |> assign_form()}
  end

  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, :show_form, false)}
  end

  def handle_event("save", %{"annotation" => annotation_params}, socket) do
    if socket.assigns.editing_annotation do
      save_annotation(socket, :edit, annotation_params)
    else
      save_annotation(socket, :new, annotation_params)
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    annotation = Enum.find(socket.assigns.annotations, fn a -> a.id == String.to_integer(id) end)

    case Bible.delete_annotation(annotation) do
      {:ok, _} ->
        annotations =
          Bible.list_verse_annotations(
            socket.assigns.user_id,
            socket.assigns.book,
            socket.assigns.chapter,
            socket.assigns.verse
          )

        notify_parent({:annotation_deleted, annotation})

        {:noreply, assign(socket, :annotations, annotations)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not delete annotation")}
    end
  end

  defp save_annotation(socket, :new, annotation_params) do
    params =
      annotation_params
      |> Map.put("user_id", socket.assigns.user_id)
      |> Map.put("book", socket.assigns.book)
      |> Map.put("chapter", socket.assigns.chapter)
      |> Map.put("verse", socket.assigns.verse)

    # Validate content
    content = Map.get(params, "content", "") |> String.trim()

    changeset = Bible.change_annotation(%Bible.Annotation{}, params)

    changeset =
      cond do
        String.length(content) < 3 ->
          Ecto.Changeset.add_error(changeset, :content, "must be at least 3 characters")

        has_overlap?(socket.assigns.annotations, content) ->
          Ecto.Changeset.add_error(changeset, :content, "this text is already annotated")

        true ->
          changeset
      end

    if changeset.errors != [] do
      {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :validate)))}
    else
      case Bible.create_annotation(params) do
        {:ok, annotation} ->
          annotations =
            Bible.list_verse_annotations(
              socket.assigns.user_id,
              socket.assigns.book,
              socket.assigns.chapter,
              socket.assigns.verse
            )

          notify_parent({:annotation_saved, annotation})

          {:noreply,
           socket
           |> assign(:annotations, annotations)
           |> assign(:show_form, false)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end
  end

  defp has_overlap?(annotations, new_content) do
    new_lower = String.downcase(new_content)

    Enum.any?(annotations, fn annotation ->
      existing_lower = String.downcase(annotation.content)
      # Check if the new content overlaps with existing annotation content
      String.contains?(existing_lower, new_lower) ||
        String.contains?(new_lower, existing_lower)
    end)
  end

  defp save_annotation(socket, :edit, annotation_params) do
    case Bible.update_annotation(socket.assigns.editing_annotation, annotation_params) do
      {:ok, annotation} ->
        annotations =
          Bible.list_verse_annotations(
            socket.assigns.user_id,
            socket.assigns.book,
            socket.assigns.chapter,
            socket.assigns.verse
          )

        notify_parent({:annotation_saved, annotation})

        {:noreply,
         socket
         |> assign(:annotations, annotations)
         |> assign(:show_form, false)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), msg)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl p-6 shadow-2xl border-2 border-purple-200 max-h-[80vh] overflow-y-auto">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-xl font-bold text-gray-800">
          Annotations for {@book} {@chapter}:{@verse}
        </h3>
        <button
          phx-click="close_annotation_modal"
          class="text-gray-400 hover:text-gray-600 text-2xl leading-none"
        >
          ✕
        </button>
      </div>

      <%= if !@show_form do %>
        <!-- List of existing annotations -->
        <div class="space-y-3 mb-4">
          <%= if @annotations == [] do %>
            <p class="text-gray-500 text-center py-4">No annotations yet</p>
          <% else %>
            <div
              :for={annotation <- @annotations}
              class={[
                "p-4 rounded-lg border-l-4",
                annotation_border_class(annotation.color)
              ]}
            >
              <div class="flex justify-between items-start mb-2">
                <span class={[
                  "text-xs font-semibold px-2 py-1 rounded",
                  color_badge_class(annotation.color)
                ]}>
                  {String.upcase(annotation.color)}
                </span>
                <div class="flex gap-2">
                  <button
                    phx-click="edit_annotation"
                    phx-value-id={annotation.id}
                    phx-target={@myself}
                    class="text-blue-600 hover:text-blue-800 text-sm"
                  >
                    ✏️ Edit
                  </button>
                  <button
                    phx-click="delete"
                    phx-value-id={annotation.id}
                    phx-target={@myself}
                    data-confirm="Delete this annotation?"
                    class="text-red-600 hover:text-red-800 text-sm"
                  >
                    🗑️ Delete
                  </button>
                </div>
              </div>
              <p class="text-sm font-medium text-gray-700 mb-1">"{annotation.content}"</p>
              <%= if annotation.note && annotation.note != "" do %>
                <p class="text-sm text-gray-600 italic mt-2">{annotation.note}</p>
              <% end %>
            </div>
          <% end %>
        </div>
        
    <!-- Add New Button -->
        <button
          phx-click="show_form"
          phx-target={@myself}
          class="btn btn-primary w-full"
        >
          ➕ Add New Annotation
        </button>
      <% else %>
        <.form for={@form} phx-target={@myself} phx-submit="save" class="space-y-4">
          <div>
            <label class="block text-sm font-semibold text-gray-700 mb-2">
              Highlight Text
            </label>
            <textarea
              name="annotation[content]"
              rows="3"
              class="textarea textarea-bordered w-full"
              placeholder="Enter the verse text you want to highlight..."
              required
            >{@form[:content].value}</textarea>
            <%= if @form[:content].errors != [] do %>
              <p class="text-xs text-red-600 mt-1">
                {elem(hd(@form[:content].errors), 0)}
              </p>
            <% else %>
              <p class="text-xs text-gray-500 mt-1">
                The text from the verse you're annotating (min 3 characters)
              </p>
            <% end %>
          </div>

          <div>
            <label class="block text-sm font-semibold text-gray-700 mb-2">
              Personal Notes (Optional)
            </label>
            <textarea
              name="annotation[note]"
              rows="5"
              class="textarea textarea-bordered w-full"
              placeholder="Add your personal notes, reflections, or insights..."
            >{@form[:note].value}</textarea>
            <p class="text-xs text-gray-500 mt-1">Your private thoughts and reflections</p>
          </div>

          <div>
            <label class="block text-sm font-semibold text-gray-700 mb-2">
              Highlight Color
            </label>
            <div class="flex gap-3">
              <label
                :for={color <- ["yellow", "blue", "green", "pink", "purple"]}
                class="cursor-pointer"
              >
                <input
                  type="radio"
                  name="annotation[color]"
                  value={color}
                  checked={
                    @form[:color].value == color || (is_nil(@form[:color].value) && color == "yellow")
                  }
                  class="hidden peer"
                />
                <div class={[
                  "w-10 h-10 rounded-full border-4 transition-all peer-checked:scale-110 peer-checked:border-gray-800",
                  color_class(color)
                ]}>
                </div>
              </label>
            </div>
          </div>

          <div class="flex gap-3 pt-4">
            <button
              type="button"
              phx-click="cancel_form"
              phx-target={@myself}
              class="btn btn-ghost"
            >
              Cancel
            </button>
            <button type="submit" class="btn btn-primary flex-1">
              {if @editing_annotation, do: "Update", else: "Save"}
            </button>
          </div>
        </.form>
      <% end %>
    </div>
    """
  end

  defp color_class("yellow"), do: "bg-yellow-200 border-yellow-300"
  defp color_class("blue"), do: "bg-blue-200 border-blue-300"
  defp color_class("green"), do: "bg-green-200 border-green-300"
  defp color_class("pink"), do: "bg-pink-200 border-pink-300"
  defp color_class("purple"), do: "bg-purple-200 border-purple-300"

  defp annotation_border_class("yellow"), do: "border-yellow-400 bg-yellow-50"
  defp annotation_border_class("blue"), do: "border-blue-400 bg-blue-50"
  defp annotation_border_class("green"), do: "border-green-400 bg-green-50"
  defp annotation_border_class("pink"), do: "border-pink-400 bg-pink-50"
  defp annotation_border_class("purple"), do: "border-purple-400 bg-purple-50"
  defp annotation_border_class(_), do: "border-gray-400 bg-gray-50"

  defp color_badge_class("yellow"), do: "bg-yellow-200 text-yellow-800"
  defp color_badge_class("blue"), do: "bg-blue-200 text-blue-800"
  defp color_badge_class("green"), do: "bg-green-200 text-green-800"
  defp color_badge_class("pink"), do: "bg-pink-200 text-pink-800"
  defp color_badge_class("purple"), do: "bg-purple-200 text-purple-800"
  defp color_badge_class(_), do: "bg-gray-200 text-gray-800"
end
