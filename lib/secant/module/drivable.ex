defmodule Secant.Module.Drivable do
  @moduledoc """
  Interface class behaviour for SECoP Drivable modules.

  Requires `value`, `status`, and `target` parameters, plus a `stop` command.

  ## Usage

      defmodule MyApp.Motor do
        use Secant.Module.Drivable

        defparam :value,  %{description: "...", datatype: {:double, []}, readonly: true}
        defparam :status, %{description: "...", datatype: Secant.DataType.status_type(), readonly: true}
        defparam :target, %{description: "...", datatype: {:double, []}, readonly: false}
        defcommand :stop, %{description: "Stop", argument: :null, result: :null}
      end
  """

  def required_params,   do: [:value, :status, :target]
  def required_commands, do: [:stop]
  def class_list,        do: ["Drivable", "Writable", "Readable", "Module"]

  def validate!(mod, params, commands) do
    Secant.Module.Writable.validate!(mod, params, commands)
    :ok
  end

  @callback read_value(user_state :: term()) ::
              {:ok, term(), term()} | {:error, term(), term()}

  @callback read_status(user_state :: term()) ::
              {:ok, term(), term()} | {:error, term(), term()}

  @callback write_target(value :: term(), user_state :: term()) ::
              {:ok, term(), term()} | {:error, term(), term()}

  @callback do_stop(argument :: term(), user_state :: term()) ::
              {:ok, term(), term()} | {:error, term(), term()}

  @optional_callbacks [read_value: 1, read_status: 1, write_target: 2, do_stop: 2]

  defmacro __using__(opts) do
    merged = Keyword.put(opts, :interface, :drivable)

    quote do
      use Secant.Module, unquote(merged)
      @behaviour Secant.Module.Drivable
    end
  end
end
