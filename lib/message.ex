defmodule Message do
  def sendMessage(_, data, state, type) do
    %{"groupId" => groupId, "msg" => msg} = data

    id = Nanoid.generate()

    {:ok, result} =
      MyXQL.transaction(
        :myxql,
        fn conn ->
          MyXQL.query!(
            conn,
            "INSERT INTO Message (id, userId, messageGroupId, content, type)
            SELECT ?, ?, ?, ?, ?
            WHERE EXISTS (SELECT * FROM User_MessageGroup WHERE userId = ? AND messageGroupId = ?)",
            [id, state.userId, groupId, msg, type, state.userId, groupId]
          )

          MyXQL.query!(
            conn,
            "SELECT m.id, u.username, u.usertag, u.image, m.content, m.created, m.type
            FROM Message m
            JOIN User u ON u.id = m.userId
            WHERE m.id = ?",
            [id]
          )
        end
      )

    if result.num_rows == 0 do
      raise("Server Error")
    end

    res_row = Enum.at(result.rows, 0)

    inserted_msg =
      Enum.to_list(0..(length(result.columns) - 1))
      |> Enum.reduce(%{}, fn i, acc ->
        Map.put(acc, Enum.at(result.columns, i), Enum.at(res_row, i))
      end)

    response =
      Jason.encode!(%{
        "type" => "message",
        "groupId" => groupId,
        "msg" => inserted_msg
      })

    Registry.MessageGroup
    |> Registry.dispatch(groupId, fn entries ->
      for {pid, _} <- entries do
        Process.send(pid, %{type: :reply, data: response}, [])
      end
    end)

    {:ok, state}
  end

  def createGroup(socket_id, data, state) do
    %{"userTags" => userTags, "image" => image, "title" => title} =
      %{"userTags" => [], "image" => 0, "title" => ""}
      |> Map.merge(data)

    groupId = Nanoid.generate()

    if title == "" do
      raise("title is necessary")
    end

    image =
      if image != "" do
        :ok = Storage.putGroupImage(groupId, image)
        1
      else
        0
      end

    userIds =
      if length(userTags) != 0 do
        userIdsQuery =
          "?"
          |> List.duplicate(length(userTags))
          |> Enum.join(", ")
          |> (&MyXQL.query!(
                :myxql,
                "SELECT id FROM User WHERE usertag IN (" <> &1 <> ")",
                userTags
              )).()

        userIdsQuery.rows
        |> List.flatten()
      else
        []
      end

    messagesIds = DB.generateIDs(length(userTags))

    {:ok, result} =
      MyXQL.transaction(
        :myxql,
        fn conn ->
          MyXQL.query!(
            conn,
            "INSERT INTO MessageGroup (id, image, title) VALUES (?, ?, ?)",
            [groupId, image, title]
          )

          ", (?, ?)"
          |> List.duplicate(length(userIds))
          |> Enum.join()
          |> (&MyXQL.query!(
                conn,
                "INSERT INTO User_MessageGroup (userId, messageGroupId)
                VALUES (?, ?)" <> &1,
                [state.userId, groupId] ++ Enum.flat_map(userIds, fn x -> [x, groupId] end)
              )).()

          DB.insertTypedMessage(conn, 1, groupId, messagesIds, [state.userId | userIds])

          MyXQL.query!(
            conn,
            "SELECT mg.id, mg.image, mg.title, mg.created, NULL latestMessage, NULL updated
            FROM MessageGroup mg
            WHERE mg.id = ?",
            [groupId]
          )
        end
      )

    if result.num_rows == 0 do
      raise("Server Error")
    end

    res_row = Enum.at(result.rows, 0)

    inserted_data =
      Enum.to_list(0..(length(result.columns) - 1))
      |> Enum.reduce(%{}, fn i, acc ->
        Map.put(acc, Enum.at(result.columns, i), Enum.at(res_row, i))
      end)

    {:ok, _} =
      Registry.MessageGroup
      |> Registry.register(groupId, %{userId: state.userId})

    [state.userId | userIds]
    |> Enum.each(fn userId ->
      Registry.User
      |> Registry.dispatch(userId, fn entries ->
        for {pid, _} <- entries do
          if pid != self() do
            Process.send(
              pid,
              %{
                type: :reply,
                data: Jason.encode!(%{"type" => "createGroup", "data" => inserted_data})
              },
              []
            )

            Process.send(
              pid,
              %{type: :reg, data: %{reg: Registry.MessageGroup, key: groupId}},
              []
            )
          end
        end
      end)
    end)

    {:reply,
     {:text,
      Jason.encode!(%{
        "id" => socket_id,
        "type" => "createGroup",
        "data" => inserted_data
      })}, state}
  end

  def inviteGroup(_, data, state) do
    %{"groupId" => groupId, "userTags" => userTags} = data

    if length(userTags) == 0 do
      raise("No Usertags")
    end

    userIdsQuery =
      "?"
      |> List.duplicate(length(userTags))
      |> Enum.join(", ")
      |> (&MyXQL.query!(
            :myxql,
            "SELECT id FROM User WHERE usertag IN (" <> &1 <> ")",
            userTags
          )).()

    userIds =
      userIdsQuery.rows
      |> List.flatten()

    {:ok, result} =
      MyXQL.transaction(
        :myxql,
        fn conn ->
          res =
            "ROW(?)"
            |> List.duplicate(length(userTags))
            |> Enum.join(", ")
            |> (&MyXQL.query!(
                  conn,
                  # SQL Insert many rows - one value changes - number of rows is dynamic https://stackoverflow.com/a/72102147
                  "INSERT INTO User_MessageGroup (userId, messageGroupId)
                  SELECT column_0, ? FROM (VALUES " <>
                    &1 <>
                    ") as t
                  WHERE EXISTS (SELECT * FROM User_MessageGroup WHERE userId = ? AND messageGroupId = ?)",
                  [groupId] ++ userIds ++ [state.userId, groupId]
                )).()

          if res.num_rows == 0 || res.num_rows != length(userTags) do
            MyXQL.rollback(conn, :not_completed)
          end

          MyXQL.query!(
            conn,
            "SELECT mg.id, mg.image, mg.title, mg.created, m.content latestMessage, m.created updated
            FROM MessageGroup mg
            LEFT JOIN Message m ON m.id = (SELECT id FROM Message WHERE messageGroupId = mg.id ORDER BY created DESC LIMIT 1)
            WHERE mg.id = ?",
            [groupId]
          )
        end
      )

    if result.num_rows == 0 do
      raise("Server Error")
    end

    res_row = Enum.at(result.rows, 0)

    inserted_data =
      Enum.to_list(0..(length(result.columns) - 1))
      |> Enum.reduce(%{}, fn i, acc ->
        Map.put(acc, Enum.at(result.columns, i), Enum.at(res_row, i))
      end)

    userIds
    |> Enum.each(fn userId ->
      sendMessage(nil, %{"groupId" => groupId, "msg" => ""}, %{userId: userId}, 1)
    end)

    userIds
    |> Enum.each(fn userId ->
      Registry.User
      |> Registry.dispatch(userId, fn entries ->
        for {pid, _} <- entries do
          if pid != self() do
            Process.send(
              pid,
              %{
                type: :reply,
                data: Jason.encode!(%{"type" => "inviteGroup", "data" => inserted_data})
              },
              []
            )

            Process.send(
              pid,
              %{type: :reg, data: %{reg: Registry.MessageGroup, key: groupId}},
              []
            )
          end
        end
      end)
    end)

    {:ok, state}
  end

  def modifyGroup(socket_id, data, state) do
    %{"groupId" => groupId, "image" => image, "title" => title} =
      %{"image" => nil, "title" => nil}
      |> Map.merge(data)

    if title == "" do
      raise("title is necessary")
    end

    {:ok, _} =
      MyXQL.transaction(:myxql, fn conn ->
        res =
          MyXQL.query!(
            conn,
            "UPDATE station0.MessageGroup
            SET title = IFNULL(?, title), image = IFNULL(?, image)
            WHERE id = ? AND EXISTS (SELECT * FROM User_MessageGroup WHERE userId = ? AND messageGroupId = ?)",
            [
              title,
              case image do
                # nothing
                nil -> nil
                # deleteImage
                "" -> 0
                # putImage
                _ -> 1
              end,
              groupId,
              state.userId,
              groupId
            ]
          )

        if res.num_rows == 0 do
          raise("server error")
        end

        if image != nil do
          res =
            if image == "" do
              Storage.deleteGroupImage(groupId)
            else
              Storage.putGroupImage(groupId, image)
            end

          if res == :fail do
            MyXQL.rollback(conn, :imgPutFail)
          end
        end
      end)

    image =
      if image == "" do
        0
      else
        1
      end

    response =
      Jason.encode!(%{
        "type" => "modifyGroup",
        "data" => %{
          "groupId" => groupId,
          "title" => title,
          "image" => image
        }
      })

    Registry.MessageGroup
    |> Registry.dispatch(groupId, fn entries ->
      for {pid, _} <- entries do
        if pid != self() do
          Process.send(pid, %{type: :reply, data: response}, [])
        end
      end
    end)

    {:reply,
     {:text,
      Jason.encode!(%{
        "id" => socket_id,
        "type" => "modifyGroup",
        "data" => %{
          "groupId" => groupId,
          "title" => title,
          "image" => image
        }
      })}, state}
  end

  def leaveGroup(socket_id, data, state) do
    %{"groupId" => groupId} = data

    # ? Generates pointless notifications on future transaction failures
    sendMessage(nil, %{"groupId" => groupId, "msg" => ""}, state, 2)

    {:ok, _} =
      MyXQL.transaction(
        :myxql,
        fn conn ->
          res =
            MyXQL.query!(
              conn,
              "DELETE FROM User_MessageGroup WHERE userId = ? AND messageGroupId = ?",
              [state.userId, groupId]
            )

          if res.num_rows == 0 do
            MyXQL.rollback(conn, :error)
          end

          res =
            MyXQL.query!(
              conn,
              "DELETE FROM MessageGroup WHERE NOT EXISTS (SELECT NULL FROM User_MessageGroup umg WHERE umg.messageGroupId = ? LIMIT 1) AND id = ?",
              [groupId, groupId]
            )

          if res.num_rows > 0 do
            res = Storage.deleteGroupImage(groupId)

            if res != :ok do
              MyXQL.rollback(conn, :error)
            end
          end

          res
        end
      )

    Registry.MessageGroup
    |> Registry.unregister_match(groupId, %{userId: state.userId})

    inserted_data = %{"groupId" => groupId}
    response = %{"type" => "leaveGroup", "data" => inserted_data} |> Jason.encode!()

    Registry.User
    |> Registry.dispatch(state.userId, fn entries ->
      for {pid, _} <- entries do
        Process.send(pid, %{type: :reply, data: response}, [])

        Process.send(
          pid,
          %{type: :unreg, data: %{reg: Registry.MessageGroup, key: groupId}},
          []
        )
      end
    end)

    {:reply,
     {:text,
      Jason.encode!(%{
        "id" => socket_id,
        "type" => "leaveGroup",
        "data" => inserted_data
      })}, state}
  end
end
