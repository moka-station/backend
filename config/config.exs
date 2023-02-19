import Config

config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")

config :backend,
  username: System.get_env("USERNAME"),
  database: System.get_env("DATABASE"),
  hostname: System.get_env("HOSTNAME"),
  password: System.get_env("PASSWORD"),
  bucket: System.get_env("BUCKET"),
  env: config_env(),
  event_key: System.get_env("EVENT_KEY")
