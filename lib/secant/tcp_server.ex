defmodule Secant.TCPServer do
  @moduledoc "Thin wrapper that configures ThousandIsland for a SEC node."

  def child_spec(opts) do
    port = Keyword.fetch!(opts, :port)
    node_name = Keyword.fetch!(opts, :node_name)

    thousand_island_opts = [
      port: port,
      handler_module: Secant.Connection,
      handler_options: %{node_name: node_name, buffer: ""},
      transport_options: [reuseaddr: true]
    ]

    %{
      id: {ThousandIsland, node_name},
      start: {ThousandIsland, :start_link, [thousand_island_opts]},
      type: :supervisor
    }
  end
end
