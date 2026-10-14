defmodule CareRouteWeb.ClientIP do
  @moduledoc """
  The visitor's IP address, for rate limits.

  Behind a proxy (Fly.io) every request comes from the proxy, so the real
  address is read from the header named in `config :care_route, :client_ip_header`
  (e.g. "fly-client-ip"). Only set that when a proxy you trust overwrites the
  header, or visitors could pick their own address.
  """

  @doc "The client IP of `conn` as a string."
  def get(%Plug.Conn{} = conn) do
    with header when is_binary(header) <- Application.get_env(:care_route, :client_ip_header),
         [value | _] <- Plug.Conn.get_req_header(conn, header),
         ip when ip != "" <- value |> String.split(",") |> hd() |> String.trim() do
      ip
    else
      _ -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  @doc "LiveView session data for `live_session`: puts the client IP in the session."
  def session(%Plug.Conn{} = conn), do: %{"client_ip" => get(conn)}
end
