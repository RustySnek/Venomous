import Config

config :venomous, :test_snake_supervisor, true

config :venomous,
  serpent_watcher: [
    enable: true,
    blacklist: ["meow"]
  ]

config :venomous, :snake_manager, %{
  erlport_encoder: %{},
  python_opts: [
    module_paths: ["python/", ".devenv/state/venv/lib/python3.11/site-packages"]
  ]
}
