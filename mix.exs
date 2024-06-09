defmodule Venomous.MixProject do
  use Mix.Project

  def project do
    [
      app: :venomous,
      description: "A wrapper for managing concurrent Erlport python processes",
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      licenses: ["GPL-3.0-or-later"],
      links: %{
        "GitHub" => "https://github.com/RustySnek/Venomous"
      },
      # Docs
      name: "Venomous",
      source_url: "https://github.com/RustySnek/Venomous",
      docs: [
        main: "Venomous",
        # TODO: logo: "path"
        extras: ["README.md"]
      ]
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
      # {:dep_from_hexpm, "~> 0.3.0"},
      {:timex, "~> 3.7.11"},
      {:erlport, "~> 0.11.0"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
