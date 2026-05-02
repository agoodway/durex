defmodule Durex.MixProject do
  use Mix.Project

  def project do
    [
      app: :durex,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:ex_unit]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [check: :test, precommit: :test]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:redix, "~> 1.5", optional: true},

      # Code Quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_dna, github: "dannote/ex_dna", branch: "master", only: [:dev, :test], runtime: false},
      {:ex_slop,
       github: "dannote/ex_slop", branch: "master", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format --check-formatted",
        "credo --strict",
        "doctor",
        "dialyzer",
        "test"
      ],
      precommit: ["check"]
    ]
  end
end
