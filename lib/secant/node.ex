defmodule Secant.Node do
  @moduledoc """
  Top-level supervisor for a single SECoP SEC node.

  ## Usage

      children = [
        {Secant.Node, [
          equipment_id: "my_node",
          description: "My SEC node",
          port: 10767,
          modules: [{"temp", MyTempModule}],
          properties: [_facility: "PSI"]
        ]}
      ]
  """

  use Supervisor

  alias Secant.Protocol

  @standard_node_properties Protocol.standard_node_properties()

  def start_link(opts) do
    equipment_id = Keyword.fetch!(opts, :equipment_id)
    name = :"secant_node_#{equipment_id}"
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    equipment_id = Keyword.fetch!(opts, :equipment_id)
    description = Keyword.get(opts, :description, "")
    port = Keyword.get(opts, :port, 10767)
    modules = Keyword.get(opts, :modules, [])
    raw_properties = Keyword.get(opts, :properties, [])

    node_name = String.to_atom(equipment_id)
    node_properties = validate_and_encode_node_properties!(raw_properties)

    module_map = Map.new(modules)

    dispatcher_opts = %{
      node_name: node_name,
      equipment_id: equipment_id,
      description: description,
      node_properties: node_properties,
      modules: module_map
    }

    module_children =
      Enum.map(modules, fn {mod_name, mod} ->
        %{
          id: {Secant.Module.Server, mod_name},
          start:
            {Secant.Module.Server, :start_link,
             [%{name: mod_name, module: mod, node_name: node_name, opts: []}]}
        }
      end)

    children =
      [{Secant.Dispatcher, dispatcher_opts}] ++
        module_children ++
        [Secant.TCPServer.child_spec(port: port, node_name: node_name)]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # ---- private ----

  defp validate_and_encode_node_properties!(properties) do
    Enum.each(properties, fn {key, _val} ->
      key_str = Atom.to_string(key)

      unless key_str in @standard_node_properties or String.starts_with?(key_str, "_") do
        raise ArgumentError,
              "Node property '#{key}' is not a standard SECoP node property. " <>
                "Non-standard properties must be prefixed with '_' (e.g. :_#{key})."
      end
    end)

    Map.new(properties, fn {k, v} -> {Atom.to_string(k), v} end)
  end
end
