import Config

config :venomous, :snake_supervisor_enabled, true

config :venomous, :snake_manager, %{
  erlport_encoder: %{}
}
