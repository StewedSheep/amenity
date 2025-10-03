defmodule Amenity.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Amenity.Accounts` context.
  """

  import Ecto.Query

  alias Amenity.Accounts
  alias Amenity.Accounts.Scope

  def unique_username, do: "user#{System.unique_integer()}"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      username: unique_username(),
      password: valid_user_password()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    # Users are now auto-confirmed on registration
    unconfirmed_user_fixture(attrs)
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Amenity.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end
end
