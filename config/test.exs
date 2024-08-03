import Config

config :venomous, :test_snake_supervisor, true

config :venomous,
  serpent_watcher: [
    enable: true
  ]

config :venomous, :snake_manager, %{
  erlport_encoder: %{},
  reload_logging: false,
  python_opts: [
    module_paths: ["python/"]
  ]
}
