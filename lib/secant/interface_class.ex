defmodule Secant.InterfaceClass do
  @moduledoc """
  Defines a custom SECoP interface class that extends one of the standard
  interface atoms (`:readable`, `:writable`, `:drivable`) or another custom class.

  ## Usage

      defmodule MyApp.MyTemperatureController do
        use Secant.InterfaceClass,
          name: "MyTemperatureController",
          extends: :drivable,
          requires_params: [:ramp]
      end

      defmodule MyApp.TempSensor do
        use MyApp.MyTemperatureController
        # interface_classes: ["MyTemperatureController", "Drivable", "Writable", "Readable", "Module"]
        # required: value, status, target, ramp params + stop command
      end
  """

  @enforce_keys [:name, :extends]
  defstruct [:name, :extends, requires_params: [], requires_commands: []]

  @type t :: %__MODULE__{
          name: String.t(),
          extends: :readable | :writable | :drivable | t(),
          requires_params: [atom()],
          requires_commands: [atom()]
        }

  defmacro __using__(opts) do
    name            = Keyword.fetch!(opts, :name)
    extends         = Keyword.fetch!(opts, :extends)
    requires_params = Keyword.get(opts, :requires_params, [])
    requires_cmds   = Keyword.get(opts, :requires_commands, [])

    interface = %Secant.InterfaceClass{
      name: name,
      extends: extends,
      requires_params: requires_params,
      requires_commands: requires_cmds
    }

    escaped = Macro.escape(interface)

    quote do
      defmacro __using__(inner_opts) do
        merged = Keyword.put(inner_opts, :interface, unquote(escaped))

        quote do
          use Secant.Module, unquote(merged)
        end
      end
    end
  end
end
