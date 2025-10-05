defmodule Amenity.Workers.CleanupAiFlashcardsWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Amenity.Repo
  alias Amenity.Study.FlashcardSet
  import Ecto.Query

  @impl Oban.Worker
  def perform(_job) do
    # Delete AI-generated flashcard sets older than 24 hours
    cutoff_time = DateTime.utc_now() |> DateTime.add(-24, :hour)

    query =
      from(fs in FlashcardSet,
        where: fs.ai_generated == true,
        where: fs.inserted_at < ^cutoff_time
      )

    {count, _} = Repo.delete_all(query)

    if count > 0 do
      require Logger
      Logger.info("Cleaned up #{count} AI-generated flashcard sets older than 24 hours")
    end

    :ok
  end
end
