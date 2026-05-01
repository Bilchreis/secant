defmodule Secant.Module.Behaviour do
  @moduledoc "Optional callbacks for user-defined SEC modules."

  @callback init_module(opts :: keyword()) :: {:ok, user_state :: term()}
  @callback do_poll(user_state :: term()) :: {:ok, term()} | {:noreply, term()}

  @optional_callbacks [init_module: 1, do_poll: 1]
end

defmodule Secant.Module do
  @moduledoc """
  `use Secant.Module` — declarative API for defining SECoP SEC modules.

  ## Interface classes

  Pass `interface:` option to `use`:
    - `:module`   — base, adds `pollinterval`
    - `:readable` — adds `value`, `status`, `pollinterval`
    - `:writable` — readable + writable `target`
    - `:drivable` — writable + `stop` command

  ## Declaring parameters, commands, and properties

      defparam :value, %{
        description: "current temperature",
        datatype: {:double, min: 0, max: 400, unit: "K"},
        readonly: true
      }

      defcommand :stop, %{description: "Stop", argument: :null, result: :null}

      defproperty :_manufacturer, "ACME Corp"

  ## Callbacks

  Implement `read_<param>(user_state)`, `write_<param>(value, user_state)`,
  `do_<command>(argument, user_state)` as needed.

  Each callback returns `{:ok, value_or_result, new_user_state}` or
  `{:error, %Secant.Error{}, user_state}`.
  """

  alias Secant.DataType
  alias Secant.Protocol

  @standard_params Protocol.standard_params()
  @standard_commands Protocol.standard_commands()

  defmacro __using__(opts) do
    interface = Keyword.get(opts, :interface, :module)

    quote do
      @behaviour Secant.Module.Behaviour

      Module.register_attribute(__MODULE__, :secant_params, accumulate: true)
      Module.register_attribute(__MODULE__, :secant_commands, accumulate: true)
      Module.register_attribute(__MODULE__, :secant_properties, accumulate: true)

      @secant_interface unquote(interface)

      import Secant.Module, only: [defparam: 2, defcommand: 2, defproperty: 2]

      @before_compile Secant.Module
    end
  end

  defmacro defparam(name, spec) do
    quote do
      @secant_params {unquote(name), unquote(spec)}
    end
  end

  defmacro defcommand(name, spec) do
    quote do
      @secant_commands {unquote(name), unquote(spec)}
    end
  end

  defmacro defproperty(name, value) do
    quote do
      @secant_properties {unquote(name), unquote(value)}
    end
  end

  defmacro __before_compile__(env) do
    interface = Module.get_attribute(env.module, :secant_interface)

    user_params =
      env.module
      |> Module.get_attribute(:secant_params)
      |> Enum.reverse()

    user_commands =
      env.module
      |> Module.get_attribute(:secant_commands)
      |> Enum.reverse()

    properties =
      env.module
      |> Module.get_attribute(:secant_properties)
      |> Enum.reverse()

    # Validate underscore prefix on non-standard names
    validate_names!(env.module, user_params, user_commands, properties)

    # Inject interface-mandated params/commands (user declarations take precedence)
    {params, commands} = inject_interface_defaults(interface, user_params, user_commands)

    interface_classes = interface_class_list(interface)

    quote do
      def __secant_params__,            do: unquote(Macro.escape(params))
      def __secant_commands__,          do: unquote(Macro.escape(commands))
      def __secant_properties__,        do: unquote(Macro.escape(properties))
      def __secant_interface__,         do: unquote(interface)
      def __secant_interface_classes__, do: unquote(interface_classes)

      @impl Secant.Module.Behaviour
      def init_module(_opts), do: {:ok, %{}}

      @impl Secant.Module.Behaviour
      def do_poll(user_state) do
        params = __secant_params__()

        new_state =
          Enum.reduce(params, user_state, fn {name, _spec}, st ->
            read_fn = :"read_#{name}"

            if function_exported?(__MODULE__, read_fn, 1) do
              case apply(__MODULE__, read_fn, [st]) do
                {:ok, _val, new_st} -> new_st
                {:error, _, new_st} -> new_st
              end
            else
              st
            end
          end)

        {:ok, new_state}
      end

      defoverridable [init_module: 1, do_poll: 1]
    end
  end

  # --- private compile-time helpers ---

  defp validate_names!(mod, params, commands, properties) do
    Enum.each(params, fn {name, _} ->
      name_str = Atom.to_string(name)
      unless name_str in @standard_params or String.starts_with?(name_str, "_") do
        raise CompileError,
          file: "#{mod}",
          description:
            "Parameter '#{name}' is not a standard SECoP parameter. " <>
              "Non-standard parameters must be prefixed with '_' (e.g. :_#{name})."
      end
    end)

    Enum.each(commands, fn {name, _} ->
      name_str = Atom.to_string(name)
      unless name_str in @standard_commands or String.starts_with?(name_str, "_") do
        raise CompileError,
          file: "#{mod}",
          description:
            "Command '#{name}' is not a standard SECoP command. " <>
              "Non-standard commands must be prefixed with '_' (e.g. :_#{name})."
      end
    end)

    Enum.each(properties, fn {name, _} ->
      name_str = Atom.to_string(name)
      unless String.starts_with?(name_str, "_") do
        raise CompileError,
          file: "#{mod}",
          description:
            "Module property '#{name}' must be prefixed with '_' (e.g. :_#{name})."
      end
    end)
  end

  defp inject_interface_defaults(interface, user_params, user_commands) do
    user_param_names = Enum.map(user_params, fn {n, _} -> n end)
    user_cmd_names = Enum.map(user_commands, fn {n, _} -> n end)

    {default_params, default_commands} = interface_defaults(interface)

    # Prepend defaults that user hasn't overridden
    merged_params =
      Enum.reject(default_params, fn {n, _} -> n in user_param_names end) ++ user_params

    merged_commands =
      Enum.reject(default_commands, fn {n, _} -> n in user_cmd_names end) ++ user_commands

    {merged_params, merged_commands}
  end

  defp interface_defaults(:module) do
    {[{:pollinterval, pollinterval_spec()}], []}
  end

  defp interface_defaults(:readable) do
    params = [
      {:pollinterval, pollinterval_spec()},
      {:value, %{description: "main value", datatype: {:double, []}, readonly: true}},
      {:status, %{description: "module status", datatype: DataType.status_type(), readonly: true}}
    ]

    {params, []}
  end

  defp interface_defaults(:writable) do
    {base_params, base_cmds} = interface_defaults(:readable)

    params =
      base_params ++
        [{:target, %{description: "target value", datatype: {:double, []}, readonly: false}}]

    {params, base_cmds}
  end

  defp interface_defaults(:drivable) do
    {base_params, _base_cmds} = interface_defaults(:writable)
    commands = [{:stop, %{description: "Stop current action", argument: :null, result: :null}}]
    {base_params, commands}
  end

  defp pollinterval_spec do
    %{
      description: "polling interval hint in seconds",
      datatype: {:double, min: 0.1, max: 120.0},
      readonly: false,
      default: 5.0
    }
  end

  defp interface_class_list(:module), do: ["Module"]
  defp interface_class_list(:readable), do: ["Readable", "Module"]
  defp interface_class_list(:writable), do: ["Writable", "Readable", "Module"]
  defp interface_class_list(:drivable), do: ["Drivable", "Writable", "Readable", "Module"]
end
