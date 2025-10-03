defmodule Amenity.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups) do
      add :name, :string, null: false
      add :description, :text
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      add :is_private, :boolean, default: false, null: false
      add :avatar_url, :string

      timestamps(type: :utc_datetime)
    end

    create index(:groups, [:owner_id])
    create index(:groups, [:name])

    create table(:group_members) do
      add :group_id, references(:groups, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"
      # roles: "owner", "admin", "moderator", "member"
      add :joined_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:group_members, [:group_id])
    create index(:group_members, [:user_id])
    create unique_index(:group_members, [:group_id, :user_id])

    create table(:group_invites) do
      add :group_id, references(:groups, on_delete: :delete_all), null: false
      add :inviter_id, references(:users, on_delete: :delete_all), null: false
      add :invitee_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      # status: "pending", "accepted", "rejected"

      timestamps(type: :utc_datetime)
    end

    create index(:group_invites, [:group_id])
    create index(:group_invites, [:invitee_id])
    create index(:group_invites, [:status])
    create unique_index(:group_invites, [:group_id, :invitee_id])
  end
end
