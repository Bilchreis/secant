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
    value_type  = get_in(param_map, [:value, :datatype])
    target_type = get_in(param_map, [:target, :datatype])

    unless type_tag(value_type) == type_tag(target_type) do
      raise CompileError,
        file: "#{mod}",
        description:
          "value and target must have the same datatype. " <>
            "Got value: #{inspect(type_tag(value_type))}, target: #{inspect(type_tag(target_type))}."
    end

    case {value_type, target_type} do
      {{tag, value_opts}, {tag, target_opts}} when tag in [:double, :int] ->
        value_min  = Keyword.get(value_opts, :min)
        target_min = Keyword.get(target_opts, :min)
        value_max  = Keyword.get(value_opts, :max)
        target_max = Keyword.get(target_opts, :max)

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

      _ ->
        :ok
    end
  end

  defp type_tag({tag, _}),              do: tag
  defp type_tag({tag}),                 do: tag
  defp type_tag(tag) when is_atom(tag), do: tag

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
