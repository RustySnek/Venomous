import Config

config :venomous, :test_snake_supervisor, true

config :venomous,
  serpent_watcher: [
    logging: false,
    enable: false
  ]

config :venomous, :snake_manager, %{
  erlport_encoder: %{},
  python_opts: [
    module_paths: ["python/"]
  ]
}
