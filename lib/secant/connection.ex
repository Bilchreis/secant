defmodule Secant.Connection do
  @moduledoc "ThousandIsland handler — one process per TCP client connection."

  use ThousandIsland.Handler

  alias Secant.{Protocol, Dispatcher}

  @impl ThousandIsland.Handler
  def handle_connection(_socket, state) do
    {:continue, state}
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    buffer = Map.get(state, :buffer, "") <> data
    {new_buffer, responses} = extract_messages(buffer, state.node_name, [])

    Enum.each(responses, fn
      {:raw, raw_data} ->
        ThousandIsland.Socket.send(socket, raw_data)

      msg ->
        ThousandIsland.Socket.send(socket, Protocol.encode_frame(msg))
    end)

    {:continue, Map.put(state, :buffer, new_buffer)}
  end

  @impl GenServer
  def handle_info({:send_message, msg}, {socket, state}) do
    ThousandIsland.Socket.send(socket, Protocol.encode_frame(msg))
    {:noreply, {socket, state}}
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, state) do
    node_name = Map.get(state, :node_name)
    if node_name, do: Dispatcher.remove_connection(node_name, self())
    :ok
  end

  @impl ThousandIsland.Handler
  def handle_error(_error, _socket, state) do
    node_name = Map.get(state, :node_name)
    if node_name, do: Dispatcher.remove_connection(node_name, self())
    :ok
  end

  # ---- private ----

  defp extract_messages(buffer, node_name, acc) do
    case Protocol.get_next_message(buffer) do
      {:more, remaining} ->
        {remaining, Enum.reverse(acc)}

      {:ok, message, rest} ->
        response = Dispatcher.handle_message(node_name, self(), message)
        extract_messages(rest, node_name, [response | acc])

      {:error, _reason} ->
        extract_messages("", node_name, acc)
    end
  end
end
