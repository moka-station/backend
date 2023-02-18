defmodule Backend do
  use Application

  def start(_type, _args) do
    children = [
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: Backend.Router,
        options: [
          port: 4000
        ]
      ),
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: Backend.ServerRouter,
        options: [
          port: 6969
        ]
      ),
      Registry.child_spec(
        keys: :duplicate,
        name: Registry.MessageGroup
      ),
      Registry.child_spec(
        keys: :duplicate,
        name: Registry.User
      ),
      if Application.fetch_env!(:backend, :env) == :prod do
        {MyXQL,
         username: Application.fetch_env!(:backend, :username),
         database: Application.fetch_env!(:backend, :database),
         hostname: Application.fetch_env!(:backend, :hostname),
         password: Application.fetch_env!(:backend, :password),
         ssl: true,
         ssl_opts: [
           verify: :verify_peer,
           cacertfile: CAStore.file_path(),
           server_name_indication:
             String.to_charlist(Application.fetch_env!(:backend, :hostname)),
           customize_hostname_check: [
             match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
           ]
         ],
         name: :myxql}
      else
        {
          MyXQL,
          username: Application.fetch_env!(:backend, :username),
          datadatabase: Application.fetch_env!(:backend, :database),
          hostname: Application.fetch_env!(:backend, :hostname),
          port: 3306,
          name: :myxql
        }
      end
    ]

    Storage.getBuckets() |> IO.inspect()

    opts = [strategy: :one_for_one, name: Backend.Application]
    Supervisor.start_link(children, opts)
  end
end
