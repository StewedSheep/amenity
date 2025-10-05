defmodule AmenityWeb.FriendsLive.Index do
  use AmenityWeb, :live_view

  import Ecto.Query
  alias Amenity.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    socket =
      socket
      |> assign(:friends, Accounts.get_friends(user_id))
      |> assign(:pending_requests, Accounts.get_pending_requests(user_id))
      |> assign(:sent_requests, Accounts.get_sent_requests(user_id))
      |> assign(:search_query, "")
      |> assign(:search_results, [])

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    user_id = socket.assigns.current_scope.user.id

    results =
      if String.length(query) >= 2 do
        Accounts.search_users(query, user_id)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)}
  end

  def handle_event("send_request", %{"user_id" => friend_id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    friend_id = String.to_integer(friend_id)

    case Accounts.send_friend_request(user_id, friend_id) do
      {:ok, _friendship} ->
        {:noreply,
         socket
         |> put_flash(:info, "Friend request sent!")
         |> assign(:sent_requests, Accounts.get_sent_requests(user_id))
         |> assign(:search_results, [])}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not send friend request")}
    end
  end

  def handle_event("accept_request", %{"user_id" => friend_id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    friend_id = String.to_integer(friend_id)

    case Accounts.accept_friend_request(user_id, friend_id) do
      {:ok, _friendship} ->
        {:noreply,
         socket
         |> put_flash(:info, "Friend request accepted!")
         |> assign(:friends, Accounts.get_friends(user_id))
         |> assign(:pending_requests, Accounts.get_pending_requests(user_id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not accept request")}
    end
  end

  def handle_event("reject_request", %{"user_id" => friend_id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    friend_id = String.to_integer(friend_id)

    case Accounts.reject_friend_request(user_id, friend_id) do
      {:ok, _friendship} ->
        {:noreply,
         socket
         |> put_flash(:info, "Friend request rejected")
         |> assign(:pending_requests, Accounts.get_pending_requests(user_id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not reject request")}
    end
  end

  def handle_event("remove_friend", %{"user_id" => friend_id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    friend_id = String.to_integer(friend_id)

    Accounts.remove_friendship(user_id, friend_id)

    {:noreply,
     socket
     |> put_flash(:info, "Friend removed")
     |> assign(:friends, Accounts.get_friends(user_id))}
  end

  def handle_event("cancel_request", %{"user_id" => friend_id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    friend_id = String.to_integer(friend_id)

    # Delete the pending friend request
    Amenity.Repo.delete_all(
      from f in Amenity.Accounts.Friendship,
        where: f.user_id == ^user_id and f.friend_id == ^friend_id and f.status == "pending"
    )

    {:noreply,
     socket
     |> put_flash(:info, "Friend request cancelled")
     |> assign(:sent_requests, Accounts.get_sent_requests(user_id))}
  end

  defp request_sent?(sent_requests, user_id) do
    Enum.any?(sent_requests, fn {_friendship, user} -> user.id == user_id end)
  end

  defp already_friends?(friends, user_id) do
    Enum.any?(friends, fn friend -> friend.id == user_id end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-indigo-50 via-purple-50 to-pink-50">
      <div class="max-w-6xl mx-auto px-4 py-8">
        <!-- Header -->
        <div class="text-center mb-12">
          <h1 class="text-5xl font-bold mb-4 bg-gradient-to-r from-indigo-600 via-purple-600 to-pink-600 bg-clip-text text-transparent">
            👥 Friends
          </h1>
        </div>
        
    <!-- Search Section -->
        <div class="bg-white rounded-3xl p-6 shadow-xl mb-8">
          <h2 class="text-2xl font-bold mb-4 text-gray-800">🔍 Find Friends</h2>
          <form phx-change="search" class="mb-4">
            <input
              type="text"
              name="search"
              value={@search_query}
              placeholder="Search by username..."
              class="input input-bordered input-lg w-full rounded-full"
              phx-debounce="300"
            />
          </form>

          <div :if={@search_results != []} class="space-y-2">
            <div
              :for={user <- @search_results}
              class="flex items-center gap-3 p-4 bg-gray-50 rounded-2xl hover:bg-gray-100 transition-all"
            >
              <!-- Profile Picture -->
              <div class="avatar">
                <div class="w-12 h-12 rounded-full">
                  <%= if user.profile_picture_url do %>
                    <img src={user.profile_picture_url} alt={"#{user.username}'s profile"} />
                  <% else %>
                    <div class="bg-gradient-to-br from-indigo-500 to-purple-500 text-white flex items-center justify-center w-full h-full text-lg font-bold">
                      {String.first(user.username) |> String.upcase()}
                    </div>
                  <% end %>
                </div>
              </div>
              
              <div class="flex-1">
                <p class="font-semibold text-gray-800">@{user.username}</p>
                <p class="text-xs text-gray-500">Level {user.level} · {user.xp} XP</p>
              </div>
              <%= cond do %>
                <% already_friends?(@friends, user.id) -> %>
                  <span class="btn btn-sm bg-green-100 text-green-700 rounded-full cursor-not-allowed">
                    ✓ Friends
                  </span>
                <% request_sent?(@sent_requests, user.id) -> %>
                  <span class="btn btn-sm btn-ghost text-gray-500 rounded-full cursor-not-allowed">
                    ⏳ Pending
                  </span>
                <% true -> %>
                  <button
                    phx-click="send_request"
                    phx-value-user_id={user.id}
                    class="btn btn-sm bg-gradient-to-r from-purple-500 to-pink-500 text-white rounded-full"
                  >
                    ➕ Add Friend
                  </button>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Pending Requests -->
        <div :if={@pending_requests != []} class="bg-white rounded-3xl p-6 shadow-xl mb-8">
          <h2 class="text-2xl font-bold mb-4 text-gray-800">📬 Friend Requests</h2>
          <div class="space-y-3">
            <div
              :for={{_friendship, user} <- @pending_requests}
              class="flex items-center gap-3 p-4 bg-yellow-50 rounded-2xl border-l-4 border-yellow-400"
            >
              <!-- Profile Picture -->
              <div class="avatar">
                <div class="w-12 h-12 rounded-full">
                  <%= if user.profile_picture_url do %>
                    <img src={user.profile_picture_url} alt={"#{user.username}'s profile"} />
                  <% else %>
                    <div class="bg-gradient-to-br from-yellow-500 to-orange-500 text-white flex items-center justify-center w-full h-full text-lg font-bold">
                      {String.first(user.username) |> String.upcase()}
                    </div>
                  <% end %>
                </div>
              </div>
              
              <div class="flex-1">
                <p class="font-semibold text-gray-800">@{user.username}</p>
                <p class="text-xs text-gray-500">Level {user.level} · {user.xp} XP</p>
              </div>
              <div class="flex gap-2">
                <button
                  phx-click="accept_request"
                  phx-value-user_id={user.id}
                  class="btn btn-sm bg-green-500 hover:bg-green-600 text-white rounded-full"
                >
                  ✓ Accept
                </button>
                <button
                  phx-click="reject_request"
                  phx-value-user_id={user.id}
                  class="btn btn-sm bg-red-500 hover:bg-red-600 text-white rounded-full"
                >
                  ✗ Reject
                </button>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Sent Requests -->
        <div :if={@sent_requests != []} class="bg-white rounded-3xl p-6 shadow-xl mb-8">
          <h2 class="text-2xl font-bold mb-4 text-gray-800">📤 Sent Requests</h2>
          <div class="space-y-3">
            <div
              :for={{_friendship, user} <- @sent_requests}
              class="flex items-center gap-3 p-4 bg-blue-50 rounded-2xl border-l-4 border-blue-400"
            >
              <!-- Profile Picture -->
              <div class="avatar">
                <div class="w-12 h-12 rounded-full">
                  <%= if user.profile_picture_url do %>
                    <img src={user.profile_picture_url} alt={"#{user.username}'s profile"} />
                  <% else %>
                    <div class="bg-gradient-to-br from-blue-500 to-cyan-500 text-white flex items-center justify-center w-full h-full text-lg font-bold">
                      {String.first(user.username) |> String.upcase()}
                    </div>
                  <% end %>
                </div>
              </div>
              
              <div class="flex-1">
                <p class="font-semibold text-gray-800">@{user.username}</p>
                <p class="text-xs text-gray-500">Level {user.level} · {user.xp} XP · Pending...</p>
              </div>
              <button
                phx-click="cancel_request"
                phx-value-user_id={user.id}
                class="btn btn-sm bg-gray-500 hover:bg-gray-600 text-white rounded-full"
              >
                ✗ Cancel
              </button>
            </div>
          </div>
        </div>
        
    <!-- Friends List -->
        <div class="bg-white rounded-3xl p-6 shadow-xl">
          <h2 class="text-2xl font-bold mb-4 text-gray-800">✨ My Friends</h2>

          <div :if={@friends == []} class="text-center py-12">
            <p class="text-xl text-gray-500">No friends yet. Start searching!</p>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div
              :for={friend <- @friends}
              class="flex items-center gap-4 p-4 bg-gradient-to-r from-purple-50 to-pink-50 rounded-2xl hover:shadow-lg transition-all"
            >
              <!-- Profile Picture -->
              <div class="avatar">
                <div class="w-16 h-16 rounded-full ring ring-primary ring-offset-2">
                  <%= if friend.profile_picture_url do %>
                    <img src={friend.profile_picture_url} alt={"#{friend.username}'s profile"} />
                  <% else %>
                    <div class="bg-gradient-to-br from-purple-500 to-pink-500 text-white flex items-center justify-center w-full h-full text-2xl font-bold">
                      {String.first(friend.username) |> String.upcase()}
                    </div>
                  <% end %>
                </div>
              </div>
              
              <!-- Friend Info -->
              <div class="flex-1 min-w-0">
                <p class="font-bold text-gray-800 text-lg truncate">@{friend.username}</p>
                <div class="flex items-center gap-2 mt-1">
                  <span class="badge badge-primary badge-sm">Level {friend.level}</span>
                  <span class="badge badge-secondary badge-sm">{friend.xp} XP</span>
                </div>
                <p class="text-xs text-gray-500 mt-1">
                  Member since {Calendar.strftime(friend.inserted_at, "%b %Y")}
                </p>
              </div>
              
              <!-- Remove Button -->
              <button
                phx-click="remove_friend"
                phx-value-user_id={friend.id}
                class="btn btn-sm btn-ghost text-red-500 hover:bg-red-100 rounded-full shrink-0"
              >
                Remove
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
