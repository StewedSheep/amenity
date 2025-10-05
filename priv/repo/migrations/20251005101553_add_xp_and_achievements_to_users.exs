defmodule Amenity.Repo.Migrations.AddXpAndAchievementsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :xp, :integer, default: 0, null: false
      add :level, :integer, default: 1, null: false
      add :achievements, {:array, :string}, default: [], null: false
    end
  end
end
