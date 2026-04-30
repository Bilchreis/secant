defmodule Secant.IntegrationTest do
  use ExUnit.Case

  @port 10799
  @timeout 3000

  defmodule TempModule do
    use Secant.Module, interface: :drivable

    defproperty :_manufacturer, "TestCorp"

    defparam :value, %{
      description: "temperature",
      datatype: {:double, min: 0, max: 400, unit: "K"},
      readonly: true,
      default: 300.0
    }

    defparam :target, %{
      description: "target temperature",
      datatype: {:double, min: 0, max: 400, unit: "K"},
      readonly: false,
      default: 300.0
    }

    defcommand :stop, %{description: "Stop ramping", argument: :null, result: :null}

    def init_module(_opts), do: {:ok, %{value: 300.0}}

    def read_value(%{value: v} = state), do: {:ok, v, state}

    def write_target(val, state), do: {:ok, val, Map.put(state, :target, val)}

    def do_stop(_arg, state), do: {:ok, nil, state}
  end

  setup do
    node_opts = [
      equipment_id: "test_node_#{:rand.uniform(10_000)}",
      description: "Integration test node",
      port: @port,
      modules: [{"temp", TempModule}]
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
    assert Map.has_key?(data["modules"], "temp")
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
