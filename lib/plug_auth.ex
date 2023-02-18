defmodule Plug.Auth do
  use Plug.Builder

  def call(conn, _) do
    [key] = get_req_header(conn, "l")
    event_key = Application.fetch_env!(:backend, :event_key)

    case key do
      x when x == event_key -> conn
      _ -> halt(conn)
    end
  end
end
