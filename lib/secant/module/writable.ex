defmodule Secant.Module.Writable do
  @moduledoc """
  Interface class behaviour for SECoP Writable modules.

  Requires `value`, `status`, and `target` parameters.

  ## Usage

      defmodule MyApp.Setpoint do
        use Secant.Module.Writable

        defparam :value,  %{description: "...", datatype: {:double, []}, readonly: true}
        defparam :status, %{description: "...", datatype: Secant.DataType.status_type(), readonly: true}
        defparam :target, %{description: "...", datatype: {:double, []}, readonly: false}
      end
  """

  def required_params,   do: [:value, :status, :target]
  def required_commands, do: []
  def class_list,        do: ["Writable", "Readable", "Module"]

  def validate!(mod, params, commands) do
    Secant.Module.Readable.validate!(mod, params, commands)
    param_map = Map.new(params)
    validate_value_target_compatibility!(mod, param_map)
    :ok
  end

  defp validate_value_target_compatibility!(mod, param_map) do
    value_type  = param_map |> Map.get(:value, %{}) |> Map.get(:datatype)
    target_type = param_map |> Map.get(:target, %{}) |> Map.get(:datatype)

    unless type_tag(value_type) == type_tag(target_type) do
      raise CompileError,
        file: "#{mod}",
        description:
          "value and target must have the same datatype. " <>
            "Got value: #{inspect(type_tag(value_type))}, target: #{inspect(type_tag(target_type))}."
    end

    case {value_type, target_type} do
      {%Secant.DataType.Double{min: value_min, max: value_max},
       %Secant.DataType.Double{min: target_min, max: target_max}} ->
        check_range_compat!(mod, value_min, target_min, value_max, target_max)

      {%Secant.DataType.Int{min: value_min, max: value_max},
       %Secant.DataType.Int{min: target_min, max: target_max}} ->
        check_range_compat!(mod, value_min, target_min, value_max, target_max)

      _ ->
        :ok
    end
  end

  defp check_range_compat!(mod, value_min, target_min, value_max, target_max) do
    if not is_nil(value_min) and not is_nil(target_min) and value_min > target_min do
      raise CompileError,
        file: "#{mod}",
        description:
          "value min (#{value_min}) is more restrictive than target min (#{target_min}). " <>
            "value.min must be <= target.min."
    end

    if not is_nil(value_max) and not is_nil(target_max) and value_max < target_max do
      raise CompileError,
        file: "#{mod}",
        description:
          "value max (#{value_max}) is more restrictive than target max (#{target_max}). " <>
            "value.max must be >= target.max."
    end
  end

  defp type_tag(%Secant.DataType.Double{}), do: :double
  defp type_tag(%Secant.DataType.Int{}), do: :int
  defp type_tag(%Secant.DataType.String{}), do: :string
  defp type_tag(%Secant.DataType.Bool{}), do: :bool
  defp type_tag(%Secant.DataType.Enum{}), do: :enum
  defp type_tag(%Secant.DataType.Tuple{}), do: :tuple
  defp type_tag(%Secant.DataType.Array{}), do: :array
  defp type_tag(%Secant.DataType.Struct{}), do: :struct
  defp type_tag(%Secant.DataType.Blob{}), do: :blob
  defp type_tag(:null), do: :null

  @callback read_value(user_state :: term()) ::
              {:ok, term(), term()} | {:error, term(), term()}

  @callback read_status(user_state :: term()) ::
              {:ok, term(), term()} | {:error, term(), term()}

  @callback write_target(value :: term(), user_state :: term()) ::
              {:ok, term(), term()} | {:error, term(), term()}

  @optional_callbacks [read_value: 1, read_status: 1, write_target: 2]

  defmacro __using__(opts) do
    merged = Keyword.put(opts, :interface, :writable)

    quote do
      use Secant.Module, unquote(merged)
      @behaviour Secant.Module.Writable
    end
  end
end
