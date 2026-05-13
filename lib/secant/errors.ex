defmodule Secant.Error do
  @moduledoc "A SECoP protocol error."
  @type t :: %__MODULE__{name: String.t(), message: String.t()}
  defstruct [:name, :message]
end

defmodule Secant.Errors do
  @moduledoc "Constructors for every SECoP error class."

  def no_such_module(msg), do: %Secant.Error{name: "NoSuchModule", message: msg}
  def no_such_parameter(msg), do: %Secant.Error{name: "NoSuchParameter", message: msg}
  def no_such_accessible(msg), do: %Secant.Error{name: "NoSuchAccessible", message: msg}
  def no_such_command(msg), do: %Secant.Error{name: "NoSuchCommand", message: msg}
  def read_only(msg), do: %Secant.Error{name: "ReadOnly", message: msg}
  def bad_value(msg), do: %Secant.Error{name: "BadValue", message: msg}
  def wrong_type(msg), do: %Secant.Error{name: "WrongType", message: msg}
  def range_error(msg), do: %Secant.Error{name: "RangeError", message: msg}
  def command_failed(msg), do: %Secant.Error{name: "CommandFailed", message: msg}
  def internal_error(msg), do: %Secant.Error{name: "InternalError", message: msg}
  def protocol_error(msg), do: %Secant.Error{name: "ProtocolError", message: msg}
  def not_implemented(msg), do: %Secant.Error{name: "NotImplemented", message: msg}
  def disabled_module(msg), do: %Secant.Error{name: "DisabledModule", message: msg}
end
