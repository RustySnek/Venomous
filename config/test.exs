import Config

config :venomous, :test_snake_supervisor, true

config :venomous,
  serpent_watcher: [
    logging: false,
    enable: false
  ]

config :venomous, :snake_manager, %{
  erlport_encoder: %{
    module: :test_venomous,
    func: :erl_encode,
    args: []
  },
  python_opts: [
    module_paths: ["priv/"]
  ]
}
