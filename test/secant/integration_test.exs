defmodule Secant.IntegrationTest do
  use ExUnit.Case

  @port 10799
  @timeout 3000

  defmodule TempModule do
    use Secant.Module.Drivable

    defproperty :_manufacturer, "TestCorp"

    defparam :value, %{
      description: "temperature",
      datatype: double(min: 0, max: 400, unit: "K"),
      readonly: true,
      default: 300.0
    }

    defparam :status, %{
      description: "module status",
      datatype: tuple([enum(%{"DISABLED" => 0, "IDLE" => 100, "WARN" => 200, "BUSY" => 300, "ERROR" => 400}), string()]),
      readonly: true,
      default: [100, ""]
    }

    defparam :target, %{
      description: "target temperature",
      datatype: double(min: 0, max: 400, unit: "K"),
      readonly: false,
      default: 300.0
    }

    defcommand :stop, %{description: "Stop ramping", argument: :null, result: :null}

    def init_module(_opts), do: {:ok, %{value: 300.0}}

    @impl Secant.Module.Drivable
    def read_value(%{value: v} = state), do: {:ok, v, state}

    @impl Secant.Module.Drivable
    def write_target(val, state), do: {:ok, val, Map.put(state, :target, val)}

    @impl Secant.Module.Drivable
    def do_stop(_arg, state), do: {:ok, nil, state}
  end

  defmodule TempModuleBlock do
    use Secant.Module.Drivable

    defproperty :_manufacturer, "TestCorp"

    defparam :value do
      description "temperature"
      datatype double(min: 0, max: 400, unit: "K")
      readonly true
      default 300.0
    end

    defparam :status do
      description "module status"
      datatype tuple([enum(%{"DISABLED" => 0, "IDLE" => 100, "WARN" => 200, "BUSY" => 300, "ERROR" => 400}), string()])
      readonly true
      default [100, ""]
    end

    defparam :target do
      description "target temperature"
      datatype double(min: 0, max: 400, unit: "K")
      readonly false
      default 300.0
    end

    defcommand :stop do
      description "Stop ramping"
      argument null()
      result null()
    end

    def init_module(_opts), do: {:ok, %{value: 300.0}}

    @impl Secant.Module.Drivable
    def read_value(%{value: v} = state), do: {:ok, v, state}

    @impl Secant.Module.Drivable
    def write_target(val, state), do: {:ok, val, Map.put(state, :target, val)}

    @impl Secant.Module.Drivable
    def do_stop(_arg, state), do: {:ok, nil, state}
  end

  defmodule TempModuleStructSpec do
    use Secant.Module.Drivable

    defproperty :_manufacturer, "TestCorp"

    defparam :value, %ParamSpec{
      description: "temperature",
      datatype: double(min: 0, max: 400, unit: "K"),
      readonly: true,
      default: 300.0,
      properties: %{_myproperty: "hello"}
    }

    defparam :status, %ParamSpec{
      description: "module status",
      datatype: tuple([enum(%{"DISABLED" => 0, "IDLE" => 100, "WARN" => 200, "BUSY" => 300, "ERROR" => 400}), string()]),
      readonly: true,
      default: [100, ""]
    }

    defparam :target, %ParamSpec{
      description: "target temperature",
      datatype: double(min: 0, max: 400, unit: "K"),
      readonly: false,
      default: 300.0
    }

    defcommand :stop, %CommandSpec{
      description: "Stop ramping",
      argument: null(),
      result: null()
    }

    def init_module(_opts), do: {:ok, %{value: 300.0}}

    @impl Secant.Module.Drivable
    def read_value(%{value: v} = state), do: {:ok, v, state}

    @impl Secant.Module.Drivable
    def write_target(val, state), do: {:ok, val, Map.put(state, :target, val)}

    @impl Secant.Module.Drivable
    def do_stop(_arg, state), do: {:ok, nil, state}
  end

  setup do
    node_opts = [
      equipment_id: "test_node_#{:rand.uniform(10_000)}",
      description: "Integration test node",
      port: @port,
      modules: [{"temp", TempModule}],
      discovery: false
    ]

    pid = start_supervised!({Secant.Node, node_opts})
    Process.sleep(100)
    {:ok, node_pid: pid}
  end

  defp connect do
    {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", @port, [:binary, active: false, packet: :raw])
    sock
  end

  defp send_msg(sock, msg) do
    :gen_tcp.send(sock, msg <> "\n")
  end

  defp recv_line(sock) do
    recv_until_newline(sock, "")
  end

  defp recv_until_newline(sock, acc) do
    case :gen_tcp.recv(sock, 0, @timeout) do
      {:ok, data} ->
        combined = acc <> data

        case String.split(combined, "\n", parts: 2) do
          [line, _rest] -> line
          [partial] -> recv_until_newline(sock, partial)
        end

      {:error, reason} ->
        raise "TCP recv failed: #{inspect(reason)}"
    end
  end

  defp parse_response(line) do
    line = String.trim(line)

    case String.split(line, " ", parts: 3) do
      [action] -> {action, nil, nil}
      [action, spec] -> {action, spec, nil}
      [action, spec, json] ->
        {:ok, data} = Jason.decode(json)
        {action, spec, data}
    end
  end

  test "identification request" do
    sock = connect()
    send_msg(sock, "*IDN?")
    line = recv_line(sock)
    assert line =~ "ISSE,SECoP"
    :gen_tcp.close(sock)
  end

  test "describe request" do
    sock = connect()
    send_msg(sock, "describe")
    line = recv_line(sock)
    {action, spec, data} = parse_response(line)
    assert action == "describing"
    assert spec == "."
    assert is_map(data)
    assert Map.has_key?(data, "equipment_id")
    assert Map.has_key?(data, "modules")
    temp = data["modules"]["temp"]
    assert Map.has_key?(temp, "accessibles")
    assert Map.has_key?(temp["accessibles"], "value")
    assert temp["_manufacturer"] == "TestCorp"
    refute Map.has_key?(temp, "properties")
    :gen_tcp.close(sock)
  end

  test "read parameter" do
    sock = connect()
    send_msg(sock, "read temp:value")
    line = recv_line(sock)
    {action, spec, data} = parse_response(line)
    assert action == "reply"
    assert spec == "temp:value"
    assert is_list(data)
    [value, qualifiers] = data
    assert is_number(value)
    assert Map.has_key?(qualifiers, "t")
    :gen_tcp.close(sock)
  end

  test "write parameter" do
    sock = connect()
    send_msg(sock, "change temp:target 350.0")
    line = recv_line(sock)
    {action, spec, data} = parse_response(line)
    assert action == "changed"
    assert spec == "temp:target"
    [value, _quals] = data
    assert value == 350.0


    send_msg(sock, "read temp:target")
    line = recv_line(sock)
    {action, spec, data} = parse_response(line)
    assert action == "reply"
    assert spec == "temp:target"
    [value, _quals] = data
    assert value == 350.0



    send_msg(sock, "change temp:target 300.0")
    line = recv_line(sock)
    {action, spec, data} = parse_response(line)
    assert action == "changed"
    assert spec == "temp:target"
    [value, _quals] = data
    assert value == 300.0


    send_msg(sock, "read temp:target")
    line = recv_line(sock)
    {action, spec, data} = parse_response(line)
    assert action == "reply"
    assert spec == "temp:target"
    [value, _quals] = data
    assert value == 300.0
    :gen_tcp.close(sock)
  end

  test "execute command" do
    sock = connect()
    send_msg(sock, "do temp:stop null")
    line = recv_line(sock)
    {action, spec, _data} = parse_response(line)
    assert action == "done"
    assert spec == "temp:stop"
    :gen_tcp.close(sock)
  end

  test "ping pong" do
    sock = connect()
    send_msg(sock, "ping mytoken")
    line = recv_line(sock)
    {action, spec, _data} = parse_response(line)
    assert action == "pong"
    assert spec == "mytoken"
    :gen_tcp.close(sock)
  end

  test "activate and receive initial updates" do
    sock = connect()
    send_msg(sock, "activate")

    # Collect multiple lines — first should be active, then updates
    lines = collect_lines(sock, 5, 500)

    actions = Enum.map(lines, fn l ->
      {action, _, _} = parse_response(l)
      action
    end)

    assert "active" in actions
    assert Enum.any?(actions, &(&1 == "update"))
    :gen_tcp.close(sock)
  end

  test "error on unknown module" do
    sock = connect()
    send_msg(sock, "read badmodule:value")
    line = recv_line(sock)
    {action, _spec, _data} = parse_response(line)
    assert action == "error_read"
    :gen_tcp.close(sock)
  end

  test "error on read-only write" do
    sock = connect()
    send_msg(sock, "change temp:value 100.0")
    line = recv_line(sock)
    {action, _spec, _data} = parse_response(line)
    assert action == "error_change"
    :gen_tcp.close(sock)
  end

  test "block DSL produces same specs as map syntax" do
    map_params   = Map.new(TempModule.__secant_params__())
    block_params = Map.new(TempModuleBlock.__secant_params__())
    assert map_params == block_params

    map_cmds   = Map.new(TempModule.__secant_commands__())
    block_cmds = Map.new(TempModuleBlock.__secant_commands__())
    assert map_cmds == block_cmds
  end

  test "struct spec form produces correct specs" do
    struct_params = Map.new(TempModuleStructSpec.__secant_params__())

    assert %Secant.ParamSpec{
             description: "temperature",
             datatype: %Secant.DataType.Double{min: 0, max: 400, unit: "K"},
             readonly: true,
             default: 300.0
           } = struct_params[:value]

    assert %Secant.ParamSpec{
             description: "target temperature",
             datatype: %Secant.DataType.Double{min: 0, max: 400, unit: "K"},
             readonly: false,
             default: 300.0
           } = struct_params[:target]

    struct_cmds = Map.new(TempModuleStructSpec.__secant_commands__())

    assert %Secant.CommandSpec{
             description: "Stop ramping",
             argument: :null,
             result: :null
           } = struct_cmds[:stop]
  end

  test "custom properties in ParamSpec appear in describe output" do
    node_name = "struct_spec_node_#{:rand.uniform(10_000)}"

    node_opts = [
      equipment_id: node_name,
      description: "struct spec node",
      port: @port + 1,
      modules: [{"temp", TempModuleStructSpec}],
      discovery: false
    ]

    start_supervised!({Secant.Node, node_opts}, id: :struct_spec_node)
    Process.sleep(50)

    {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", @port + 1, [:binary, active: false, packet: :raw])
    :gen_tcp.send(sock, "describe\n")
    line = recv_line(sock)
    :gen_tcp.close(sock)

    {_action, _spec, data} = parse_response(line)
    value_accessible = data["modules"]["temp"]["accessibles"]["value"]
    assert value_accessible["_myproperty"] == "hello"
    refute Map.has_key?(value_accessible, "properties")
  end

  test "struct spec form semantic fields match map syntax" do
    map_params    = Map.new(TempModule.__secant_params__())
    struct_params = Map.new(TempModuleStructSpec.__secant_params__())

    for name <- [:value, :status, :target] do
      assert Map.take(map_params[name], [:description, :datatype, :readonly, :default]) ==
               Map.take(struct_params[name], [:description, :datatype, :readonly, :default])
    end

    map_cmds    = Map.new(TempModule.__secant_commands__())
    struct_cmds = Map.new(TempModuleStructSpec.__secant_commands__())

    assert Map.take(map_cmds[:stop], [:description, :argument, :result]) ==
             Map.take(struct_cmds[:stop], [:description, :argument, :result])
  end

  # Helpers

  defp collect_lines(sock, count, timeout_ms) do
    Enum.reduce_while(1..count, [], fn _i, acc ->
      case :gen_tcp.recv(sock, 0, timeout_ms) do
        {:ok, data} ->
          new_lines =
            data
            |> String.split("\n", trim: true)
            |> Enum.filter(&(String.trim(&1) != ""))

          {:cont, acc ++ new_lines}

        {:error, :timeout} ->
          {:halt, acc}

        {:error, _reason} ->
          {:halt, acc}
      end
    end)
  end
end
