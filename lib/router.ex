defmodule Backend.Router do
  use Plug.Router

  plug(:match)

  plug(:dispatch)

  get "/" do
    send_resp(conn, 200, "ok")
  end

  get "/ws" do
    {Plug.Cowboy.Conn, req} = conn.adapter
    {:cowboy_websocket, _, state} = Backend.SocketHandler.init(req, {})
    Plug.Conn.upgrade_adapter(conn, :websocket, {Backend.SocketHandler, state, %{}})
  end

  post "/event/:type" do
    onlyServer(conn)

    case type do
      "like" ->
        %{"userId" => userId, "byUserId" => byUserId} = conn.params
        user = DB.getSimpleUserById(:myxql, byUserId)

        Registry.User
        |> Registry.dispatch(userId, fn entries ->
          for {pid, _} <- entries do
            if pid != self() do
              Process.send(
                pid,
                %{
                  type: :reply,
                  data:
                    Jason.encode!(%{
                      "type" => "event",
                      "data" => %{
                        "type" => "likeMonu",
                        "byUser" => user
                      }
                    })
                },
                []
              )
            end
          end
        end)

      x when x in ["mention", "remonu"] ->
        %{"userTags" => userTags, "byUserId" => byUserId} = conn.params
        user = DB.getSimpleUserById(:myxql, byUserId)

        DB.getUserIdsByTags(conn, userTags)
        |> Enum.each(fn id ->
          Registry.User
          |> Registry.dispatch(id, fn entries ->
            for {pid, _} <- entries do
              if pid != self() do
                Process.send(
                  pid,
                  %{
                    type: :reply,
                    data:
                      Jason.encode!(%{
                        "type" => "event",
                        "data" => %{
                          "type" => type,
                          "byUser" => user
                        }
                      })
                  },
                  []
                )
              end
            end
          end)
        end)
    end

    send_resp(conn, 200, "ok")
  end

  def onlyServer(conn) do
    [key] = get_req_header(conn, "l")
    event_key = Application.fetch_env!(:backend, :event_key)

    case key do
      x when x == event_key -> conn
      _ -> halt(conn)
    end
  end
end
