defmodule AmenityWeb.PageController do
  use AmenityWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
