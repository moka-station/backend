import Config

config :ex_aws,
  access_key_id: "${AWS_ACCESS_KEY_ID}",
  secret_access_key: "${AWS_SECRET_ACCESS_KEY}"

config :backend,
  username: "${USERNAME}",
  database: "${DATABASE}",
  hostname: "${HOSTNAME}",
  password: "${PASSWORD}",
  bucket: "${BUCKET}",
  env: config_env(),
  event_key: "${EVENT_KEY}"
