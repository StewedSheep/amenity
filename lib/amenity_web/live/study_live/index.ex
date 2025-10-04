defmodule AmenityWeb.StudyLive.Index do
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
            📚
            <span class="bg-gradient-to-r from-blue-600 via-purple-600 to-pink-600 bg-clip-text text-transparent">
              Study
            </span>
          </h1>
          <p class="text-xl text-gray-600">Strengthen your knowledge through practice</p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-5xl mx-auto">
          <!-- Flashcards Card -->
          <div class="bg-white rounded-3xl p-8 shadow-xl hover:shadow-2xl transition-all transform hover:scale-105 border-t-4 border-blue-400">
            <div class="text-center mb-6">
              <div class="text-6xl mb-4">🎴</div>
              <h2 class="text-3xl font-bold text-gray-800 mb-2">Flashcards</h2>
              <p class="text-gray-600">Study Bible verses and concepts with interactive flashcards</p>
            </div>

            <div class="space-y-3 mb-6">
              <div class="flex items-center gap-2 text-gray-700">
                <span class="text-green-500">✓</span>
                <span>Create custom card decks</span>
              </div>
              <div class="flex items-center gap-2 text-gray-700">
                <span class="text-green-500">✓</span>
                <span>Track your progress</span>
              </div>
              <div class="flex items-center gap-2 text-gray-700">
                <span class="text-green-500">✓</span>
                <span>Spaced repetition learning</span>
              </div>
            </div>

            <button class="btn btn-primary w-full btn-lg rounded-full">
              Start Studying
            </button>
          </div>
          
    <!-- Trivia Battle Card -->
          <div class="bg-white rounded-3xl p-8 shadow-xl hover:shadow-2xl transition-all transform hover:scale-105 border-t-4 border-purple-400">
            <div class="text-center mb-6">
              <div class="text-6xl mb-4">⚔️</div>
              <h2 class="text-3xl font-bold text-gray-800 mb-2">Trivia Battle</h2>
              <p class="text-gray-600">Challenge friends and test your Bible knowledge</p>
            </div>

            <div class="space-y-3 mb-6">
              <div class="flex items-center gap-2 text-gray-700">
                <span class="text-purple-500">✓</span>
                <span>Compete with friends</span>
              </div>
              <div class="flex items-center gap-2 text-gray-700">
                <span class="text-purple-500">✓</span>
                <span>Multiple difficulty levels</span>
              </div>
              <div class="flex items-center gap-2 text-gray-700">
                <span class="text-purple-500">✓</span>
                <span>Earn points and badges</span>
              </div>
            </div>

            <.link navigate={~p"/trivia/rooms"} class="btn btn-secondary w-full btn-lg rounded-full">
              Start Battle
            </.link>
          </div>
        </div>
        
    <!-- Coming Soon Banner -->
        <div class="text-center mt-12">
          <div class="inline-block bg-yellow-100 border-2 border-yellow-400 rounded-full px-6 py-3">
            <p class="text-yellow-800 font-semibold">🚧 Coming Soon - Features in development</p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
