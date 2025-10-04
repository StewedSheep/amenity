defmodule AmenityWeb.SocialLive.Show do
  use AmenityWeb, :live_view

  alias Amenity.Social

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      post = Social.get_post!(id)
      {:ok, assign(socket, post: post, page_title: post.title, reply_content: "")}
    else
      {:ok, assign(socket, post: nil, page_title: "Post", reply_content: "")}
    end
  end

  @impl true
  def handle_event("submit_reply", %{"content" => content}, socket) do
    case Social.create_reply(
           %{"content" => content},
           socket.assigns.post.id,
           socket.assigns.current_scope.user.id
         ) do
      {:ok, _reply} ->
        post = Social.get_post!(socket.assigns.post.id)

        {:noreply,
         socket
         |> assign(:post, post)
         |> assign(:reply_content, "")
         |> put_flash(:info, "Reply posted successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to post reply")}
    end
  end

  @impl true
  def handle_event("delete_reply", %{"id" => id}, socket) do
    reply = Social.get_reply!(id)

    if Social.can_edit_reply?(reply, socket.assigns.current_scope.user.id) do
      {:ok, _} = Social.delete_reply(reply)
      post = Social.get_post!(socket.assigns.post.id)

      {:noreply,
       socket
       |> assign(:post, post)
       |> put_flash(:info, "Reply deleted successfully")}
    else
      {:noreply, put_flash(socket, :error, "You can only delete your own replies")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-base-200">
        <div class="max-w-6xl mx-auto px-4 py-6">
          <!-- Forum Header -->
          <div class="bg-gradient-to-r from-primary to-secondary text-primary-content rounded-t-lg p-4 shadow-lg">
            <div class="flex items-center justify-between">
              <div>
                <h1 class="text-3xl font-bold flex items-center gap-2">
                  <.icon name="hero-chat-bubble-left-right" class="w-8 h-8" />
                  Community Forum
                </h1>
                <p class="text-sm opacity-90 mt-1">Share your thoughts and connect with others</p>
              </div>
            </div>
          </div>

          <!-- Breadcrumbs -->
          <div class="bg-base-100 border-x border-base-300 p-3">
            <div class="breadcrumbs text-sm">
              <ul>
                <li><.link navigate={~p"/social"}>Forum</.link></li>
                <li>General Discussion</li>
                <li class="font-semibold"><%= @post.title %></li>
              </ul>
            </div>
          </div>

          <!-- Original Post -->
          <div class="bg-base-100 border-x border-b border-base-300">
            <div class="grid grid-cols-12">
              <!-- Author Sidebar -->
              <div class="col-span-2 bg-base-200 border-r border-base-300 p-4 text-center">
                <div class="avatar mb-2">
                  <%= if @post.user.profile_picture_url do %>
                    <div class="w-16 rounded-full">
                      <img src={@post.user.profile_picture_url} alt={@post.user.username} />
                    </div>
                  <% else %>
                    <div class="placeholder">
                      <div class="bg-primary text-primary-content rounded-full w-16">
                        <span class="text-2xl">
                          <%= String.first(@post.user.username) |> String.upcase() %>
                        </span>
                      </div>
                    </div>
                  <% end %>
                </div>
                <p class="font-bold text-sm"><%= @post.user.username %></p>
                <p class="text-xs text-base-content/60 mt-1">Member</p>
              </div>

              <!-- Post Content -->
              <div class="col-span-10 p-4">
                <div class="flex justify-between items-start mb-4">
                  <div>
                    <h2 class="text-2xl font-bold"><%= @post.title %></h2>
                    <p class="text-sm text-base-content/60">
                      Posted <%= Calendar.strftime(@post.inserted_at, "%B %d, %Y at %I:%M %p") %>
                      <%= if @post.edited_at do %>
                        <span class="badge badge-ghost badge-xs ml-2">edited</span>
                      <% end %>
                    </p>
                  </div>
                </div>

                <div class="prose max-w-none">
                  <p class="whitespace-pre-wrap"><%= @post.content %></p>
                </div>

                <%= if @post.images && length(@post.images) > 0 do %>
                  <div class="grid grid-cols-2 gap-3 mt-4">
                    <%= for image_url <- @post.images do %>
                      <img
                        src={image_url}
                        alt="Post image"
                        class="w-full h-48 object-cover rounded-lg"
                      />
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Replies Header -->
          <div class="bg-base-200 border-x border-b border-base-300 px-4 py-2 font-semibold text-sm">
            <%= length(@post.replies) %> <%= if length(@post.replies) == 1, do: "Reply", else: "Replies" %>
          </div>

          <!-- Replies -->
          <%= for reply <- @post.replies do %>
            <div class="bg-base-100 border-x border-b border-base-300">
              <div class="grid grid-cols-12">
                <!-- Author Sidebar -->
                <div class="col-span-2 bg-base-200 border-r border-base-300 p-4 text-center">
                  <div class="avatar mb-2">
                    <%= if reply.user.profile_picture_url do %>
                      <div class="w-12 rounded-full">
                        <img src={reply.user.profile_picture_url} alt={reply.user.username} />
                      </div>
                    <% else %>
                      <div class="placeholder">
                        <div class="bg-primary text-primary-content rounded-full w-12">
                          <span class="text-lg">
                            <%= String.first(reply.user.username) |> String.upcase() %>
                          </span>
                        </div>
                      </div>
                    <% end %>
                  </div>
                  <p class="font-bold text-xs"><%= reply.user.username %></p>
                </div>

                <!-- Reply Content -->
                <div class="col-span-10 p-4">
                  <div class="flex justify-between items-start mb-2">
                    <p class="text-xs text-base-content/60">
                      Posted <%= Calendar.strftime(reply.inserted_at, "%B %d, %Y at %I:%M %p") %>
                      <%= if reply.edited_at do %>
                        <span class="badge badge-ghost badge-xs ml-2">edited</span>
                      <% end %>
                    </p>
                    <%= if reply.user_id == @current_scope.user.id do %>
                      <button
                        phx-click="delete_reply"
                        phx-value-id={reply.id}
                        data-confirm="Are you sure you want to delete this reply?"
                        class="btn btn-ghost btn-xs text-error"
                      >
                        <.icon name="hero-trash" class="w-3 h-3" />
                        Delete
                      </button>
                    <% end %>
                  </div>

                  <div class="prose max-w-none">
                    <p class="whitespace-pre-wrap text-sm"><%= reply.content %></p>
                  </div>
                </div>
              </div>
            </div>
          <% end %>

          <!-- Reply Form -->
          <div class="bg-base-100 border-x border-b border-base-300 rounded-b-lg p-4">
            <h3 class="font-bold mb-3 flex items-center gap-2">
              <.icon name="hero-chat-bubble-left" class="w-5 h-5" />
              Post a Reply
            </h3>
            <form phx-submit="submit_reply">
              <textarea
                name="content"
                rows="4"
                class="textarea textarea-bordered w-full"
                placeholder="Write your reply..."
                required
              ><%= @reply_content %></textarea>
              <div class="flex justify-end mt-3">
                <button type="submit" class="btn btn-primary btn-sm gap-2">
                  <.icon name="hero-paper-airplane" class="w-4 h-4" />
                  Post Reply
                </button>
              </div>
            </form>
          </div>

          <!-- Back Button -->
          <div class="mt-4">
            <.link navigate={~p"/social"} class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-left" class="w-4 h-4" />
              Back to Forum
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
