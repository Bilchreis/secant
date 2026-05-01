defmodule Secant.Connection do
  @moduledoc "ThousandIsland handler — one process per TCP client connection."

  use ThousandIsland.Handler

  alias Secant.{Protocol, Errors}
  alias Secant.Module.Server, as: ModServer

  @impl ThousandIsland.Handler
  def handle_connection(_socket, state), do: {:continue, state}

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    buffer = Map.get(state, :buffer, "") <> data
    {new_buffer, responses, new_state} = extract_messages(buffer, state, [])

    Enum.each(responses, fn
      {:raw, raw_data} -> ThousandIsland.Socket.send(socket, raw_data)
      msg -> ThousandIsland.Socket.send(socket, Protocol.encode_frame(msg))
    end)

    {:continue, %{new_state | buffer: new_buffer}}
  end

  @impl GenServer
  def handle_info({:secant_update, mod_name, param_name, encoded, qualifiers}, {socket, state}) do
    msg = {"update", "#{mod_name}:#{param_name}", [encoded, qualifiers]}
    ThousandIsland.Socket.send(socket, Protocol.encode_frame(msg))
    {:noreply, {socket, state}}
  end

  def handle_info(_msg, {socket, state}), do: {:noreply, {socket, state}}

  @impl ThousandIsland.Handler
  def handle_close(_socket, _state), do: :ok

  @impl ThousandIsland.Handler
  def handle_error(_error, _socket, _state), do: :ok

  # ---- private ----

  defp extract_messages(buffer, state, acc) do
    case Protocol.get_next_message(buffer) do
      {:more, remaining} ->
        {remaining, acc, state}

      {:ok, message, rest} ->
        {responses, new_state} = handle_message(message, state)
        extract_messages(rest, new_state, acc ++ responses)

      {:error, _reason} ->
        extract_messages("", state, acc)
    end
  end

  defp handle_message({"*IDN?", _spec, _data}, state) do
    {[{:raw, "ISSE,SECoP,,v1.1\n"}], state}
  end

  defp handle_message({"describe", _spec, _data}, state) do
    {descriptor, new_state} = get_or_build_descriptor(state)
    {[{"describing", ".", descriptor}], new_state}
  end

  defp handle_message({"read", spec, _data}, state) do
    response =
      case parse_module_param(spec, "value", state) do
        {:error, err} -> error_response("read", spec, err)
        {:ok, mod_name, param_name} ->
          result = ModServer.read(state.node_name, mod_name, param_name)
          build_response("reply", "read", spec, result)
      end

    {[response], state}
  end

  defp handle_message({"change", spec, data}, state) do
    response =
      case parse_module_param(spec, nil, state) do
        {:error, err} -> error_response("change", spec, err)
        {:ok, mod_name, param_name} ->
          result = ModServer.write(state.node_name, mod_name, param_name, data)
          build_response("changed", "change", spec, result)
      end

    {[response], state}
  end

  defp handle_message({"do", spec, data}, state) do
    response =
      case parse_module_param(spec, nil, state) do
        {:error, err} -> error_response("do", spec, err)
        {:ok, mod_name, cmd_name} ->
          result = ModServer.execute(state.node_name, mod_name, cmd_name, data)
          build_response("done", "do", spec, result)
      end

    {[response], state}
  end

  defp handle_message({"ping", spec, _data}, state) do
    token = spec || ""
    {[{"pong", token, [nil, %{"t" => now()}]}], state}
  end

  defp handle_message({"activate", spec, _data}, state) do
    Registry.register(Secant.PubSub, state.node_name, nil)
    current_value_msgs = gather_current_values(state)
    reply_spec = spec || ""
    {current_value_msgs ++ [{"active", reply_spec, nil}], state}
  end

  defp handle_message({"deactivate", spec, _data}, state) do
    Registry.unregister(Secant.PubSub, state.node_name)
    reply_spec = spec || ""
    {[{"inactive", reply_spec, nil}], state}
  end

  defp handle_message({action, spec, _data}, state) do
    err = Errors.protocol_error("Unknown action '#{action}'")
    {[error_response(action, spec, err)], state}
  end

  defp get_or_build_descriptor(%{descriptor_cache: desc} = state) when not is_nil(desc) do
    {desc, state}
  end

  defp get_or_build_descriptor(state) do
    modules =
      Map.new(state.modules, fn {mod_name, _mod} ->
        case ModServer.describe(state.node_name, mod_name) do
          {:error, _} -> {mod_name, %{}}
          desc -> {mod_name, desc}
        end
      end)

    base = %{
      "equipment_id" => state.equipment_id,
      "description" => state.description,
      "firmware" => Secant.firmware(),
      "modules" => modules
    }

    descriptor = Map.merge(base, state.node_properties)
    {descriptor, Map.put(state, :descriptor_cache, descriptor)}
  end

  defp gather_current_values(state) do
    Enum.flat_map(state.modules, fn {mod_name, _mod} ->
      case ModServer.current_values(state.node_name, mod_name) do
        list when is_list(list) ->
          Enum.map(list, fn {param_name, value, timestamp, error} ->
            qualifiers = build_qualifiers(timestamp, error)
            {"update", "#{mod_name}:#{param_name}", [value, qualifiers]}
          end)

        _ ->
          []
      end
    end)
  end

  defp parse_module_param(nil, _default, _state) do
    {:error, Errors.protocol_error("Missing specifier")}
  end

  defp parse_module_param(spec, default_param, state) do
    case String.split(spec, ":", parts: 2) do
      [mod] when default_param != nil ->
        if Map.has_key?(state.modules, mod),
          do: {:ok, mod, default_param},
          else: {:error, Errors.no_such_module("Module '#{mod}' not found")}

      [_mod] ->
        {:error, Errors.protocol_error("Specifier '#{spec}' missing parameter name")}

      [mod, param] ->
        if Map.has_key?(state.modules, mod),
          do: {:ok, mod, param},
          else: {:error, Errors.no_such_module("Module '#{mod}' not found")}
    end
  end

  defp build_response(reply_action, _err_action, spec, {:ok, report}),
    do: {reply_action, spec, report}

  defp build_response(_reply_action, err_action, spec, {:error, %Secant.Error{} = err}),
    do: error_response(err_action, spec, err)

  defp error_response(action, spec, %Secant.Error{name: name, message: msg}),
    do: {"error_#{action}", spec, [name, msg, %{}]}

  defp build_qualifiers(ts, nil), do: %{"t" => ts}
  defp build_qualifiers(ts, %Secant.Error{name: n, message: m}),
    do: %{"t" => ts, "error" => n, "message" => m}

  defp now, do: System.os_time(:millisecond) / 1000.0
end
