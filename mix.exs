defmodule Secant.MixProject do
  use Mix.Project

  def project do
    [
      app: :secant,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Secant.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:thousand_island, "~> 1.4"}
    ]
  end
end
