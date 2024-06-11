defmodule Venomous.MixProject do
  use Mix.Project

  @version "0.1.1"

  def project do
    [
      app: :venomous,
      description: "A wrapper for managing concurrent Erlport python processes",
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      # Docs
      name: "Venomous",
      source_url: "https://github.com/RustySnek/Venomous",
      docs: [
        main: "Venomous",
        logo: "./assets/venomous_logo.png",
        extras: ["README.md", "PYTHON.md"]
      ]
    ]
  end

  defp package do
    [
      licenses: ["GPL-3.0-or-later"],
      links: %{
        "GitHub" => "https://github.com/RustySnek/Venomous"
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Venomous.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:timex, "~> 3.7.11"},
      {:erlport, "~> 0.11.0"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
