defmodule Secant.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Secant.Registry}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Secant.Supervisor)
  end
end
