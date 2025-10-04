defmodule AmenityWeb.SocialLive.Index do
  use AmenityWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 via-purple-50 to-pink-50">
      <div class="max-w-7xl mx-auto px-4 py-8">
        <div class="text-center mb-12">
          <h1 class="text-6xl font-bold mb-4">
            👥
            <span class="bg-gradient-to-r from-blue-600 via-purple-600 to-pink-600 bg-clip-text text-transparent">
              Social
            </span>
          </h1>
          <p class="text-xl text-gray-600">Groups, posts, and community discussions</p>
        </div>

        <div class="text-center py-20">
          <p class="text-2xl text-gray-600">Social features coming soon!</p>
          <p class="text-lg text-gray-500 mt-4">
            Groups, posts, and discussions will be available here
          </p>
        </div>
      </div>
    </div>
    """
  end
end
