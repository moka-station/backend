defmodule Backend.SocketHandler do
  @behaviour :cowboy_websocket

  def init(req, _state) do
    state = %{path: req.path, cookie: req.headers["cookie"]}
    {:cowboy_websocket, req, state}
  end

  def websocket_init(state) do
    try do
      if !String.contains?(state.cookie, "auth_session=") do
        raise('no session key found')
      end

      tmp =
        state.cookie
        |> String.split(["auth_session=", ";"])
        |> Enum.at(1)
        |> then(
          &MyXQL.query!(
            :myxql,
            "SELECT user_id FROM Session WHERE id = (?)",
            [&1]
          )
        )

      if tmp.num_rows == 0 do
        raise('no session key found')
      end

      %{rows: [[userId]]} = tmp

      Registry.User
      |> Registry.register(userId, {})

      MyXQL.query!(
        :myxql,
        "SELECT mg.id
        FROM User_MessageGroup umg
        JOIN MessageGroup mg ON mg.id = umg.messageGroupId
        WHERE umg.userId = (?)",
        [userId]
      ).rows
      |> Enum.each(fn [x] ->
        IO.puts("Registered " <> x)

        {:ok, _} =
          Registry.MessageGroup
          |> Registry.register(x, %{userId: userId})
      end)

      {:ok, %{userId: userId, path: state.path}}
    rescue
      _ -> {:stop, state}
    end
  end

  def websocket_handle({:text, message}, state) do
    %{"id" => id, "type" => type, "data" => data} =
      %{"id" => nil, "data" => nil}
      |> Map.merge(Jason.decode!(message))

    try do
      case type do
        "ping" -> {:reply, {:text, Jason.encode!(%{"type" => "pong"})}, state}
        "sendMessage" -> Message.sendMessage(id, data, state, 0)
        "createGroup" -> Message.createGroup(id, data, state)
        "inviteGroup" -> Message.inviteGroup(id, data, state)
        "leaveGroup" -> Message.leaveGroup(id, data, state)
        "modifyGroup" -> Message.modifyGroup(id, data, state)
        _ -> raise("non-existent type")
      end
    rescue
      e in RuntimeError ->
        {:reply, {:text, Jason.encode!(%{"id" => id, "type" => "error", "msg" => e.message})},
         state}

      _ ->
        {:reply, {:text, Jason.encode!(%{"id" => id, "type" => "error", "msg" => ""})}, state}
    end
  end

  def websocket_info(info, state) do
    %{type: type, data: data} = info

    case type do
      :reply ->
        {:reply, {:text, data}, state}

      :reg ->
        %{reg: reg, key: key} = data
        {:ok, _} = Registry.register(reg, key, {})
        {:ok, state}

      :unreg ->
        %{reg: reg, key: key} = data
        :ok = Registry.unregister(reg, key)
        {:ok, state}
    end
  end
end
