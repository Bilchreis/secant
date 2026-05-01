defmodule Secant.Discovery do
  @moduledoc """
  SECoP UDP auto-discovery listener.

  Binds to UDP port 10767, broadcasts a node announcement on startup, and
  replies to `{"SECoP": "discover"}` multicast/broadcast probes with a JSON
  payload describing this node:

      {"SECoP": "node", "port": 10767, "equipment_id": "...",
       "firmware": "...", "description": "..."}

  Added automatically by `Secant.Node` unless `discovery: false` is passed.

  ## Options (passed via `Secant.Node` opts)

  - `discovery: false` — disable discovery entirely
  - `discovery_port: integer` — UDP port to listen/send on (default 10767)
  - `startup_broadcast: false` — do not send a broadcast on startup

  ## Message size limit

  The SECoP spec recommends keeping UDP payloads ≤ 508 bytes so they survive
  most network paths without fragmentation. If the generated message exceeds
  that limit the description is truncated and a warning is logged. If even
  the truncated message is too large discovery is disabled at runtime.
  """

  use GenServer, restart: :permanent

  require Logger

  @default_udp_port 10767
  @max_payload_bytes 508

  # ---- Public API ----

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  # ---- GenServer callbacks ----

  @impl true
  def init(opts) do
    equipment_id = Map.fetch!(opts, :equipment_id)
    description = Map.get(opts, :description, "")
    tcp_port = Map.fetch!(opts, :tcp_port)
    udp_port = Map.get(opts, :discovery_port, @default_udp_port)
    startup_broadcast = Map.get(opts, :startup_broadcast, true)
    firmware = Secant.firmware()

    {enabled, trimmed_description} =
      check_size(equipment_id, description, tcp_port, firmware)

    if not enabled do
      Logger.warning(
        "[Secant.Discovery] equipment_id + firmware exceed the #{@max_payload_bytes}-byte " <>
          "UDP payload limit — discovery disabled for node '#{equipment_id}'"
      )

      {:ok, %{enabled: false}}
    else
      if trimmed_description != description do
        Logger.debug(
          "[Secant.Discovery] description truncated for UDP payload size limit " <>
            "(node '#{equipment_id}')"
        )
      end

      msg = build_message(equipment_id, trimmed_description, tcp_port, firmware)

      case open_socket(udp_port) do
        {:ok, sock} ->
          if startup_broadcast do
            Logger.debug("[Secant.Discovery] Sending startup UDP broadcast (port #{udp_port})")
            broadcast(sock, udp_port, msg)
          end

          {:ok,
           %{
             enabled: true,
             sock: sock,
             msg: msg,
             udp_port: udp_port,
             equipment_id: equipment_id
           }}

        {:error, reason} ->
          Logger.warning(
            "[Secant.Discovery] Could not bind UDP port #{udp_port}: #{inspect(reason)} " <>
              "— discovery disabled for node '#{equipment_id}'"
          )

          {:ok, %{enabled: false}}
      end
    end
  end

  @impl true
  def handle_info({:udp, _sock, sender_ip, sender_port, data}, %{enabled: true} = state) do
    case Jason.decode(data) do
      {:ok, %{"SECoP" => "discover"}} ->
        Logger.debug(
          "[Secant.Discovery] Answering discovery probe from #{format_addr(sender_ip)}:#{sender_port}"
        )

        :gen_udp.send(state.sock, sender_ip, sender_port, state.msg)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info({:udp, _, _, _, _}, state), do: {:noreply, state}

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{enabled: true, sock: sock}) do
    :gen_udp.close(sock)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # ---- Private ----

  defp open_socket(udp_port) do
    socket_opts = [
      :binary,
      {:active, true},
      {:broadcast, true},
      {:reuseaddr, true}
    ]

    # Try SO_REUSEPORT first (Linux/macOS), fall back to just REUSEADDR on error.
    # This allows multiple nodes on the same machine to each bind port 10767.
    reuseport_opts = socket_opts ++ [{:raw, 1, 15, <<1::32-native>>}]

    case :gen_udp.open(udp_port, reuseport_opts) do
      {:ok, sock} -> {:ok, sock}
      {:error, _} -> :gen_udp.open(udp_port, socket_opts)
    end
  end

  defp broadcast(sock, udp_port, msg) do
    :gen_udp.send(sock, {255, 255, 255, 255}, udp_port, msg)
  end

  defp build_message(equipment_id, description, tcp_port, firmware) do
    Jason.encode!(%{
      "SECoP" => "node",
      "port" => tcp_port,
      "equipment_id" => equipment_id,
      "firmware" => firmware,
      "description" => description
    })
  end

  # Returns {enabled :: boolean, trimmed_description :: String.t()}
  defp check_size(equipment_id, description, tcp_port, firmware) do
    # Check with max possible port (5 digits) to get a tight upper bound
    base_msg = build_message(equipment_id, "", tcp_port, firmware)
    base_size = byte_size(base_msg)
    desc_bytes = String.length(description |> :unicode.characters_to_binary(:utf8))

    cond do
      base_size + desc_bytes <= @max_payload_bytes ->
        {true, description}

      base_size > @max_payload_bytes ->
        # Even without description it's too big — disable
        {false, description}

      true ->
        # Truncate description to fit
        available = @max_payload_bytes - base_size
        trimmed = truncate_utf8(description, available)
        {true, trimmed}
    end
  end

  defp truncate_utf8(str, max_bytes) do
    str
    |> :unicode.characters_to_binary(:utf8)
    |> binary_part(0, min(max_bytes, byte_size(:unicode.characters_to_binary(str, :utf8))))
    |> then(fn bin ->
      # Strip any truncated multi-byte codepoint at the tail
      case :unicode.characters_to_binary(bin, :utf8, :utf8) do
        {:incomplete, valid, _} -> valid
        {:error, valid, _} -> valid
        complete -> complete
      end
    end)
    |> to_string()
  end

  defp format_addr({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_addr(addr), do: inspect(addr)
end
