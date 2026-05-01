defmodule Secant.DataType do
  @moduledoc """
  SECoP data type definitions, validation, and JSON datainfo encoding.

  Internal type representations (tagged tuples):
    {:double, opts}         opts: min, max, unit, fmtstr
    {:int, opts}            opts: min, max
    {:string, opts}         opts: maxchars, minchars
    {:bool}
    {:enum, members}        members: %{"NAME" => integer}
    {:tuple, [types]}
    {:array, type, opts}    opts: minlen, maxlen
    {:struct, %{key => type}}
    {:blob, opts}           opts: maxbytes, minbytes
    :null
  """

  alias Secant.Errors

  @status_type {:tuple,
    [
      {:enum, %{"DISABLED" => 0, "IDLE" => 100, "WARN" => 200, "BUSY" => 300, "ERROR" => 400}},
      {:string, []}
    ]}

  def status_type, do: @status_type

  @doc "Convert internal type spec to the SECoP datainfo JSON map."
  def to_datainfo(:null), do: %{"type" => "null"}

  def to_datainfo({:double, opts}) do
    base = %{"type" => "double"}
    opts
    |> Keyword.take([:min, :max, :unit, :fmtstr, :absolute_resolution, :relative_resolution])
    |> Enum.reduce(base, fn {k, v}, acc -> Map.put(acc, Atom.to_string(k), v) end)
  end

  def to_datainfo({:int, opts}) do
    base = %{"type" => "int"}
    opts
    |> Keyword.take([:min, :max])
    |> Enum.reduce(base, fn {k, v}, acc -> Map.put(acc, Atom.to_string(k), v) end)
  end

  def to_datainfo({:string, opts}) do
    base = %{"type" => "string"}
    opts
    |> Keyword.take([:maxchars, :minchars])
    |> Enum.reduce(base, fn {k, v}, acc -> Map.put(acc, Atom.to_string(k), v) end)
  end

  def to_datainfo({:bool}), do: %{"type" => "bool"}

  def to_datainfo({:enum, members}) when is_map(members) do
    %{"type" => "enum", "members" => members}
  end

  def to_datainfo({:tuple, types}) when is_list(types) do
    %{"type" => "tuple", "members" => Enum.map(types, &to_datainfo/1)}
  end

  def to_datainfo({:array, type, opts}) do
    base = %{"type" => "array", "members" => to_datainfo(type)}
    opts
    |> Keyword.take([:minlen, :maxlen])
    |> Enum.reduce(base, fn {k, v}, acc -> Map.put(acc, Atom.to_string(k), v) end)
  end

  def to_datainfo({:struct, members}) when is_map(members) do
    encoded = Map.new(members, fn {k, v} -> {to_string(k), to_datainfo(v)} end)
    %{"type" => "struct", "members" => encoded}
  end

  def to_datainfo({:blob, opts}) do
    base = %{"type" => "blob"}
    opts
    |> Keyword.take([:maxbytes, :minbytes])
    |> Enum.reduce(base, fn {k, v}, acc -> Map.put(acc, Atom.to_string(k), v) end)
  end

  @doc "Validate and coerce a value against the given type."
  def validate(nil, :null), do: {:ok, nil}
  def validate(_val, :null), do: {:error, Errors.wrong_type("expected null")}

  def validate(v, {:double, opts}) when is_number(v) do
    v = v / 1  # ensure float
    case check_range(v, opts) do
      :ok -> {:ok, v * 1.0}
      err -> err
    end
  end
  def validate(_, {:double, _}), do: {:error, Errors.wrong_type("expected a number")}

  def validate(v, {:int, opts}) when is_integer(v) do
    case check_range(v, opts) do
      :ok -> {:ok, v}
      err -> err
    end
  end
  def validate(v, {:int, opts}) when is_float(v) do
    i = trunc(v)
    if i == v, do: validate(i, {:int, opts}),
               else: {:error, Errors.wrong_type("expected integer")}
  end
  def validate(_, {:int, _}), do: {:error, Errors.wrong_type("expected integer")}

  def validate(v, {:string, opts}) when is_binary(v) do
    max = Keyword.get(opts, :maxchars)
    if max && String.length(v) > max do
      {:error, Errors.range_error("string exceeds maxchars #{max}")}
    else
      {:ok, v}
    end
  end
  def validate(_, {:string, _}), do: {:error, Errors.wrong_type("expected string")}

  def validate(v, {:bool}) when is_boolean(v), do: {:ok, v}
  def validate(1, {:bool}), do: {:ok, true}
  def validate(0, {:bool}), do: {:ok, false}
  def validate(_, {:bool}), do: {:error, Errors.wrong_type("expected boolean")}

  def validate(v, {:enum, members}) when is_integer(v) do
    if v in Map.values(members) do
      {:ok, v}
    else
      {:error, Errors.range_error("enum value #{v} not in #{inspect(Map.values(members))}")}
    end
  end
  def validate(v, {:enum, members}) when is_binary(v) do
    case Map.fetch(members, v) do
      {:ok, int_val} -> {:ok, int_val}
      :error -> {:error, Errors.bad_value("unknown enum member '#{v}'")}
    end
  end
  def validate(_, {:enum, _}), do: {:error, Errors.wrong_type("expected integer or string")}

  def validate(v, {:tuple, types}) when is_list(v) do
    if length(v) != length(types) do
      {:error, Errors.wrong_type("tuple length mismatch: got #{length(v)}, expected #{length(types)}")}
    else
      v
      |> Enum.zip(types)
      |> Enum.reduce_while({:ok, []}, fn {elem, type}, {:ok, acc} ->
        case validate(elem, type) do
          {:ok, coerced} -> {:cont, {:ok, acc ++ [coerced]}}
          err -> {:halt, err}
        end
      end)
    end
  end
  def validate(_, {:tuple, _}), do: {:error, Errors.wrong_type("expected list/tuple")}

  def validate(v, {:array, type, opts}) when is_list(v) do
    min = Keyword.get(opts, :minlen, 0)
    max = Keyword.get(opts, :maxlen)
    cond do
      length(v) < min ->
        {:error, Errors.range_error("array length #{length(v)} below minlen #{min}")}
      max && length(v) > max ->
        {:error, Errors.range_error("array length #{length(v)} exceeds maxlen #{max}")}
      true ->
        Enum.reduce_while(v, {:ok, []}, fn elem, {:ok, acc} ->
          case validate(elem, type) do
            {:ok, coerced} -> {:cont, {:ok, acc ++ [coerced]}}
            err -> {:halt, err}
          end
        end)
    end
  end
  def validate(_, {:array, _, _}), do: {:error, Errors.wrong_type("expected list")}

  def validate(v, {:struct, member_types}) when is_map(v) do
    Enum.reduce_while(member_types, {:ok, %{}}, fn {k, type}, {:ok, acc} ->
      key_str = to_string(k)
      case Map.fetch(v, key_str) do
        {:ok, elem} ->
          case validate(elem, type) do
            {:ok, coerced} -> {:cont, {:ok, Map.put(acc, key_str, coerced)}}
            err -> {:halt, err}
          end
        :error ->
          {:halt, {:error, Errors.bad_value("struct missing key '#{key_str}'")}}
      end
    end)
  end
  def validate(_, {:struct, _}), do: {:error, Errors.wrong_type("expected map")}

  def validate(v, {:blob, opts}) when is_binary(v) do
    max = Keyword.get(opts, :maxbytes)
    if max && byte_size(v) > max do
      {:error, Errors.range_error("blob exceeds maxbytes #{max}")}
    else
      {:ok, v}
    end
  end
  def validate(_, {:blob, _}), do: {:error, Errors.wrong_type("expected binary/blob")}

  @doc "Convert internal Elixir value to JSON-serialisable form."
  def encode_value(nil, :null), do: nil
  def encode_value(v, {:double, _}), do: v * 1.0
  def encode_value(v, {:int, _}), do: v
  def encode_value(v, {:string, _}), do: v
  def encode_value(v, {:bool}), do: v
  def encode_value(v, {:enum, members}) when is_integer(v) do
    Enum.find_value(members, v, fn {name, val} -> if val == v, do: name end)
  end
  def encode_value(v, {:tuple, types}) when is_list(v) do
    Enum.zip(v, types) |> Enum.map(fn {elem, t} -> encode_value(elem, t) end)
  end
  def encode_value(v, {:array, type, _}) when is_list(v) do
    Enum.map(v, &encode_value(&1, type))
  end
  def encode_value(v, {:struct, member_types}) when is_map(v) do
    Map.new(v, fn {k, val} ->
      key = to_string(k)
      type = Map.get(member_types, String.to_existing_atom(key), {:string, []})
      {key, encode_value(val, type)}
    end)
  end
  def encode_value(v, {:blob, _}), do: Base.encode64(v)
  def encode_value(v, _), do: v

  @doc "Convert incoming JSON value to internal Elixir form."
  def decode_value(v, type), do: validate(v, type)

  # --- private helpers ---

  defp check_range(v, opts) do
    min = Keyword.get(opts, :min)
    max = Keyword.get(opts, :max)
    cond do
      min != nil and v < min -> {:error, Errors.range_error("value #{v} below min #{min}")}
      max != nil and v > max -> {:error, Errors.range_error("value #{v} above max #{max}")}
      true -> :ok
    end
  end
end
