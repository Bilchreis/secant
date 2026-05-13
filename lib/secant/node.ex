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
          properties: [_facility: "PSI"],

          # UDP discovery options (all optional):
          discovery: true,            # default true — set false to disable
          discovery_port: 10767,      # UDP port (default 10767)
          startup_broadcast: true     # broadcast on startup (default true)
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

    unless is_binary(description) and description != "" do
      raise ArgumentError, "Node :description must be a non-empty string"
    end

    port = Keyword.get(opts, :port, 10767)
    modules = Keyword.get(opts, :modules, [])
    raw_properties = Keyword.get(opts, :properties, [])
    discovery_enabled = Keyword.get(opts, :discovery, true)
    discovery_port = Keyword.get(opts, :discovery_port, 10767)
    startup_broadcast = Keyword.get(opts, :startup_broadcast, true)

    node_name = String.to_atom(equipment_id)
    node_properties = validate_and_encode_node_properties!(raw_properties)

    module_map =
      Map.new(modules, fn
        {name, mod} -> {name, mod}
        {name, mod, _opts} -> {name, mod}
      end)

    module_children =
      Enum.map(modules, fn
        {mod_name, mod} -> build_module_child(mod_name, mod, node_name, [])
        {mod_name, mod, mod_opts} -> build_module_child(mod_name, mod, node_name, mod_opts)
      end)

    discovery_children =
      if discovery_enabled do
        discovery_opts = %{
          equipment_id: equipment_id,
          description: description,
          tcp_port: port,
          discovery_port: discovery_port,
          startup_broadcast: startup_broadcast
        }

        [%{id: {Secant.Discovery, equipment_id}, start: {Secant.Discovery, :start_link, [discovery_opts]}}]
      else
        []
      end

    tcp_child =
      Secant.TCPServer.child_spec(
        port: port,
        node_name: node_name,
        equipment_id: equipment_id,
        description: description,
        modules: module_map,
        node_properties: node_properties
      )

    children = module_children ++ [tcp_child] ++ discovery_children

    Supervisor.init(children, strategy: :one_for_one)
  end

  # ---- private ----

  defp build_module_child(mod_name, mod, node_name, mod_opts) do
    %{
      id: {Secant.Module.Server, mod_name},
      start:
        {Secant.Module.Server, :start_link,
         [%{name: mod_name, module: mod, node_name: node_name, opts: mod_opts}]}
    }
  end

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
