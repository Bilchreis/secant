defmodule Secant.Module.Server do
  @moduledoc "GenServer backing a single SECoP module instance."

  use GenServer

  alias Secant.{DataType, Errors}
  alias Secant.Module.State

  # ---- Public API ----

  def start_link(%{name: mod_name, node_name: node_name} = args) do
    via = {:via, Registry, {Secant.Registry, {node_name, mod_name}}}
    GenServer.start_link(__MODULE__, args, name: via)
  end

  def read(node_name, mod_name, param_name) do
    call(node_name, mod_name, {:read, param_name})
  end

  def write(node_name, mod_name, param_name, value) do
    call(node_name, mod_name, {:write, param_name, value})
  end

  def execute(node_name, mod_name, cmd_name, argument) do
    call(node_name, mod_name, {:do, cmd_name, argument})
  end

  def describe(node_name, mod_name) do
    call(node_name, mod_name, :describe)
  end

  def current_values(node_name, mod_name) do
    call(node_name, mod_name, :current_values)
  end

  defp call(node_name, mod_name, msg) do
    case Registry.lookup(Secant.Registry, {node_name, mod_name}) do
      [{pid, _}] -> GenServer.call(pid, msg)
      [] -> {:error, Errors.no_such_module("Module '#{mod_name}' not found")}
    end
  end

  # ---- GenServer callbacks ----

  @impl true
  def init(%{name: mod_name, module: mod, node_name: node_name, opts: opts}) do
    runtime_properties =
      opts
      |> Keyword.get(:properties, [])
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    description_override = Keyword.get(opts, :description)
    param_defaults = Keyword.get(opts, :param_defaults, [])
    init_opts = Keyword.drop(opts, [:properties, :param_defaults, :description])

    param_specs = build_param_specs(mod)
    command_specs = build_command_specs(mod)

    params_cache =
      Enum.reduce(param_defaults, build_initial_cache(param_specs), fn {k, v}, acc ->
        Map.update(acc, k, %{value: v, timestamp: 0.0, error: nil}, &%{&1 | value: v})
      end)

    user_state =
      if function_exported?(mod, :init_module, 1) do
        case mod.init_module(init_opts) do
          {:ok, s} -> s
          _ -> %{}
        end
      else
        %{}
      end

    description =
      if is_binary(description_override) and description_override != "" do
        description_override
      else
        if function_exported?(mod, :__secant_description__, 0),
          do: mod.__secant_description__(),
          else: ""
      end

    poll_interval_ms =
      case get_in(param_specs, [:pollinterval, :default]) do
        v when is_number(v) -> round(v * 1000)
        _ -> 5000
      end

    state = %State{
      name: mod_name,
      module: mod,
      node_name: node_name,
      params: params_cache,
      param_specs: param_specs,
      command_specs: command_specs,
      interface_classes: mod.__secant_interface_classes__(),
      description: description,
      poll_interval_ms: poll_interval_ms,
      user_state: user_state,
      runtime_properties: runtime_properties
    }

    timer_ref = Process.send_after(self(), :poll, poll_interval_ms)
    {:ok, %{state | poll_timer_ref: timer_ref}}
  end

  @impl true
  def handle_call({:read, param_name}, _from, state) do
    param_atom = atomize(param_name)

    case Map.fetch(state.param_specs, param_atom) do
      :error ->
        {:reply, {:error, Errors.no_such_parameter("Parameter '#{param_name}' not found")}, state}

      {:ok, spec} ->
        {result, new_state} = do_read(param_atom, spec, state)
        {:reply, result, new_state}
    end
  end

  @impl true
  def handle_call({:write, param_name, raw_value}, _from, state) do
    param_atom = atomize(param_name)

    case Map.fetch(state.param_specs, param_atom) do
      :error ->
        {:reply, {:error, Errors.no_such_parameter("Parameter '#{param_name}' not found")}, state}

      {:ok, %{readonly: true}} ->
        {:reply, {:error, Errors.read_only("Parameter '#{param_name}' is read-only")}, state}

      {:ok, spec} ->
        case DataType.decode_value(raw_value, spec.datatype) do
          {:error, _} = err ->
            {:reply, err, state}

          {:ok, value} ->
            write_fn = :"write_#{param_atom}"

            {result, new_state} =
              if function_exported?(state.module, write_fn, 2) do
                case apply(state.module, write_fn, [value, state.user_state]) do
                  {:ok, written_val, new_user_state} ->
                    ns = update_cache(state, param_atom, written_val, nil)
                    ns = %{ns | user_state: new_user_state}
                    broadcast_update(ns, param_atom)
                    {{:ok, build_report(written_val, spec.datatype)}, ns}

                  {:error, err, new_user_state} ->
                    ns = %{state | user_state: new_user_state}
                    {{:error, err}, ns}
                end
              else
                ns = update_cache(state, param_atom, value, nil)
                broadcast_update(ns, param_atom)
                {{:ok, build_report(value, spec.datatype)}, ns}
              end

            # Update pollinterval if it changed
            new_state =
              if param_atom == :pollinterval do
                new_ms = round(value * 1000)
                if new_state.poll_timer_ref, do: Process.cancel_timer(new_state.poll_timer_ref)
                ref = Process.send_after(self(), :poll, new_ms)
                %{new_state | poll_interval_ms: new_ms, poll_timer_ref: ref}
              else
                new_state
              end

            {:reply, result, new_state}
        end
    end
  end

  @impl true
  def handle_call({:do, cmd_name, argument}, _from, state) do
    cmd_atom = atomize(cmd_name)

    case Map.fetch(state.command_specs, cmd_atom) do
      :error ->
        {:reply, {:error, Errors.no_such_command("Command '#{cmd_name}' not found")}, state}

      {:ok, spec} ->
        do_fn = :"do_#{cmd_atom}"

        {result, new_state} =
          if function_exported?(state.module, do_fn, 2) do
            case apply(state.module, do_fn, [argument, state.user_state]) do
              {:ok, res, new_user_state} ->
                ns = %{state | user_state: new_user_state}
                result_type = Map.get(spec, :result, :null)
                encoded = DataType.encode_value(res, result_type)
                {{:ok, build_plain_report(encoded)}, ns}

              {:error, err, new_user_state} ->
                {{:error, err}, %{state | user_state: new_user_state}}
            end
          else
            # Default: no-op command
            {{:ok, build_plain_report(nil)}, state}
          end

        {:reply, result, new_state}
    end
  end

  @impl true
  def handle_call(:describe, _from, state) do
    descriptor = build_descriptor(state)
    {:reply, descriptor, state}
  end

  @impl true
  def handle_call(:current_values, _from, state) do
    values =
      Enum.map(state.params, fn {param_name, cache} ->
        spec = Map.get(state.param_specs, param_name, %{datatype: %Secant.DataType.String{}})
        encoded = DataType.encode_value(cache.value, spec.datatype)
        {Atom.to_string(param_name), encoded, cache.timestamp, cache.error}
      end)

    {:reply, values, state}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state =
      case state.module.do_poll(state.user_state) do
        {:ok, param_names, new_user_state} ->
          poll_params(%{state | user_state: new_user_state}, param_names)

        {:noreply, new_user_state} ->
          %{state | user_state: new_user_state}
      end

    ref = Process.send_after(self(), :poll, new_state.poll_interval_ms)
    {:noreply, %{new_state | poll_timer_ref: ref}}
  end

  # ---- Private ----

  defp atomize(name) when is_atom(name), do: name
  defp atomize(name) when is_binary(name), do: String.to_existing_atom(name)

  defp poll_params(state, param_names) do
    Enum.reduce(param_names, state, fn param_atom, st ->
      read_fn = :"read_#{param_atom}"

      if function_exported?(st.module, read_fn, 1) do
        case apply(st.module, read_fn, [st.user_state]) do
          {:ok, value, new_user_state} ->
            ns = update_cache(st, param_atom, value, nil)
            ns = %{ns | user_state: new_user_state}
            broadcast_update(ns, param_atom)
            ns

          {:error, err, new_user_state} ->
            old_error = get_in(st.params, [param_atom, :error])

            if err != old_error do
              ns = update_cache_error(st, param_atom, err)
              ns = %{ns | user_state: new_user_state}
              broadcast_update(ns, param_atom)
              ns
            else
              %{st | user_state: new_user_state}
            end
        end
      else
        st
      end
    end)
  end

  defp do_read(param_atom, spec, state) do
    read_fn = :"read_#{param_atom}"

    if function_exported?(state.module, read_fn, 1) do
      case apply(state.module, read_fn, [state.user_state]) do
        {:ok, value, new_user_state} ->
          ns = update_cache(state, param_atom, value, nil)
          ns = %{ns | user_state: new_user_state}
          broadcast_update(ns, param_atom)
          {{:ok, build_report(value, spec.datatype)}, ns}

        {:error, err, new_user_state} ->
          ns = update_cache_error(state, param_atom, err)
          ns = %{ns | user_state: new_user_state}
          {{:error, err}, ns}
      end
    else
      # Return cached value
      case Map.get(state.params, param_atom) do
        %{error: %Secant.Error{} = err} ->
          {{:error, err}, state}

        %{value: value} ->
          {{:ok, build_report(value, spec.datatype)}, state}

        nil ->
          {{:error, Errors.internal_error("No cached value for #{param_atom}")}, state}
      end
    end
  end

  defp update_cache(state, param_atom, value, error) do
    ts = now()
    cache = %{value: value, timestamp: ts, error: error}
    %{state | params: Map.put(state.params, param_atom, cache)}
  end

  defp update_cache_error(state, param_atom, error) do
    old = Map.get(state.params, param_atom, %{value: nil, timestamp: now()})
    cache = %{old | error: error, timestamp: now()}
    %{state | params: Map.put(state.params, param_atom, cache)}
  end

  defp broadcast_update(state, param_atom) do
    cache = Map.get(state.params, param_atom)
    spec = Map.get(state.param_specs, param_atom, %{datatype: %Secant.DataType.String{}})
    encoded = DataType.encode_value(cache.value, spec.datatype)
    qualifiers = build_qualifiers(cache.timestamp, cache.error)

    Registry.dispatch(Secant.PubSub, state.node_name, fn entries ->
      for {pid, _} <- entries do
        send(pid, {:secant_update, state.name, Atom.to_string(param_atom), encoded, qualifiers})
      end
    end)
  end

  defp build_qualifiers(ts, nil), do: %{"t" => ts}

  defp build_qualifiers(ts, %Secant.Error{name: n, message: m}),
    do: %{"t" => ts, "error" => n, "message" => m}

  defp build_report(value, datatype) do
    encoded = DataType.encode_value(value, datatype)
    [encoded, %{"t" => now()}]
  end

  defp build_plain_report(value) do
    [value, %{"t" => now()}]
  end

  defp now do
    System.os_time(:millisecond) / 1000.0
  end

  defp build_param_specs(mod) do
    mod.__secant_params__()
    |> Map.new(fn {name, spec} ->
      full_spec = Map.merge(%{readonly: true, default: nil}, atomize_map(spec))
      {name, full_spec}
    end)
  end

  defp build_command_specs(mod) do
    mod.__secant_commands__()
    |> Map.new(fn {name, spec} ->
      {name, atomize_map(spec)}
    end)
  end

  defp atomize_map(map) when is_struct(map), do: Map.from_struct(map)

  defp atomize_map(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {if(is_atom(k), do: k, else: String.to_atom(k)), v} end)
  end

  defp build_initial_cache(param_specs) do
    Map.new(param_specs, fn {name, spec} ->
      default = Map.get(spec, :default)
      {name, %{value: default, timestamp: 0.0, error: nil}}
    end)
  end

  defp build_descriptor(state) do
    mod = state.module

    accessibles =
      state.param_specs
      |> Enum.map(fn {name, spec} ->
        accessible = %{
          "description" => Map.get(spec, :description, ""),
          "datainfo" => DataType.to_datainfo(spec.datatype),
          "readonly" => Map.get(spec, :readonly, true)
        }

        accessible =
          case Map.get(spec, :properties) do
            nil -> accessible
            props -> Map.merge(accessible, encode_properties(props))
          end

        {Atom.to_string(name), accessible}
      end)

    commands =
      state.command_specs
      |> Enum.map(fn {name, spec} ->
        arg_type = Map.get(spec, :argument, :null)
        res_type = Map.get(spec, :result, :null)

        accessible = %{
          "description" => Map.get(spec, :description, ""),
          "datainfo" => %{
            "type" => "command",
            "argument" => DataType.to_datainfo(arg_type),
            "result" => DataType.to_datainfo(res_type)
          }
        }

        accessible =
          case Map.get(spec, :properties) do
            nil -> accessible
            props -> Map.merge(accessible, encode_properties(props))
          end

        {Atom.to_string(name), accessible}
      end)

    all_accessibles = Map.new(accessibles ++ commands)

    compile_time_properties =
      if function_exported?(mod, :__secant_properties__, 0) do
        mod.__secant_properties__()
        |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      else
        %{}
      end

    module_properties = Map.merge(compile_time_properties, state.runtime_properties)

    features =
      if function_exported?(mod, :__secant_features__, 0),
        do: mod.__secant_features__(),
        else: []

    base = %{
      "description" => state.description,
      "interface_classes" => state.interface_classes,
      "implementation" => mod.__secant_implementation__(),
      "features" => features,
      "accessibles" => all_accessibles
    }

    Map.merge(module_properties, base)
  end

  defp encode_properties(props) when is_map(props) do
    Map.new(props, fn {k, v} -> {to_string(k), v} end)
  end

  defp encode_properties(props) when is_list(props) do
    Map.new(props, fn {k, v} -> {to_string(k), v} end)
  end
end
