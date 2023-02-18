defmodule Backend.ServerRouter do
  use Plug.Router

  # Auth check by Header
  plug(Plug.Auth)

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  get "/" do
    # {127, 0, 0, 1} = conn.remote_ip # Only Allow IP
    send_resp(conn, 200, "ok")
  end

  post "/event/:type" do
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
end
