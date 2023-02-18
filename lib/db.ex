defmodule DB do
  def getSimpleUserById(conn, id) do
    res =
      MyXQL.query!(
        conn,
        "SELECT image, usertag, username
        FROM User
        WHERE id = ?",
        [id]
      )

    res_row = Enum.at(res.rows, 0)

    Enum.to_list(0..(length(res.columns) - 1))
    |> Enum.reduce(%{}, fn i, acc ->
      Map.put(acc, Enum.at(res.columns, i), Enum.at(res_row, i))
    end)
  end

  def getSimpleUserByIds(conn, ids) do
    res =
      "?"
      |> List.duplicate(length(ids))
      |> Enum.join(", ")
      |> (&MyXQL.query!(
            conn,
            "SELECT image, usertag, username, id
            FROM User
            WHERE id IN (" <> &1 <> ")",
            ids
          )).()

    res.rows
    |> Enum.reduce(%{}, fn row, acc ->
      Enum.to_list(0..(length(res.columns) - 1))
      |> Enum.reduce(%{}, fn i, acc ->
        Map.put(acc, Enum.at(res.columns, i), Enum.at(row, i))
      end)
      |> (&Map.put(acc, &1["id"], &1)).()
    end)
  end

  def getSimpleUserByTags(conn, tags) do
    res =
      "?"
      |> List.duplicate(length(tags))
      |> Enum.join(", ")
      |> (&MyXQL.query!(
            conn,
            "SELECT image, usertag, username, id
            FROM User
            WHERE usertag IN (" <> &1 <> ")",
            tags
          )).()

    res.rows
    |> Enum.reduce(%{}, fn row, acc ->
      Enum.to_list(0..(length(res.columns) - 1))
      |> Enum.reduce(%{}, fn i, acc ->
        Map.put(acc, Enum.at(res.columns, i), Enum.at(row, i))
      end)
      |> (&Map.put(acc, &1["id"], Map.delete(&1, "id"))).()
    end)
  end

  def getUserIdsByTags(conn, tags) do
    res =
      MyXQL.query!(
        conn,
        "SELECT id
        FROM User
        WHERE usertag IN ?",
        [tags]
      )

    res.rows |> List.flatten()
  end

  def insertTypedMessage(conn, type, groupId, messageIds, userIds) do
    "(?, ?, ?, ?, ?)"
    |> List.duplicate(length(userIds))
    |> Enum.join(", ")
    |> (&MyXQL.query!(
          conn,
          "INSERT INTO Messages (id, userId, messageGroupId, content, type)
          VALUES " <> &1,
          0..(length(userIds) - 1)
          |> Enum.map(fn i ->
            [Enum.at(messageIds, i), Enum.at(userIds, i), groupId, "", type]
          end)
        )).()
  end

  def getMessages(conn, messageIds) do
    res =
      "?"
      |> List.duplicate(length(messageIds))
      |> Enum.join(",")
      |> (&MyXQL.query!(
            conn,
            "
          SELECT m.id, u.username, u.usertag, u.image, m.content, m.created, m.type
          FROM Message m
          JOIN User u ON u.id = m.userId
          WHERE m.id IN (" <> &1 <> ")",
            messageIds
          )).()

    res.rows
    |> Enum.reduce([], fn row, acc ->
      Enum.to_list(0..(length(res.columns) - 1))
      |> Enum.reduce(%{}, fn i, acc ->
        Map.put(acc, Enum.at(res.columns, i), Enum.at(row, i))
      end)
      |> (&[&1 | acc]).()
    end)
  end

  def getUsersFromMessages(messages) do
    messages
    |> Enum.flat_map(fn message ->
      [message["username"], message["usertag"], message["image"]]
    end)
  end

  def generateIDs(count) do
    1..count
    |> Enum.map(fn _ ->
      Nanoid.generate()
    end)
  end
end
