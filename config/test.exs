import Config

config :venomous, :test_snake_supervisor, true

config :venomous,
  serpent_watcher: [
    enable: true,
    blacklist: ["meow"]
  ]

config :venomous, :snake_manager, %{
  erlport_encoder: %{}
}
