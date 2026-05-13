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
        # interface_classes: ["MyTemperatureController", "Drivable", "Writable", "Readable"]
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

    quote do
      # Expose the interface spec as a function so it can be retrieved at
      # compile time by Secant.Module.__using__ without going through AST.
      def __secant_interface_class__ do
        %Secant.InterfaceClass{
          name: unquote(name),
          extends: unquote(extends),
          requires_params: unquote(requires_params),
          requires_commands: unquote(requires_cmds)
        }
      end

      # Pass the module name (a plain atom) as the :interface option so it
      # survives macro quoting without needing Macro.escape on a struct.
      defmacro __using__(_inner_opts) do
        quote do
          use Secant.Module, interface: unquote(__MODULE__)
        end
      end
    end
  end
end
