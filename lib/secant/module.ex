defmodule Secant.ParamSpec do
  @moduledoc "Spec struct for a SECoP parameter — use this for IDE field completion."
  @enforce_keys [:description]
  @type t :: %__MODULE__{
          description: String.t(),
          datatype: Secant.DataType.t() | nil,
          readonly: boolean() | nil,
          default: term(),
          properties: map() | nil,
          group: String.t() | nil,
          visibility: String.t() | nil
        }
  defstruct [:description, :datatype, :readonly, :default, :properties, :group, :visibility]
end

defmodule Secant.CommandSpec do
  @moduledoc "Spec struct for a SECoP command — use this for IDE field completion."
  @enforce_keys [:description]
  @type t :: %__MODULE__{
          description: String.t(),
          argument: Secant.DataType.t() | nil,
          result: Secant.DataType.t() | nil,
          properties: map() | nil,
          group: String.t() | nil,
          visibility: String.t() | nil
        }
  defstruct [:description, :argument, :result, :properties, :group, :visibility]
end

defmodule Secant.Module.Behaviour do
  @moduledoc "Optional callbacks for user-defined SEC modules."

  @callback init_module(opts :: keyword()) :: {:ok, user_state :: term()}
  @callback do_poll(user_state :: term()) :: {:ok, term()} | {:noreply, term()}

  @optional_callbacks [init_module: 1, do_poll: 1]
end

defmodule Secant.Module do
  @moduledoc """
  `use Secant.Module` — declarative API for defining SECoP SEC modules.

  Prefer the dedicated interface modules over the raw `interface:` option:

      use Secant.Module              # base module, no interface class
      use Secant.Module.Readable     # requires value + status
      use Secant.Module.Writable     # requires value + status + target
      use Secant.Module.Drivable     # requires value + status + target + stop

  Custom interface classes are defined with `Secant.InterfaceClass`.

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

  alias Secant.Protocol

  @standard_params Protocol.standard_params()
  @standard_commands Protocol.standard_commands()

  defmacro __using__(opts) do
    raw_interface = Keyword.get(opts, :interface, nil)

    # When a custom InterfaceClass module passes itself as the :interface
    # option it arrives as a plain atom (module name), which is valid AST.
    # Resolve it to the actual struct here at compile time.
    interface =
      case raw_interface do
        nil -> nil
        atom when atom in [:readable, :writable, :drivable] -> atom
        %Secant.InterfaceClass{} = s -> s
        mod when is_atom(mod) -> mod.__secant_interface_class__()
      end

    iface_mod              = to_interface_module(interface)
    {req_params, req_cmds} = interface_requirements(interface)
    iface_classes          = interface_class_list(interface)
    iface_label            = interface_label(interface)

    quote do
      @behaviour Secant.Module.Behaviour

      Module.register_attribute(__MODULE__, :secant_params, accumulate: true)
      Module.register_attribute(__MODULE__, :secant_commands, accumulate: true)
      Module.register_attribute(__MODULE__, :secant_properties, accumulate: true)
      Module.register_attribute(__MODULE__, :secant_description, [])

      @secant_interface_classes unquote(iface_classes)
      @secant_interface_label   unquote(iface_label)
      @secant_req_params        unquote(req_params)
      @secant_req_cmds          unquote(req_cmds)
      @secant_iface_mod         unquote(iface_mod)

      import Secant.Module, only: [defparam: 2, defcommand: 2, defproperty: 2, description: 1]
      import Secant.DataType
      alias Secant.DataType, as: DT
      alias Secant.ParamSpec
      alias Secant.CommandSpec

      @before_compile Secant.Module
    end
  end

  defmacro defparam(name, do: block) do
    map_expr = {:%{}, [], spec_block_to_fields(block)}
    quote do
      @secant_params {unquote(name), unquote(map_expr)}
    end
  end

  defmacro defparam(name, spec) do
    quote do
      @secant_params {unquote(name), unquote(spec)}
    end
  end

  defmacro defcommand(name, do: block) do
    map_expr = {:%{}, [], spec_block_to_fields(block)}
    quote do
      @secant_commands {unquote(name), unquote(map_expr)}
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

  defmacro description(text) do
    quote do
      @secant_description unquote(text)
    end
  end

  defmacro __before_compile__(env) do
    iface_classes  = Module.get_attribute(env.module, :secant_interface_classes)
    iface_label    = Module.get_attribute(env.module, :secant_interface_label)
    req_params     = Module.get_attribute(env.module, :secant_req_params)
    req_cmds       = Module.get_attribute(env.module, :secant_req_cmds)
    iface_mod      = Module.get_attribute(env.module, :secant_iface_mod)
    mod_description = Module.get_attribute(env.module, :secant_description)

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

    validate_names!(env.module, user_params, user_commands, properties)
    validate_descriptions!(env.module, user_params, user_commands)
    validate_module_description!(env.module, mod_description)
    validate_interface!(env.module, iface_label, req_params, req_cmds, user_params, user_commands)
    if iface_mod, do: iface_mod.validate!(env.module, user_params, user_commands)

    quote do
      def __secant_params__,            do: unquote(Macro.escape(user_params))
      def __secant_commands__,          do: unquote(Macro.escape(user_commands))
      def __secant_properties__,        do: unquote(Macro.escape(properties))
      def __secant_interface_classes__, do: unquote(iface_classes)
      def __secant_description__,       do: unquote(mod_description)

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

  defp validate_descriptions!(mod, params, commands) do
    Enum.each(params, fn {name, spec} ->
      unless valid_description?(extract_description(spec)) do
        raise CompileError,
          file: "#{mod}",
          description: "Parameter '#{name}' must have a non-empty :description."
      end
    end)

    Enum.each(commands, fn {name, spec} ->
      unless valid_description?(extract_description(spec)) do
        raise CompileError,
          file: "#{mod}",
          description: "Command '#{name}' must have a non-empty :description."
      end
    end)
  end

  defp validate_module_description!(mod, desc) do
    unless valid_description?(desc) do
      raise CompileError,
        file: "#{mod}",
        description:
          "Module must have a non-empty description. " <>
            "Add: description \"your description\""
    end
  end

  defp valid_description?(desc), do: is_binary(desc) and desc != ""

  defp extract_description(spec) when is_map(spec), do: Map.get(spec, :description)
  defp extract_description(_), do: nil

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

  defp validate_interface!(mod, label, req_params, req_cmds, params, commands) do
    param_names = Enum.map(params, &elem(&1, 0))
    cmd_names   = Enum.map(commands, &elem(&1, 0))

    Enum.each(req_params, fn name ->
      unless name in param_names do
        raise CompileError,
          file: "#{mod}",
          description:
            "#{label} module missing required parameter '#{name}'. " <>
              "Declare it with: defparam :#{name}, %{...}"
      end
    end)

    Enum.each(req_cmds, fn name ->
      unless name in cmd_names do
        raise CompileError,
          file: "#{mod}",
          description:
            "#{label} module missing required command '#{name}'. " <>
              "Declare it with: defcommand :#{name}, %{...}"
      end
    end)
  end

  defp to_interface_module(nil),       do: nil
  defp to_interface_module(:readable), do: Secant.Module.Readable
  defp to_interface_module(:writable), do: Secant.Module.Writable
  defp to_interface_module(:drivable), do: Secant.Module.Drivable
  defp to_interface_module(%Secant.InterfaceClass{extends: parent}), do: to_interface_module(parent)

  defp interface_requirements(nil), do: {[], []}
  defp interface_requirements(atom) when atom in [:readable, :writable, :drivable] do
    mod = to_interface_module(atom)
    {mod.required_params(), mod.required_commands()}
  end
  defp interface_requirements(%Secant.InterfaceClass{extends: parent, requires_params: rp, requires_commands: rc}) do
    {base_params, base_cmds} = interface_requirements(parent)
    {Enum.uniq(base_params ++ rp), Enum.uniq(base_cmds ++ rc)}
  end

  defp interface_label(nil), do: "Module"
  defp interface_label(atom) when atom in [:readable, :writable, :drivable] do
    atom |> to_interface_module() |> then(fn mod -> hd(mod.class_list()) end)
  end
  defp interface_label(%Secant.InterfaceClass{name: name}), do: name

  defp interface_class_list(nil), do: []
  defp interface_class_list(atom) when atom in [:readable, :writable, :drivable] do
    to_interface_module(atom).class_list()
  end
  defp interface_class_list(%Secant.InterfaceClass{name: name, extends: parent}) do
    [name | interface_class_list(parent)]
  end

  defp spec_block_to_fields({:__block__, _, stmts}), do: Enum.map(stmts, &stmt_to_field/1)
  defp spec_block_to_fields(single), do: [stmt_to_field(single)]

  defp stmt_to_field({key, _meta, [value_expr]}), do: {key, value_expr}
end
