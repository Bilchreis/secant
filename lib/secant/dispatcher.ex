defmodule Secant.Dispatcher do
  @moduledoc """
  Routes incoming SECoP messages to module servers and manages client subscriptions.
  One dispatcher per Secant.Node.
  """

  use GenServer

  alias Secant.{DataType, Errors}
  alias Secant.Module.Server, as: ModServer

  defmodule State do
    @type subscription :: :all | {:module, String.t()} | {:param, String.t(), String.t()}

    @type t :: %__MODULE__{
            node_name: atom(),
            equipment_id: String.t(),
            description: String.t(),
            node_properties: map(),
            modules: %{String.t() => module()},
            descriptor: map() | nil,
            subscriptions: %{pid() => MapSet.t()},
            topics: %{term() => MapSet.t()}
          }

    defstruct node_name: nil,
              equipment_id: nil,
              description: nil,
              node_properties: %{},
              modules: %{},
              descriptor: nil,
              subscriptions: %{},
              topics: %{}
  end

  # ---- Public API ----

  def start_link(opts) do
    node_name = Map.fetch!(opts, :node_name)
    name = via_name(node_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def handle_message(node_name, conn_pid, message) do
    GenServer.call(via_name(node_name), {:handle_message, conn_pid, message})
  end

  def broadcast_update(node_name, mod_name, param_name, value, timestamp, error) do
    GenServer.cast(via_name(node_name), {:update, mod_name, param_name, value, timestamp, error})
  end

  def set_module_dispatcher(node_name, mod_name) do
    pid = self()
    GenServer.cast(via_name(node_name), {:set_module_dispatcher, mod_name, pid})
  end

  def remove_connection(node_name, conn_pid) do
    GenServer.cast(via_name(node_name), {:remove_connection, conn_pid})
  end

  defp via_name(node_name), do: {:via, Registry, {Secant.Registry, {node_name, :dispatcher}}}

  # ---- GenServer callbacks ----

  @impl true
  def init(opts) do
    state = %State{
      node_name: Map.fetch!(opts, :node_name),
      equipment_id: Map.fetch!(opts, :equipment_id),
      description: Map.fetch!(opts, :description),
      node_properties: Map.get(opts, :node_properties, %{}),
      modules: Map.get(opts, :modules, %{})
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:handle_message, conn_pid, message}, _from, state) do
    {response, new_state} = dispatch(conn_pid, message, state)
    {:reply, response, new_state}
  end

  @impl true
  def handle_cast({:update, mod_name, param_name, value, timestamp, error}, state) do
    specifier = "#{mod_name}:#{param_name}"

    encoded_value =
      case get_module_param_datatype(state, mod_name, param_name) do
        nil -> value
        dtype -> DataType.encode_value(value, dtype)
      end

    qualifiers = build_qualifiers(timestamp, error)
    msg = {"update", specifier, [encoded_value, qualifiers]}

    subscribers = get_subscribers(state, mod_name, param_name)
    Enum.each(subscribers, fn pid -> send(pid, {:send_message, msg}) end)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:remove_connection, conn_pid}, state) do
    {:noreply, cleanup_connection(conn_pid, state)}
  end

  @impl true
  def handle_cast({:set_module_dispatcher, _mod_name, _pid}, state) do
    # Module servers inform us of their PID so we can wire up dispatcher references.
    # Handled at the Node level; no action needed here.
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, cleanup_connection(pid, state)}
  end

  # ---- Dispatch logic ----

  defp dispatch(_conn_pid, {"*IDN?", _spec, _data}, state) do
    {{:raw, "ISSE,SECoP,,v1.1\n"}, state}
  end

  defp dispatch(_conn_pid, {"describe", _spec, _data}, state) do
    {descriptor, new_state} = get_or_build_descriptor(state)
    {{"describing", ".", descriptor}, new_state}
  end

  defp dispatch(_conn_pid, {"read", spec, _data}, state) do
    case parse_module_param(spec, "value") do
      {:error, err} ->
        {error_response("read", spec, err), state}

      {:ok, mod_name, param_name} ->
        case check_module(mod_name, state) do
          {:error, err} ->
            {error_response("read", spec, err), state}

          :ok ->
            result = ModServer.read(state.node_name, mod_name, param_name)
            response = build_response("reply", "read", spec, result)
            {response, state}
        end
    end
  end

  defp dispatch(_conn_pid, {"change", spec, data}, state) do
    case parse_module_param(spec, nil) do
      {:error, err} ->
        {error_response("change", spec, err), state}

      {:ok, mod_name, param_name} ->
        case check_module(mod_name, state) do
          {:error, err} ->
            {error_response("change", spec, err), state}

          :ok ->
            result = ModServer.write(state.node_name, mod_name, param_name, data)
            response = build_response("changed", "change", spec, result)
            {response, state}
        end
    end
  end

  defp dispatch(_conn_pid, {"do", spec, data}, state) do
    case parse_module_param(spec, nil) do
      {:error, err} ->
        {error_response("do", spec, err), state}

      {:ok, mod_name, cmd_name} ->
        case check_module(mod_name, state) do
          {:error, err} ->
            {error_response("do", spec, err), state}

          :ok ->
            result = ModServer.execute(state.node_name, mod_name, cmd_name, data)
            response = build_response("done", "do", spec, result)
            {response, state}
        end
    end
  end

  defp dispatch(_conn_pid, {"ping", spec, _data}, state) do
    token = spec || ""
    ts = now()
    {{"pong", token, [nil, %{"t" => ts}]}, state}
  end

  defp dispatch(conn_pid, {"activate", spec, _data}, state) do
    new_state = subscribe(conn_pid, spec, state)

    # Send current values to the newly subscribed connection
    send_current_values(conn_pid, spec, new_state)

    reply_spec = spec || ""
    {{"active", reply_spec, nil}, new_state}
  end

  defp dispatch(conn_pid, {"deactivate", spec, _data}, state) do
    new_state = unsubscribe(conn_pid, spec, state)
    reply_spec = spec || ""
    {{"inactive", reply_spec, nil}, new_state}
  end

  defp dispatch(_conn_pid, {action, spec, _data}, state) do
    err = Errors.protocol_error("Unknown action '#{action}'")
    {error_response(action, spec, err), state}
  end

  # ---- Subscription management ----

  defp subscribe(conn_pid, nil, state), do: subscribe(conn_pid, "", state)

  defp subscribe(conn_pid, "", state) do
    Process.monitor(conn_pid)
    topic = :all
    add_subscription(conn_pid, topic, state)
  end

  defp subscribe(conn_pid, spec, state) do
    Process.monitor(conn_pid)

    topic =
      case String.split(spec, ":", parts: 2) do
        [mod] -> {:module, mod}
        [mod, param] -> {:param, mod, param}
      end

    add_subscription(conn_pid, topic, state)
  end

  defp add_subscription(conn_pid, topic, state) do
    subs = Map.update(state.subscriptions, conn_pid, MapSet.new([topic]), &MapSet.put(&1, topic))
    topics = Map.update(state.topics, topic, MapSet.new([conn_pid]), &MapSet.put(&1, conn_pid))
    %{state | subscriptions: subs, topics: topics}
  end

  defp unsubscribe(conn_pid, nil, state), do: unsubscribe(conn_pid, "", state)

  defp unsubscribe(conn_pid, "", state) do
    cleanup_connection(conn_pid, state)
  end

  defp unsubscribe(conn_pid, spec, state) do
    topic =
      case String.split(spec, ":", parts: 2) do
        [mod] -> {:module, mod}
        [mod, param] -> {:param, mod, param}
      end

    subs = Map.update(state.subscriptions, conn_pid, MapSet.new(), &MapSet.delete(&1, topic))
    topics = Map.update(state.topics, topic, MapSet.new(), &MapSet.delete(&1, conn_pid))
    %{state | subscriptions: subs, topics: topics}
  end

  defp cleanup_connection(conn_pid, state) do
    topics_to_remove = Map.get(state.subscriptions, conn_pid, MapSet.new())

    topics =
      Enum.reduce(topics_to_remove, state.topics, fn topic, acc ->
        Map.update(acc, topic, MapSet.new(), &MapSet.delete(&1, conn_pid))
      end)

    subs = Map.delete(state.subscriptions, conn_pid)
    %{state | subscriptions: subs, topics: topics}
  end

  defp get_subscribers(state, mod_name, param_name) do
    all_pids = Map.get(state.topics, :all, MapSet.new())
    mod_pids = Map.get(state.topics, {:module, mod_name}, MapSet.new())
    param_pids = Map.get(state.topics, {:param, mod_name, param_name}, MapSet.new())

    all_pids
    |> MapSet.union(mod_pids)
    |> MapSet.union(param_pids)
  end

  defp send_current_values(conn_pid, spec, state) do
    mod_filter =
      case spec do
        nil -> nil
        "" -> nil
        s ->
          case String.split(s, ":", parts: 2) do
            [mod] -> mod
            [mod, _param] -> mod
          end
      end

    mods_to_send =
      if mod_filter do
        Map.take(state.modules, [mod_filter])
      else
        state.modules
      end

    Enum.each(mods_to_send, fn {mod_name, _mod} ->
      values = ModServer.current_values(state.node_name, mod_name)

      case values do
        list when is_list(list) ->
          Enum.each(list, fn {param_name, value, timestamp, error} ->
            qualifiers = build_qualifiers(timestamp, error)
            msg = {"update", "#{mod_name}:#{param_name}", [value, qualifiers]}
            send(conn_pid, {:send_message, msg})
          end)

        _ ->
          :ok
      end
    end)
  end

  # ---- Descriptor building ----

  defp get_or_build_descriptor(%{descriptor: desc} = state) when not is_nil(desc) do
    {desc, state}
  end

  defp get_or_build_descriptor(state) do
    descriptor = build_descriptor(state)
    {descriptor, %{state | descriptor: descriptor}}
  end

  defp build_descriptor(state) do
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

    # Merge node-level custom properties
    Map.merge(base, state.node_properties)
  end

  # ---- Helpers ----

  defp parse_module_param(nil, _default_param) do
    {:error, Errors.protocol_error("Missing specifier")}
  end

  defp parse_module_param(spec, default_param) do
    case String.split(spec, ":", parts: 2) do
      [mod] when default_param != nil ->
        {:ok, mod, default_param}

      [_mod] ->
        {:error, Errors.protocol_error("Specifier '#{spec}' missing parameter name")}

      [mod, param] ->
        {:ok, mod, param}
    end
  end

  defp check_module(mod_name, state) do
    if Map.has_key?(state.modules, mod_name) do
      :ok
    else
      {:error, Errors.no_such_module("Module '#{mod_name}' not found")}
    end
  end

  defp build_response(reply_action, _err_action, spec, {:ok, report}) do
    {reply_action, spec, report}
  end

  defp build_response(_reply_action, err_action, spec, {:error, %Secant.Error{} = err}) do
    error_response(err_action, spec, err)
  end

  defp error_response(action, spec, %Secant.Error{name: name, message: msg}) do
    {"error_#{action}", spec, [name, msg, %{}]}
  end

  defp build_qualifiers(timestamp, nil) do
    %{"t" => timestamp}
  end

  defp build_qualifiers(timestamp, %Secant.Error{name: name, message: msg}) do
    %{"t" => timestamp, "error" => name, "message" => msg}
  end

  defp get_module_param_datatype(state, mod_name, param_name) do
    with {:ok, _mod_module} <- Map.fetch(state.modules, mod_name),
         [{pid, _}] <- Registry.lookup(Secant.Registry, {state.node_name, mod_name}),
         desc <- GenServer.call(pid, :describe),
         {:ok, accessible} <- Map.fetch(desc["accessibles"] || %{}, param_name),
         true <- is_map(accessible) do
      nil
    else
      _ -> nil
    end
  end

  defp now, do: System.os_time(:millisecond) / 1000.0
end
