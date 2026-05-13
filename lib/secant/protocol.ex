defmodule Secant.Protocol do
  @moduledoc """
  Pure functions for SECoP wire-frame parsing and encoding.

  Wire format: `action specifier json_data\\n`
  The specifier and JSON data are optional.
  """

  @type message :: {action :: String.t(), specifier :: String.t() | nil, data :: term()}

  @standard_params ~w(value status target pollinterval ramp setpoint time_to_target
                      mode control_active controlled_by loglevel)

  @standard_commands ~w(stop go hold prepare shutdown reset clear_errors communicate)

  @standard_node_properties ~w(equipment_id description firmware timeout implementor)

  @standard_module_properties ~w(description interface_classes features visibility
                                  group meaning implementation accessibles properties)

  def standard_params, do: @standard_params
  def standard_commands, do: @standard_commands
  def standard_node_properties, do: @standard_node_properties
  def standard_module_properties, do: @standard_module_properties

  @doc """
  Extract the next complete SECoP message from the buffer.
  Returns `{:ok, message, rest}` or `{:more, buffer}` if incomplete.
  """
  def get_next_message(buffer) do
    case :binary.split(buffer, "\n") do
      [_] ->
        {:more, buffer}

      [line, rest] ->
        line = String.trim_trailing(line, "\r")

        case parse_line(line) do
          {:ok, msg} -> {:ok, msg, rest}
          {:error, _} = err -> err
        end
    end
  end

  @doc "Encode a message triple to wire bytes including trailing newline."
  def encode_frame({action, specifier, data}) do
    parts = [action]
    parts = if specifier && specifier != "", do: parts ++ [specifier], else: parts

    parts =
      if data != nil do
        parts ++ [Jason.encode!(data)]
      else
        parts
      end

    IO.iodata_to_binary([Enum.join(parts, " "), "\n"])
  end

  @doc "Parse a specifier string into `{module_name, accessible_name}`."
  def parse_specifier(nil), do: {:ok, nil, nil}
  def parse_specifier(""), do: {:ok, nil, nil}
  def parse_specifier("."), do: {:ok, ".", nil}

  def parse_specifier(spec) do
    case String.split(spec, ":", parts: 2) do
      [mod] -> {:ok, mod, nil}
      [mod, acc] -> {:ok, mod, acc}
    end
  end

  # --- private ---

  defp parse_line("*IDN?"), do: {:ok, {"*IDN?", nil, nil}}

  defp parse_line(line) do
    case String.split(line, " ", parts: 3) do
      [""] ->
        {:error, :empty}

      [action] ->
        {:ok, {action, nil, nil}}

      [action, specifier] ->
        {:ok, {action, specifier, nil}}

      [action, specifier, json_str] ->
        case Jason.decode(json_str) do
          {:ok, data} -> {:ok, {action, specifier, data}}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end
    end
  end
end
