defmodule AmenityWeb.UserLive.Profile do
  use AmenityWeb, :live_view

  alias Amenity.Accounts
  alias Amenity.Trivia

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
                <div class="flex items-center justify-center gap-3 mt-2">
                  <div class="badge badge-primary badge-lg">
                    Level {@user.level}
                  </div>
                  <div class="badge badge-secondary badge-lg">
                    {@user.xp} XP
                  </div>
                </div>
                
                <!-- XP Progress Bar -->
                <div class="w-full max-w-md mx-auto mt-4">
                  <div class="flex justify-between text-xs text-gray-600 mb-1">
                    <span>Level {@user.level}</span>
                    <span>Level {@user.level + 1}</span>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-3">
                    <div
                      class="bg-gradient-to-r from-purple-500 to-pink-500 h-3 rounded-full transition-all"
                      style={"width: #{calculate_level_progress(@user.xp, @user.level)}%"}
                    >
                    </div>
                  </div>
                  <p class="text-xs text-gray-500 mt-1">
                    {xp_to_next_level(@user.xp, @user.level)} XP to next level
                  </p>
                </div>
                
                <p class="text-sm text-base-content/60 mt-4">
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

        <!-- Achievements -->
        <div class="card bg-gradient-to-br from-yellow-50 to-orange-50 shadow-xl">
          <div class="card-body">
            <div class="flex items-center gap-3 mb-6">
              <div class="text-4xl">🏆</div>
              <div>
                <h3 class="card-title text-orange-900">Achievements</h3>
                <p class="text-sm text-orange-700">Your unlocked achievements</p>
              </div>
            </div>

            <%= if length(@user.achievements) > 0 do %>
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for achievement_id <- @user.achievements do %>
                  <% achievement = get_achievement_info(achievement_id) %>
                  <div class="bg-white rounded-xl p-4 shadow-md border-2 border-yellow-400">
                    <div class="flex items-center gap-3">
                      <div class="text-3xl">{achievement.icon}</div>
                      <div class="flex-1">
                        <h4 class="font-bold text-gray-800">{achievement.name}</h4>
                        <p class="text-xs text-gray-600">{achievement.description}</p>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-center py-8">
                <div class="text-6xl mb-4">🎯</div>
                <p class="text-gray-600">No achievements unlocked yet.</p>
                <p class="text-sm text-gray-500 mt-2">Play trivia games to unlock achievements!</p>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Trivia Statistics -->
        <div class="card bg-gradient-to-br from-purple-50 to-pink-50 shadow-xl">
          <div class="card-body">
            <div class="flex items-center gap-3 mb-6">
              <div class="text-4xl">🎮</div>
              <div>
                <h3 class="card-title text-purple-900">Trivia Battle Stats</h3>
                <p class="text-sm text-purple-700">Your performance in trivia games</p>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <!-- Stats Summary -->
              <div class="space-y-4">
                <div class="bg-white rounded-xl p-4 shadow-md">
                  <div class="flex justify-between items-center">
                    <span class="text-gray-700 font-semibold">🎯 Games Played</span>
                    <span class="text-2xl font-bold text-purple-600">{@trivia_stats.games_played}</span>
                  </div>
                </div>
                
                <div class="bg-white rounded-xl p-4 shadow-md">
                  <div class="flex justify-between items-center">
                    <span class="text-gray-700 font-semibold">✅ Correct Answers</span>
                    <span class="text-2xl font-bold text-green-600">{@trivia_stats.total_correct}</span>
                  </div>
                </div>
                
                <div class="bg-white rounded-xl p-4 shadow-md">
                  <div class="flex justify-between items-center">
                    <span class="text-gray-700 font-semibold">❌ Incorrect Answers</span>
                    <span class="text-2xl font-bold text-red-600">{@trivia_stats.total_incorrect}</span>
                  </div>
                </div>
                
                <div class="bg-white rounded-xl p-4 shadow-md">
                  <div class="flex justify-between items-center">
                    <span class="text-gray-700 font-semibold">⭐ Total Score</span>
                    <span class="text-2xl font-bold text-orange-600">{@trivia_stats.total_score}</span>
                  </div>
                </div>

                <%= if @trivia_stats.total_correct + @trivia_stats.total_incorrect > 0 do %>
                  <div class="bg-gradient-to-r from-purple-500 to-pink-500 rounded-xl p-4 shadow-md text-white">
                    <div class="flex justify-between items-center">
                      <span class="font-semibold">📊 Accuracy Rate</span>
                      <span class="text-2xl font-bold">
                        {Float.round(@trivia_stats.total_correct / (@trivia_stats.total_correct + @trivia_stats.total_incorrect) * 100, 1)}%
                      </span>
                    </div>
                  </div>
                <% end %>
              </div>

              <!-- Pie Chart -->
              <%= if @trivia_stats.total_correct + @trivia_stats.total_incorrect > 0 do %>
                <div class="bg-white rounded-xl p-6 shadow-md">
                  <h4 class="text-lg font-bold text-gray-800 mb-4 text-center">Answer Accuracy</h4>
                  <div class="flex justify-center items-center">
                    <div style="width: 300px; height: 300px;">
                      <canvas
                        id="accuracy-chart"
                        phx-hook="AccuracyPieChart"
                        data-correct={@trivia_stats.total_correct}
                        data-incorrect={@trivia_stats.total_incorrect}
                      >
                      </canvas>
                    </div>
                  </div>
                </div>
              <% else %>
                <div class="bg-white rounded-xl p-6 shadow-md">
                  <h4 class="text-lg font-bold text-gray-800 mb-4 text-center">Answer Accuracy</h4>
                  <div class="text-center text-gray-500 py-8">
                    <div class="text-4xl mb-3">📊</div>
                    <p>No trivia games played yet.</p>
                    <p class="text-sm mt-2">Start playing to see your stats!</p>
                  </div>
                </div>
              <% end %>
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
    
    # Fetch trivia statistics
    trivia_stats = Trivia.get_user_stats(user.id)
    
    require Logger
    Logger.info("Loading trivia stats for user #{user.id}: #{inspect(trivia_stats)}")

    socket =
      socket
      |> assign(:user, user)
      |> assign(:profile_picture_form, to_form(profile_picture_changeset))
      |> assign(:trivia_stats, trivia_stats)

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

  # Helper functions for XP and level calculations
  defp calculate_level_progress(xp, level) do
    # XP required for current level
    xp_for_current_level = (level - 1) * (level - 1) * 100
    # XP required for next level
    xp_for_next_level = level * level * 100
    # XP progress in current level
    xp_in_level = xp - xp_for_current_level
    xp_needed_for_level = xp_for_next_level - xp_for_current_level
    
    # Calculate percentage
    if xp_needed_for_level > 0 do
      min(100, (xp_in_level / xp_needed_for_level * 100) |> Float.round(1))
    else
      0
    end
  end

  defp xp_to_next_level(xp, level) do
    xp_for_next_level = level * level * 100
    max(0, xp_for_next_level - xp)
  end

  # Helper function to get achievement information
  defp get_achievement_info(achievement_id) do
    case achievement_id do
      "first_victory" ->
        %{
          icon: "🎉",
          name: "First Victory",
          description: "Complete your first trivia game"
        }

      "perfect_game" ->
        %{
          icon: "💯",
          name: "Perfect Game",
          description: "Get all answers correct in a game"
        }

      "trivia_master" ->
        %{
          icon: "🎓",
          name: "Trivia Master",
          description: "Play 10 trivia games"
        }

      "scholar" ->
        %{
          icon: "📚",
          name: "Scholar",
          description: "Get 50 correct answers"
        }

      "high_scorer" ->
        %{
          icon: "⭐",
          name: "High Scorer",
          description: "Reach 5000 total score"
        }

      _ ->
        %{
          icon: "🏆",
          name: "Unknown Achievement",
          description: "Mystery achievement"
        }
    end
  end
end
