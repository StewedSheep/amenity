defmodule AmenityWeb.UserLive.Profile do
  use AmenityWeb, :live_view

  alias Amenity.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto space-y-8">
        <div class="text-center">
          <.header>
            User Profile
            <:subtitle>View and manage your account information</:subtitle>
          </.header>
        </div>

        <div class="card bg-base-200 shadow-xl">
          <div class="card-body">
            <div class="flex flex-col items-center space-y-6">
              <!-- Profile Picture -->
              <div class="avatar">
                <div class="w-32 h-32 rounded-full ring ring-primary ring-offset-base-100 ring-offset-2">
                  <%= if @user.profile_picture_url do %>
                    <img src={@user.profile_picture_url} alt="Profile picture" />
                  <% else %>
                    <div class="bg-neutral text-neutral-content flex items-center justify-center w-full h-full text-4xl font-bold">
                      {String.first(@user.username) |> String.upcase()}
                    </div>
                  <% end %>
                </div>
              </div>

              <!-- Username -->
              <div class="text-center">
                <h2 class="text-3xl font-bold">{@user.username}</h2>
                <p class="text-sm text-base-content/60">
                  Member since {Calendar.strftime(@user.inserted_at, "%B %d, %Y")}
                </p>
              </div>

              <!-- Edit Profile Picture Form -->
              <div class="w-full max-w-md">
                <.form
                  for={@profile_picture_form}
                  id="profile_picture_form"
                  phx-submit="update_profile_picture"
                  phx-change="validate_profile_picture"
                  class="space-y-4"
                >
                  <.input
                    field={@profile_picture_form[:profile_picture_url]}
                    type="text"
                    label="Profile Picture URL"
                    placeholder="https://example.com/image.jpg"
                  />
                  <div class="flex gap-2">
                    <.button variant="primary" phx-disable-with="Saving..." class="flex-1">
                      Update Picture
                    </.button>
                    <%= if @user.profile_picture_url do %>
                      <.button
                        type="button"
                        phx-click="remove_profile_picture"
                        class="flex-1 btn-outline"
                      >
                        Remove Picture
                      </.button>
                    <% end %>
                  </div>
                </.form>
              </div>
            </div>
          </div>
        </div>

        <!-- Account Information -->
        <div class="card bg-base-200 shadow-xl">
          <div class="card-body">
            <h3 class="card-title">Account Information</h3>
            <div class="space-y-4">
              <div class="flex justify-between items-center py-2 border-b border-base-300">
                <span class="font-semibold">Username</span>
                <span>{@user.username}</span>
              </div>
              <div class="flex justify-between items-center py-2 border-b border-base-300">
                <span class="font-semibold">Account Status</span>
                <span class="badge badge-success">Active</span>
              </div>
              <div class="flex justify-between items-center py-2 border-b border-base-300">
                <span class="font-semibold">Confirmed At</span>
                <span>
                  <%= if @user.confirmed_at do %>
                    {Calendar.strftime(@user.confirmed_at, "%B %d, %Y at %I:%M %p")}
                  <% else %>
                    Not confirmed
                  <% end %>
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    profile_picture_changeset = Accounts.change_user_profile_picture(user, %{})

    socket =
      socket
      |> assign(:user, user)
      |> assign(:profile_picture_form, to_form(profile_picture_changeset))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_profile_picture", params, socket) do
    %{"user" => user_params} = params

    profile_picture_form =
      socket.assigns.user
      |> Accounts.change_user_profile_picture(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, profile_picture_form: profile_picture_form)}
  end

  def handle_event("update_profile_picture", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.user

    case Accounts.update_user_profile_picture(user, user_params) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(
           :profile_picture_form,
           to_form(Accounts.change_user_profile_picture(updated_user, %{}))
         )
         |> put_flash(:info, "Profile picture updated successfully!")}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_picture_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("remove_profile_picture", _params, socket) do
    user = socket.assigns.user

    case Accounts.update_user_profile_picture(user, %{profile_picture_url: nil}) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(
           :profile_picture_form,
           to_form(Accounts.change_user_profile_picture(updated_user, %{}))
         )
         |> put_flash(:info, "Profile picture removed successfully!")}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_picture_form, to_form(changeset, action: :insert))}
    end
  end
end
