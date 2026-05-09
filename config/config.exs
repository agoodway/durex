import Config

# Host applications must configure these values:
#
#   config :durex, :app_name, :my_app
#
#   config :durex, Durex.Store.Redis,
#     connection: MyApp.Redis
#
#   # Required Tigris keys: :bucket, :access_key_id, and :secret_access_key.
#   # Optional keys: :endpoint, :region, :prefix, and safe transport :req_options.
#   config :durex, Durex.Store.Tigris,
#     bucket: "my-bucket",
#     access_key_id: "tid_xxx",
#     secret_access_key: "tsec_xxx",
#     prefix: "checkpoints",
#     req_options: [receive_timeout: 5_000, pool_timeout: 1_000]

if config_env() == :test do
  config :durex, :app_name, :durex_test

  config :durex, Durex.Store.Redis, connection: :durex_test_redis
end
