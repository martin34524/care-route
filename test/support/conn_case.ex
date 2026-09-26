defmodule CareRouteWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use CareRouteWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint CareRouteWeb.Endpoint

      use CareRouteWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import CareRouteWeb.ConnCase
    end
  end

  setup tags do
    CareRoute.DataCase.setup_sandbox(tags)
    {:ok, conn: staff_conn(Phoenix.ConnTest.build_conn())}
  end

  @doc "Adds the test staff credentials, so /clinician and /admin are reachable."
  def staff_conn(conn) do
    %{username: user, password: pass} = Map.new(Application.fetch_env!(:care_route, :staff_auth))
    Plug.Conn.put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth(user, pass))
  end
end
