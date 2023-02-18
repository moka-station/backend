defmodule Backend.Router do
  use Plug.Router

  plug(:match)

  plug(:dispatch)

  get "/" do
    {Plug.Cowboy.Conn, req} = conn.adapter
    {:cowboy_websocket, _, state} = Backend.SocketHandler.init(req, {})
    Plug.Conn.upgrade_adapter(conn, :websocket, {Backend.SocketHandler, state, %{}})
  end
end
