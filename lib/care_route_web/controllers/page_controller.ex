defmodule CareRouteWeb.PageController do
  use CareRouteWeb, :controller

  def home(conn, _params) do
    conn
    |> assign(:page_title, "Find the right care, right away")
    |> render(:home)
  end
end
