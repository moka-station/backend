defmodule Storage do
  alias ExAws.S3, as: S3

  def getBuckets do
    S3.list_buckets()
    |> ExAws.request!()
  end

  def putObject(key, binary) do
    bucket_name = Application.fetch_env!(:backend, :bucket)
    %{status_code: code} = S3.put_object(bucket_name, key, binary) |> ExAws.request!()

    if code == 200 do
      :ok
    else
      :fail
    end
  end

  def putGroupImage(groupId, image) do
    path = "messageGroup/" <> groupId <> ".png"
    binary = Base.decode64!(image)

    if IO.iodata_length(binary) > 1_000_000 do
      raise("over size")
    end

    true = ExImageInfo.seems?(binary, :png)
    Storage.putObject(path, binary)
  end

  def deleteObject(key) do
    bucket_name = Application.fetch_env!(:backend, :bucket)
    %{status_code: code} = S3.delete_object(bucket_name, key) |> ExAws.request!()

    if code == 204 do
      :ok
    else
      :fail
    end
  end

  def deleteGroupImage(groupId) do
    path = "messageGroup/" <> groupId <> ".png"
    deleteObject(path)
  end
end
