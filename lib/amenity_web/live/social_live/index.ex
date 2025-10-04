defmodule AmenityWeb.SocialLive.Index do
  use AmenityWeb, :live_view

  alias Amenity.Social

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      posts = Social.list_posts()
      {:ok, assign(socket, posts: posts, page_title: "Social")}
    else
      {:ok, assign(socket, posts: [], page_title: "Social")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    post = Social.get_post!(id)

    if Social.can_edit_post?(post, socket.assigns.current_scope.user.id) do
      socket
      |> assign(:page_title, "Edit Post")
      |> assign(:post, post)
    else
      socket
      |> put_flash(:error, "You can only edit your own posts")
      |> push_patch(to: ~p"/social")
    end
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Post")
    |> assign(:post, %Social.Post{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Social")
    |> assign(:post, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    post = Social.get_post!(id)

    if Social.can_edit_post?(post, socket.assigns.current_scope.user.id) do
      {:ok, _} = Social.delete_post(post)

      {:noreply,
       socket
       |> put_flash(:info, "Post deleted successfully")
       |> assign(:posts, Social.list_posts())}
    else
      {:noreply, put_flash(socket, :error, "You can only delete your own posts")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-gradient-to-br from-blue-50 via-purple-50 to-pink-50">
        <div class="max-w-6xl mx-auto px-4 py-6">
          <!-- Forum Header -->
          <div class="bg-gradient-to-r from-blue-600 via-purple-600 to-pink-600 text-white rounded-t-lg p-4 shadow-lg">
            <div class="flex items-center justify-between">
              <div>
                <h1 class="text-3xl font-bold flex items-center gap-2">
                  <.icon name="hero-chat-bubble-left-right" class="w-8 h-8" />
                  Community Forum
                </h1>
                <p class="text-sm opacity-90 mt-1">Share your thoughts and connect with others</p>
              </div>
              <div class="stats shadow bg-base-100 text-base-content">
                <div class="stat py-2 px-4">
                  <div class="stat-title text-xs">Total Posts</div>
                  <div class="stat-value text-2xl"><%= length(@posts) %></div>
                </div>
              </div>
            </div>
          </div>

          <!-- Action Bar -->
          <div class="bg-base-100 border-x border-base-300 p-3 flex items-center justify-between">
            <%= if @live_action in [:new, :edit] do %>
              <div class="breadcrumbs text-sm">
                <ul>
                  <li><.link patch={~p"/social"}>Forum</.link></li>
                  <li><%= if @live_action == :new, do: "New Topic", else: "Edit Post" %></li>
                </ul>
              </div>
            <% else %>
              <div class="breadcrumbs text-sm">
                <ul>
                  <li>Forum</li>
                  <li>General Discussion</li>
                </ul>
              </div>
              <.link patch={~p"/social/new"} class="btn btn-sm gap-2 bg-gradient-to-r from-blue-600 via-purple-600 to-pink-600 text-white hover:shadow-lg transition-all">
                <.icon name="hero-plus" class="w-4 h-4" />
                New Topic
              </.link>
            <% end %>
          </div>

          <%= if @live_action in [:new, :edit] do %>
            <div class="bg-base-100 border-x border-b border-base-300 p-4">
              <.live_component
                module={AmenityWeb.SocialLive.PostFormComponent}
                id={@post.id || :new}
                action={@live_action}
                post={@post}
                current_scope={@current_scope}
                patch={~p"/social"}
              />
            </div>
          <% end %>

          <!-- Posts List -->
          <%= if @posts == [] && @live_action == :index do %>
            <div class="bg-base-100 border border-base-300 rounded-b-lg p-12 text-center">
              <.icon name="hero-chat-bubble-left-right" class="w-16 h-16 mx-auto text-base-300 mb-4" />
              <h2 class="text-xl font-bold mb-2">No topics yet</h2>
              <p class="text-base-content/60 mb-4">Be the first to start a discussion!</p>
              <.link patch={~p"/social/new"} class="btn btn-sm bg-gradient-to-r from-blue-600 via-purple-600 to-pink-600 text-white hover:shadow-lg transition-all">
                <.icon name="hero-plus" class="w-4 h-4" />
                Create First Topic
              </.link>
            </div>
          <% else %>
            <%= if @live_action == :index do %>
              <div class="bg-base-100 border-x border-b border-base-300 rounded-b-lg overflow-hidden">
                <!-- Table Header -->
                <div class="bg-base-200 border-b border-base-300 px-4 py-2 grid grid-cols-12 gap-4 text-sm font-semibold">
                  <div class="col-span-6">Topic</div>
                  <div class="col-span-2 text-center">Author</div>
                  <div class="col-span-2 text-center">Replies</div>
                  <div class="col-span-2 text-center">Last Post</div>
                </div>

                <!-- Posts -->
                <%= for post <- @posts do %>
                  <div class="border-b border-base-300 hover:bg-base-200/50 transition-colors">
                    <div class="px-4 py-3 grid grid-cols-12 gap-4 items-center">
                      <!-- Topic Info -->
                      <div class="col-span-6">
                        <div class="flex items-start gap-3">
                          <.icon name="hero-document-text" class="w-5 h-5 text-primary mt-1 flex-shrink-0" />
                          <div class="min-w-0 flex-1">
                            <.link navigate={~p"/social/#{post.id}"}>
                              <h3 class="font-semibold text-base hover:text-primary transition-colors truncate">
                                <%= post.title %>
                              </h3>
                            </.link>
                            <p class="text-sm text-base-content/60 line-clamp-2 mt-1">
                              <%= post.content %>
                            </p>
                            <%= if post.images && length(post.images) > 0 do %>
                              <div class="flex gap-1 mt-2">
                                <span class="badge badge-sm gap-1">
                                  <.icon name="hero-photo" class="w-3 h-3" />
                                  <%= length(post.images) %>
                                </span>
                              </div>
                            <% end %>
                          </div>
                        </div>
                      </div>

                      <!-- Author -->
                      <div class="col-span-2 text-center">
                        <div class="flex flex-col items-center gap-1">
                          <div class="avatar">
                            <%= if post.user.profile_picture_url do %>
                              <div class="w-8 rounded-full">
                                <img src={post.user.profile_picture_url} alt={post.user.username} />
                              </div>
                            <% else %>
                              <div class="placeholder">
                                <div class="bg-primary text-primary-content rounded-full w-8">
                                  <span class="text-xs">
                                    <%= String.first(post.user.username) |> String.upcase() %>
                                  </span>
                                </div>
                              </div>
                            <% end %>
                          </div>
                          <span class="text-sm font-medium"><%= post.user.username %></span>
                        </div>
                      </div>

                      <!-- Replies -->
                      <div class="col-span-2 text-center">
                        <div class="text-lg font-bold"><%= Map.get(post, :reply_count, 0) %></div>
                        <div class="text-xs text-base-content/60">replies</div>
                      </div>

                      <!-- Last Post -->
                      <div class="col-span-2 text-center">
                        <div class="text-xs">
                          <%= Calendar.strftime(post.inserted_at, "%b %d, %Y") %>
                        </div>
                        <div class="text-xs text-base-content/60">
                          <%= Calendar.strftime(post.inserted_at, "%I:%M %p") %>
                        </div>
                        <%= if post.edited_at do %>
                          <span class="badge badge-ghost badge-xs mt-1">edited</span>
                        <% end %>
                        <%= if post.user_id == @current_scope.user.id do %>
                          <div class="flex gap-1 justify-center mt-2">
                            <.link
                              patch={~p"/social/#{post}/edit"}
                              class="btn btn-ghost btn-xs"
                              title="Edit"
                            >
                              <.icon name="hero-pencil-square" class="w-3 h-3" />
                            </.link>
                            <button
                              phx-click="delete"
                              phx-value-id={post.id}
                              data-confirm="Are you sure you want to delete this topic?"
                              class="btn btn-ghost btn-xs text-error"
                              title="Delete"
                            >
                              <.icon name="hero-trash" class="w-3 h-3" />
                            </button>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>

              <!-- Forum Footer -->
              <div class="mt-4 bg-base-100 border border-base-300 rounded-lg p-3 flex items-center justify-between text-sm">
                <div class="flex items-center gap-2">
                  <.icon name="hero-information-circle" class="w-4 h-4" />
                  <span class="text-base-content/60">
                    <%= length(@posts) %> <%= if length(@posts) == 1, do: "topic", else: "topics" %>
                  </span>
                </div>
                <.link patch={~p"/social/new"} class="btn btn-sm gap-2 bg-gradient-to-r from-blue-600 via-purple-600 to-pink-600 text-white hover:shadow-lg transition-all">
                  <.icon name="hero-plus" class="w-4 h-4" />
                  New Topic
                </.link>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
