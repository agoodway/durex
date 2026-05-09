import Config

config :durex, :app_name, :demo

config :logger, :default_handler,
  config: [type: :standard_io],
  level: :warning

import_config "#{config_env()}.exs"
