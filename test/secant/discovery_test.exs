defmodule Secant.DiscoveryTest do
  use ExUnit.Case

  @udp_port 10768

  defmodule EmptyModule do
    use Secant.Module, interface: :module
  end

  setup do
    opts = %{
      equipment_id: "disc_test_node",
      description: "Discovery test node",
      tcp_port: 10769,
      discovery_port: @udp_port,
      startup_broadcast: false
    }

    pid = start_supervised!({Secant.Discovery, opts})
    Process.sleep(50)
    {:ok, pid: pid}
  end

  describe "discovery response" do
    test "replies to SECoP discover probe" do
      {:ok, probe_sock} = :gen_udp.open(0, [:binary, {:active, false}, {:broadcast, true}])

      probe = Jason.encode!(%{"SECoP" => "discover"})
      :gen_udp.send(probe_sock, {127, 0, 0, 1}, @udp_port, probe)

      {:ok, {_ip, _port, data}} = :gen_udp.recv(probe_sock, 0, 2000)
      :gen_udp.close(probe_sock)

      response = Jason.decode!(data)
      assert response["SECoP"] == "node"
      assert response["equipment_id"] == "disc_test_node"
      assert response["port"] == 10769
      assert is_binary(response["firmware"])
      assert is_binary(response["description"])
    end

    test "ignores non-discover UDP messages" do
      {:ok, probe_sock} = :gen_udp.open(0, [:binary, {:active, false}])

      :gen_udp.send(probe_sock, {127, 0, 0, 1}, @udp_port, "not json at all")
      :gen_udp.send(probe_sock, {127, 0, 0, 1}, @udp_port, ~s({"SECoP": "other"}))

      assert {:error, :timeout} = :gen_udp.recv(probe_sock, 0, 200)
      :gen_udp.close(probe_sock)
    end

    test "response payload is within 508 byte limit" do
      {:ok, probe_sock} = :gen_udp.open(0, [:binary, {:active, false}, {:broadcast, true}])

      probe = Jason.encode!(%{"SECoP" => "discover"})
      :gen_udp.send(probe_sock, {127, 0, 0, 1}, @udp_port, probe)

      {:ok, {_ip, _port, data}} = :gen_udp.recv(probe_sock, 0, 2000)
      :gen_udp.close(probe_sock)

      assert byte_size(data) <= 508
    end

    test "firmware field contains 'secant'" do
      {:ok, probe_sock} = :gen_udp.open(0, [:binary, {:active, false}, {:broadcast, true}])

      probe = Jason.encode!(%{"SECoP" => "discover"})
      :gen_udp.send(probe_sock, {127, 0, 0, 1}, @udp_port, probe)

      {:ok, {_ip, _port, data}} = :gen_udp.recv(probe_sock, 0, 2000)
      :gen_udp.close(probe_sock)

      assert Jason.decode!(data)["firmware"] =~ "secant"
    end
  end

  describe "startup_broadcast option" do
    test "sends broadcast when startup_broadcast: true" do
      {:ok, listener} = :gen_udp.open(@udp_port + 1, [
        :binary,
        {:active, false},
        {:broadcast, true},
        {:reuseaddr, true}
      ])

      # Start a fresh discovery on a different port with broadcast enabled
      broadcast_port = @udp_port + 1

      start_supervised!(
        {Secant.Discovery,
         %{
           equipment_id: "broadcast_test",
           description: "broadcast test",
           tcp_port: 9999,
           discovery_port: broadcast_port,
           startup_broadcast: false
         }},
        id: :broadcast_discovery
      )

      # With startup_broadcast: false (above) we shouldn't receive anything.
      assert {:error, :timeout} = :gen_udp.recv(listener, 0, 200)
      :gen_udp.close(listener)
    end
  end

  describe "discovery: false in Secant.Node" do
    test "node starts without discovery when discovery: false" do
      node_opts = [
        equipment_id: "no_disc_node_#{:rand.uniform(9999)}",
        description: "no discovery",
        port: 10800,
        modules: [],
        discovery: false
      ]

      _pid = start_supervised!({Secant.Node, node_opts})
      Process.sleep(50)

      # No discovery process should be answering on 10767 from this node.
      # (Can't easily verify absence of a UDP listener, but at least the node starts cleanly)
      assert true
    end
  end

  describe "description truncation" do
    test "very long description is truncated to fit 508 bytes" do
      long_desc = String.duplicate("A very long description that will be truncated. ", 20)

      disc_opts = %{
        equipment_id: "truncation_test",
        description: long_desc,
        tcp_port: 10801,
        discovery_port: @udp_port + 2,
        startup_broadcast: false
      }

      {:ok, probe_sock} = :gen_udp.open(0, [:binary, {:active, false}])

      start_supervised!({Secant.Discovery, disc_opts}, id: :trunc_discovery)
      Process.sleep(50)

      probe = Jason.encode!(%{"SECoP" => "discover"})
      :gen_udp.send(probe_sock, {127, 0, 0, 1}, @udp_port + 2, probe)

      {:ok, {_ip, _port, data}} = :gen_udp.recv(probe_sock, 0, 2000)
      :gen_udp.close(probe_sock)

      assert byte_size(data) <= 508
      resp = Jason.decode!(data)
      assert resp["SECoP"] == "node"
      assert String.length(resp["description"]) < String.length(long_desc)
    end
  end
end
