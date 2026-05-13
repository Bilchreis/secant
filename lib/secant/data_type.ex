defmodule Secant.DataType.Double do
  @moduledoc "SECoP double floating point type."
  @type t :: %__MODULE__{
          min: number() | nil,
          max: number() | nil,
          unit: String.t() | nil,
          fmtstr: String.t() | nil,
          absolute_resolution: number() | nil,
          relative_resolution: number() | nil
        }
  defstruct [:min, :max, :unit, :fmtstr, :absolute_resolution, :relative_resolution]
end

defmodule Secant.DataType.Int do
  @moduledoc "SECoP integer type."
  @type t :: %__MODULE__{min: integer() | nil, max: integer() | nil}
  defstruct [:min, :max]
end

defmodule Secant.DataType.String do
  @moduledoc "SECoP string type."
  @type t :: %__MODULE__{maxchars: non_neg_integer() | nil, minchars: non_neg_integer() | nil}
  defstruct [:maxchars, :minchars]
end

defmodule Secant.DataType.Bool do
  @moduledoc "SECoP boolean type."
  @type t :: %__MODULE__{}
  defstruct []
end

defmodule Secant.DataType.Enum do
  @moduledoc "SECoP enum type."
  @enforce_keys [:members]
  @type t :: %__MODULE__{members: %{String.t() => integer()}}
  defstruct [:members]
end

defmodule Secant.DataType.Tuple do
  @moduledoc "SECoP tuple type."
  @enforce_keys [:types]
  @type t :: %__MODULE__{types: [Secant.DataType.t()]}
  defstruct [:types]
end

defmodule Secant.DataType.Array do
  @moduledoc "SECoP array type."
  @enforce_keys [:type]
  @type t :: %__MODULE__{
          type: Secant.DataType.t(),
          minlen: non_neg_integer() | nil,
          maxlen: non_neg_integer() | nil
        }
  defstruct [:type, :minlen, :maxlen]
end

defmodule Secant.DataType.Struct do
  @moduledoc "SECoP struct type."
  @enforce_keys [:fields]
  @type t :: %__MODULE__{fields: %{atom() => Secant.DataType.t()}}
  defstruct [:fields]
end

defmodule Secant.DataType.Blob do
  @moduledoc "SECoP binary large object type."
  @type t :: %__MODULE__{maxbytes: non_neg_integer() | nil, minbytes: non_neg_integer() | nil}
  defstruct [:maxbytes, :minbytes]
end

defmodule Secant.DataType do
  @moduledoc """
  SECoP data type definitions, validation, and JSON datainfo encoding.

  Types are represented as structs:
    %Double{}     fields: min, max, unit, fmtstr, absolute_resolution, relative_resolution
    %Int{}        fields: min, max
    %String{}     fields: maxchars, minchars
    %Bool{}
    %Enum{}       fields: members (%{"NAME" => integer})
    %Tuple{}      fields: types (list of type structs)
    %Array{}      fields: type, minlen, maxlen
    %Struct{}     fields: fields (%{atom => type})
    %Blob{}       fields: maxbytes, minbytes
    :null         (atom sentinel)

  All submodule structs live under `Secant.DataType.*`.
  Builder functions (double/1, int/1, etc.) are provided for convenience
  and are auto-imported by `use Secant.Module.*`.
  """

  @type t ::
          Secant.DataType.Double.t()
          | Secant.DataType.Int.t()
          | Secant.DataType.String.t()
          | Secant.DataType.Bool.t()
          | Secant.DataType.Enum.t()
          | Secant.DataType.Tuple.t()
          | Secant.DataType.Array.t()
          | Secant.DataType.Struct.t()
          | Secant.DataType.Blob.t()
          | :null

  alias Secant.Errors
  alias Secant.DataType.{Double, Int, Bool, Tuple, Array, Struct, Blob}
  # Secant.DataType.String and Secant.DataType.Enum are used by full name
  # to avoid shadowing Elixir.String and Elixir.Enum within this module.

  @status_type %Tuple{
    types: [
      %Secant.DataType.Enum{
        members: %{"DISABLED" => 0, "IDLE" => 100, "WARN" => 200, "BUSY" => 300, "ERROR" => 400}
      },
      %Secant.DataType.String{}
    ]
  }

  def status_type, do: @status_type

  @doc "Convert internal type struct to the SECoP datainfo JSON map."
  def to_datainfo(:null), do: %{"type" => "null"}

  def to_datainfo(%Double{} = d) do
    Enum.reduce(
      [:min, :max, :unit, :fmtstr, :absolute_resolution, :relative_resolution],
      %{"type" => "double"},
      fn k, acc ->
        case Map.get(d, k) do
          nil -> acc
          v -> Map.put(acc, Atom.to_string(k), v)
        end
      end
    )
  end

  def to_datainfo(%Int{} = d) do
    Enum.reduce([:min, :max], %{"type" => "int"}, fn k, acc ->
      case Map.get(d, k) do
        nil -> acc
        v -> Map.put(acc, Atom.to_string(k), v)
      end
    end)
  end

  def to_datainfo(%Secant.DataType.String{} = d) do
    Enum.reduce([:maxchars, :minchars], %{"type" => "string"}, fn k, acc ->
      case Map.get(d, k) do
        nil -> acc
        v -> Map.put(acc, Atom.to_string(k), v)
      end
    end)
  end

  def to_datainfo(%Bool{}), do: %{"type" => "bool"}

  def to_datainfo(%Secant.DataType.Enum{members: members}) when is_map(members) do
    %{"type" => "enum", "members" => members}
  end

  def to_datainfo(%Tuple{types: types}) when is_list(types) do
    %{"type" => "tuple", "members" => Enum.map(types, &to_datainfo/1)}
  end

  def to_datainfo(%Array{type: type, minlen: minlen, maxlen: maxlen}) do
    base = %{"type" => "array", "members" => to_datainfo(type)}
    base = if minlen != nil, do: Map.put(base, "minlen", minlen), else: base
    if maxlen != nil, do: Map.put(base, "maxlen", maxlen), else: base
  end

  def to_datainfo(%Struct{fields: fields}) when is_map(fields) do
    encoded = Map.new(fields, fn {k, v} -> {to_string(k), to_datainfo(v)} end)
    %{"type" => "struct", "members" => encoded}
  end

  def to_datainfo(%Blob{} = d) do
    Enum.reduce([:maxbytes, :minbytes], %{"type" => "blob"}, fn k, acc ->
      case Map.get(d, k) do
        nil -> acc
        v -> Map.put(acc, Atom.to_string(k), v)
      end
    end)
  end

  @doc "Validate and coerce a value against the given type."
  def validate(nil, :null), do: {:ok, nil}
  def validate(_val, :null), do: {:error, Errors.wrong_type("expected null")}

  def validate(v, %Double{min: min, max: max}) when is_number(v) do
    v = v * 1.0
    cond do
      min != nil and v < min -> {:error, Errors.range_error("value #{v} below min #{min}")}
      max != nil and v > max -> {:error, Errors.range_error("value #{v} above max #{max}")}
      true -> {:ok, v}
    end
  end
  def validate(_, %Double{}), do: {:error, Errors.wrong_type("expected a number")}

  def validate(v, %Int{min: min, max: max}) when is_integer(v) do
    cond do
      min != nil and v < min -> {:error, Errors.range_error("value #{v} below min #{min}")}
      max != nil and v > max -> {:error, Errors.range_error("value #{v} above max #{max}")}
      true -> {:ok, v}
    end
  end
  def validate(v, %Int{} = type) when is_float(v) do
    i = trunc(v)
    if i == v, do: validate(i, type),
               else: {:error, Errors.wrong_type("expected integer")}
  end
  def validate(_, %Int{}), do: {:error, Errors.wrong_type("expected integer")}

  def validate(v, %Secant.DataType.String{maxchars: maxchars}) when is_binary(v) do
    if maxchars && String.length(v) > maxchars do
      {:error, Errors.range_error("string exceeds maxchars #{maxchars}")}
    else
      {:ok, v}
    end
  end
  def validate(_, %Secant.DataType.String{}), do: {:error, Errors.wrong_type("expected string")}

  def validate(v, %Bool{}) when is_boolean(v), do: {:ok, v}
  def validate(1, %Bool{}), do: {:ok, true}
  def validate(0, %Bool{}), do: {:ok, false}
  def validate(_, %Bool{}), do: {:error, Errors.wrong_type("expected boolean")}

  def validate(v, %Secant.DataType.Enum{members: members}) when is_integer(v) do
    if v in Map.values(members) do
      {:ok, v}
    else
      {:error, Errors.range_error("enum value #{v} not in #{inspect(Map.values(members))}")}
    end
  end
  def validate(v, %Secant.DataType.Enum{members: members}) when is_binary(v) do
    case Map.fetch(members, v) do
      {:ok, int_val} -> {:ok, int_val}
      :error -> {:error, Errors.bad_value("unknown enum member '#{v}'")}
    end
  end
  def validate(_, %Secant.DataType.Enum{}), do: {:error, Errors.wrong_type("expected integer or string")}

  def validate(v, %Tuple{types: types}) when is_list(v) do
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
  def validate(_, %Tuple{}), do: {:error, Errors.wrong_type("expected list/tuple")}

  def validate(v, %Array{type: type, minlen: minlen, maxlen: maxlen}) when is_list(v) do
    min = minlen || 0
    cond do
      length(v) < min ->
        {:error, Errors.range_error("array length #{length(v)} below minlen #{min}")}
      maxlen != nil and length(v) > maxlen ->
        {:error, Errors.range_error("array length #{length(v)} exceeds maxlen #{maxlen}")}
      true ->
        Enum.reduce_while(v, {:ok, []}, fn elem, {:ok, acc} ->
          case validate(elem, type) do
            {:ok, coerced} -> {:cont, {:ok, acc ++ [coerced]}}
            err -> {:halt, err}
          end
        end)
    end
  end
  def validate(_, %Array{}), do: {:error, Errors.wrong_type("expected list")}

  def validate(v, %Struct{fields: member_types}) when is_map(v) do
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
  def validate(_, %Struct{}), do: {:error, Errors.wrong_type("expected map")}

  def validate(v, %Blob{maxbytes: maxbytes}) when is_binary(v) do
    if maxbytes && byte_size(v) > maxbytes do
      {:error, Errors.range_error("blob exceeds maxbytes #{maxbytes}")}
    else
      {:ok, v}
    end
  end
  def validate(_, %Blob{}), do: {:error, Errors.wrong_type("expected binary/blob")}

  @doc "Convert internal Elixir value to JSON-serialisable form."
  def encode_value(nil, :null), do: nil
  def encode_value(v, %Double{}), do: v * 1.0
  def encode_value(v, %Int{}), do: v
  def encode_value(v, %Secant.DataType.String{}), do: v
  def encode_value(v, %Bool{}), do: v
  def encode_value(v, %Secant.DataType.Enum{}) when is_integer(v), do: v
  def encode_value(v, %Tuple{types: types}) when is_list(v) do
    Enum.zip(v, types) |> Enum.map(fn {elem, t} -> encode_value(elem, t) end)
  end
  def encode_value(v, %Array{type: type}) when is_list(v) do
    Enum.map(v, &encode_value(&1, type))
  end
  def encode_value(v, %Struct{fields: member_types}) when is_map(v) do
    Map.new(v, fn {k, val} ->
      key = to_string(k)
      type = Map.get(member_types, String.to_existing_atom(key), %Secant.DataType.String{})
      {key, encode_value(val, type)}
    end)
  end
  def encode_value(v, %Blob{}), do: Base.encode64(v)
  def encode_value(v, _), do: v

  @doc "Convert incoming JSON value to internal Elixir form."
  def decode_value(v, type), do: validate(v, type)

  # --- datatype builder functions ---

  @doc "Build a `Double` datatype. Options: `min`, `max`, `unit`, `fmtstr`, `absolute_resolution`, `relative_resolution`."
  @spec double(keyword()) :: Secant.DataType.Double.t()
  def double(opts \\ []) do
    %Double{
      min: Keyword.get(opts, :min),
      max: Keyword.get(opts, :max),
      unit: Keyword.get(opts, :unit),
      fmtstr: Keyword.get(opts, :fmtstr),
      absolute_resolution: Keyword.get(opts, :absolute_resolution),
      relative_resolution: Keyword.get(opts, :relative_resolution)
    }
  end

  @doc "Build an `Int` datatype. Options: `min`, `max`."
  @spec int(keyword()) :: Secant.DataType.Int.t()
  def int(opts \\ []) do
    %Int{
      min: Keyword.get(opts, :min),
      max: Keyword.get(opts, :max)
    }
  end

  @doc "Build a `String` datatype. Options: `maxchars`, `minchars`."
  @spec string(keyword()) :: Secant.DataType.String.t()
  def string(opts \\ []) do
    %Secant.DataType.String{
      maxchars: Keyword.get(opts, :maxchars),
      minchars: Keyword.get(opts, :minchars)
    }
  end

  @doc "Build a `Bool` datatype."
  @spec bool() :: Secant.DataType.Bool.t()
  def bool(), do: %Bool{}

  @doc "Build an `Enum` datatype. `members` is a `%{\"NAME\" => integer}` map."
  @spec enum(map()) :: Secant.DataType.Enum.t()
  def enum(members), do: %Secant.DataType.Enum{members: members}

  @doc "Build a `Tuple` datatype from a list of element types."
  @spec tuple([term()]) :: Secant.DataType.Tuple.t()
  def tuple(types), do: %Tuple{types: types}

  @doc "Build an `Array` datatype. Options: `minlen`, `maxlen`."
  @spec array(term(), keyword()) :: Secant.DataType.Array.t()
  def array(type, opts \\ []) do
    %Array{
      type: type,
      minlen: Keyword.get(opts, :minlen),
      maxlen: Keyword.get(opts, :maxlen)
    }
  end

  @doc "Build a `Struct` datatype from a `%{atom => type}` fields map."
  @spec struct(map()) :: Secant.DataType.Struct.t()
  def struct(fields), do: %Struct{fields: fields}

  @doc "Build a `Blob` datatype. Options: `maxbytes`, `minbytes`."
  @spec blob(keyword()) :: Secant.DataType.Blob.t()
  def blob(opts \\ []) do
    %Blob{
      maxbytes: Keyword.get(opts, :maxbytes),
      minbytes: Keyword.get(opts, :minbytes)
    }
  end

  @doc "Return the `:null` type sentinel."
  @spec null() :: :null
  def null(), do: :null
end
