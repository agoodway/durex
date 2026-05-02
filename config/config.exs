import Config

# Host applications must configure these values:
#
#   config :durex, :app_name, :my_app
#
#   config :durex, Durex.Store.Redis,
#     connection: MyApp.Redis

if config_env() == :test do
  config :durex, :app_name, :durex_test

  config :durex, Durex.Store.Redis, connection: :durex_test_redis
end
