defmodule Secant do
  @moduledoc """
  Secant — an Elixir framework for creating SECoP SEC nodes.

  ## Quick start

      defmodule MyModule do
        use Secant.Module, interface: :readable

        defparam :value, %{
          description: "sensor reading",
          datatype: {:double, unit: "K"},
          readonly: true
        }

        def read_value(state), do: {:ok, 42.0, state}
      end

      # In your Application supervisor:
      {Secant.Node, [
        equipment_id: "my_node",
        description: "My SECoP node",
        port: 10767,
        modules: [{"sensor", MyModule}]
      ]}
  """

  @version Mix.Project.config()[:version]

  def version, do: @version

  def firmware, do: "secant #{@version}"
end
