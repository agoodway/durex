import Config

Dotenvy.source([".env", ".env.#{config_env()}", ".env.#{config_env()}.local"])

if config_env() != :test do
  config :durex, Durex.Store.Tigris,
    bucket: Dotenvy.env!("TIGRIS_BUCKET"),
    access_key_id: Dotenvy.env!("TIGRIS_ACCESS_KEY_ID"),
    secret_access_key: Dotenvy.env!("TIGRIS_SECRET_ACCESS_KEY"),
    prefix: "durex-demo"
end
