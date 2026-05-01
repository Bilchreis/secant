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
      {:jason, git: "https://github.com/michalmuskala/jason.git", tag: "v1.4.4"},
      {:thousand_island, git: "https://github.com/mtrudel/thousand_island.git", tag: "1.3.9"},
      {:telemetry, git: "https://github.com/beam-telemetry/telemetry.git", tag: "v1.3.0", override: true}
    ]
  end
end
