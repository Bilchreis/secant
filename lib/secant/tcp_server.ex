defmodule Secant.TCPServer do
  @moduledoc "Thin wrapper that configures ThousandIsland for a SEC node."

  def child_spec(opts) do
    port = Keyword.fetch!(opts, :port)
    node_name = Keyword.fetch!(opts, :node_name)
    equipment_id = Keyword.fetch!(opts, :equipment_id)
    description = Keyword.get(opts, :description, "")
    modules = Keyword.get(opts, :modules, %{})
    node_properties = Keyword.get(opts, :node_properties, %{})

    thousand_island_opts = [
      port: port,
      handler_module: Secant.Connection,
      handler_options: %{
        node_name: node_name,
        equipment_id: equipment_id,
        description: description,
        modules: modules,
        node_properties: node_properties,
        buffer: "",
        descriptor_cache: nil
      },
      transport_options: [reuseaddr: true]
    ]

    %{
      id: {ThousandIsland, node_name},
      start: {ThousandIsland, :start_link, [thousand_island_opts]},
      type: :supervisor
    }
  end
end
