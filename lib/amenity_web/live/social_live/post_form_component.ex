defmodule AmenityWeb.SocialLive.PostFormComponent do
  use AmenityWeb, :live_component

  alias Amenity.Social

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-100">
      <div class="border-b border-base-300 px-4 py-3 bg-base-200">
        <h3 class="text-lg font-bold flex items-center gap-2">
          <.icon name="hero-pencil-square" class="w-5 h-5" />
          <%= if @action == :new, do: "Post New Topic", else: "Edit Topic" %>
        </h3>
      </div>
      <div class="p-4">

      <.form
        for={@form}
        id={"post-form-#{@id}"}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-4">
          <.input field={@form[:title]} type="text" label="Title" placeholder="Enter post title..." />

          <.input
            field={@form[:content]}
            type="textarea"
            label="Content"
            placeholder="Share your thoughts..."
            rows="6"
          />

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Images (optional)</span>
            </label>

            <div class="tabs tabs-boxed mb-4">
              <a class="tab tab-active">Upload</a>
              <a class="tab">Link URL</a>
            </div>

            <div class="space-y-4">
              <div
                class="border-2 border-dashed border-base-300 rounded-lg p-8 text-center hover:border-primary transition-colors cursor-pointer bg-base-200/50"
                phx-drop-target={@uploads.images.ref}
              >
                <.live_file_input upload={@uploads.images} class="hidden" />
                <label for={@uploads.images.ref} class="cursor-pointer">
                  <.icon name="hero-photo" class="w-16 h-16 mx-auto opacity-40 mb-3" />
                  <p class="text-sm font-medium mb-1">
                    Click to upload or drag and drop images
                  </p>
                  <p class="text-xs opacity-60">
                    PNG, JPG, GIF up to 5MB each (max 4 images)
                  </p>
                </label>
              </div>

              <div class="divider">OR</div>

              <div class="join w-full">
                <input
                  type="text"
                  placeholder="Paste image URL (https://...)"
                  class="input input-bordered join-item flex-1"
                  value={@image_url}
                  phx-target={@myself}
                  name="image_url"
                />
                <button
                  type="button"
                  class="btn join-item bg-gradient-to-r from-blue-600 via-purple-600 to-pink-600 text-white hover:shadow-lg transition-all"
                  phx-click="add-image-url"
                  phx-target={@myself}
                  disabled={@image_url == ""}
                >
                  <.icon name="hero-plus" class="w-5 h-5" />
                  Add
                </button>
              </div>
            </div>

            <%= for entry <- @uploads.images.entries do %>
              <div class="alert mt-3">
                <div class="flex items-center gap-3 flex-1">
                  <.live_img_preview entry={entry} class="w-16 h-16 object-cover rounded-lg" />
                  <div class="flex-1">
                    <p class="text-sm font-medium"><%= entry.client_name %></p>
                    <progress class="progress progress-primary w-full" value={entry.progress} max="100"></progress>
                  </div>
                </div>
                <button
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  phx-target={@myself}
                  class="btn btn-ghost btn-sm btn-circle"
                >
                  <.icon name="hero-x-mark" class="w-5 h-5" />
                </button>
              </div>
            <% end %>

            <%= for err <- upload_errors(@uploads.images) do %>
              <div class="alert alert-error mt-2">
                <.icon name="hero-exclamation-circle" class="w-5 h-5" />
                <span><%= error_to_string(err) %></span>
              </div>
            <% end %>

            <%= if @linked_images != [] do %>
              <div class="mt-4">
                <p class="text-sm font-medium mb-2">Linked Images:</p>
                <div class="grid grid-cols-2 gap-2">
                  <%= for image_url <- @linked_images do %>
                    <div class="relative group">
                      <img
                        src={image_url}
                        alt="Linked image"
                        class="w-full h-32 object-cover rounded-lg"
                      />
                      <button
                        type="button"
                        phx-click="remove-linked-image"
                        phx-value-url={image_url}
                        phx-target={@myself}
                        class="btn btn-error btn-sm btn-circle absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity"
                      >
                        <.icon name="hero-x-mark" class="w-4 h-4" />
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <div class="flex justify-end gap-2 pt-4 border-t border-base-300">
            <button
              type="button"
              phx-click="cancel"
              phx-target={@myself}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
              Cancel
            </button>
            <button
              type="submit"
              class="btn btn-sm gap-2 bg-gradient-to-r from-blue-600 via-purple-600 to-pink-600 text-white hover:shadow-lg transition-all"
            >
              <.icon name="hero-paper-airplane" class="w-4 h-4" />
              <%= if @action == :new, do: "Submit Topic", else: "Update Topic" %>
            </button>
          </div>
        </div>
      </.form>
      </div>
    </div>
    """
  end

  @impl true
  def update(%{post: post} = assigns, socket) do
    changeset = Social.change_post(post)
    linked_images = post.images || []

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(changeset))
     |> assign(:image_url, "")
     |> assign(:linked_images, linked_images)
     |> allow_upload(:images,
       accept: ~w(.jpg .jpeg .png .gif),
       max_entries: 4,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_event("validate", %{"post" => post_params}, socket) do
    changeset =
      socket.assigns.post
      |> Social.change_post(post_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("update-image-url", %{"image_url" => url}, socket) do
    {:noreply, assign(socket, :image_url, url)}
  end

  @impl true
  def handle_event("add-image-url", _params, socket) do
    url = String.trim(socket.assigns.image_url)

    if valid_image_url?(url) do
      linked_images = socket.assigns.linked_images ++ [url]

      {:noreply,
       socket
       |> assign(:linked_images, linked_images)
       |> assign(:image_url, "")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please enter a valid image URL (must start with http:// or https://)")}
    end
  end

  @impl true
  def handle_event("remove-linked-image", %{"url" => url}, socket) do
    linked_images = Enum.reject(socket.assigns.linked_images, &(&1 == url))
    {:noreply, assign(socket, :linked_images, linked_images)}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :images, ref)}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply, push_patch(socket, to: socket.assigns.patch)}
  end

  @impl true
  def handle_event("save", %{"post" => post_params}, socket) do
    save_post(socket, socket.assigns.action, post_params)
  end

  defp save_post(socket, :edit, post_params) do
    uploaded_files = consume_uploaded_entries(socket, :images, &upload_image/2)
    linked_images = socket.assigns.linked_images
    all_images = linked_images ++ uploaded_files

    post_params = Map.put(post_params, "images", all_images)

    case Social.update_post(socket.assigns.post, post_params) do
      {:ok, _post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_post(socket, :new, post_params) do
    uploaded_files = consume_uploaded_entries(socket, :images, &upload_image/2)
    linked_images = socket.assigns.linked_images
    all_images = linked_images ++ uploaded_files

    post_params = Map.put(post_params, "images", all_images)

    case Social.create_post(post_params, socket.assigns.current_scope.user.id) do
      {:ok, _post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp upload_image({path, entry}, _socket) do
    filename = "#{System.unique_integer([:positive])}-#{entry.client_name}"
    dest = Path.join(["priv", "static", "uploads", filename])

    File.mkdir_p!(Path.dirname(dest))
    File.cp!(path, dest)

    "/uploads/#{filename}"
  end

  defp error_to_string(:too_large), do: "File is too large (max 5MB)"
  defp error_to_string(:not_accepted), do: "File type not accepted"
  defp error_to_string(:too_many_files), do: "Too many files (max 4)"

  defp valid_image_url?(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] && uri.host != nil
  end
end
