defmodule AmenityWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.
  """
  use Phoenix.Presence,
    otp_app: :amenity,
    pubsub_server: Amenity.PubSub
end
