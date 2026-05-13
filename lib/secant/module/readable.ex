defmodule Secant.Module.Readable do
  @moduledoc """
  Interface class behaviour for SECoP Readable modules.

  Requires `value` and `status` parameters.

  ## Usage

      defmodule MyApp.Sensor do
        use Secant.Module.Readable

        defparam :value,  %{description: "...", datatype: {:double, []}, readonly: true}
        defparam :status, %{description: "...", datatype: Secant.DataType.status_type(), readonly: true}
      end
  """

  def required_params, do: [:value, :status]
  def required_commands, do: []
  def class_list, do: ["Readable"]
  def default_poll_params, do: [:value, :status]

  def validate!(mod, params, _commands) do
    param_map = Map.new(params)
    if :status in Map.keys(param_map), do: validate_status_datatype!(mod, param_map[:status])
    :ok
  end

  defp validate_status_datatype!(mod, spec) do
    case Map.get(spec, :datatype) do
      %Secant.DataType.Tuple{types: [enum_type, string_type]} ->
        case enum_type do
          %Secant.DataType.Enum{members: members} when is_map(members) ->
            Enum.each(Map.values(members), fn v ->
              unless is_integer(v) and v >= 0 and v <= 499 do
                raise CompileError,
                  file: "#{mod}",
                  description:
                    "status enum codes must be integers in the range [0, 499]. Got: #{inspect(v)}."
              end
            end)

          _ ->
            raise CompileError,
              file: "#{mod}",
              description:
                "status parameter's first tuple element must be %Enum{members: %{name => integer_code}}."
        end

        unless match?(%Secant.DataType.String{}, string_type) do
          raise CompileError,
            file: "#{mod}",
            description:
              "status parameter datatype must be %Tuple{types: [enum_type, %String{}]}; " <>
                "second element must be a string type."
        end

      _ ->
        raise CompileError,
          file: "#{mod}",
          description:
            "status parameter must have datatype %Tuple{types: [enum_type, string_type]}."
    end
  end

  @callback read_value(user_state :: term()) ::
              {:ok, term(), term()} | {:error, term(), term()}

  @callback read_status(user_state :: term()) ::
              {:ok, term(), term()} | {:error, term(), term()}

  @optional_callbacks [read_value: 1, read_status: 1]

  defmacro __using__(opts) do
    merged = Keyword.put(opts, :interface, :readable)

    quote do
      use Secant.Module, unquote(merged)
      @behaviour Secant.Module.Readable
    end
  end
end
