defmodule Secant.Module.State do
  @moduledoc "Runtime state struct for a Secant.Module.Server GenServer."

  @type param_cache :: %{
          value: term(),
          timestamp: float(),
          error: Secant.Error.t() | nil
        }

  @type t :: %__MODULE__{
          name: String.t(),
          module: module(),
          node_name: atom(),
          params: %{atom() => param_cache()},
          param_specs: %{atom() => map()},
          command_specs: %{atom() => map()},
          interface_classes: [String.t()],
          description: String.t(),
          poll_interval_ms: non_neg_integer(),
          poll_timer_ref: reference() | nil,
          user_state: term(),
          runtime_properties: %{String.t() => term()}
        }

  defstruct name: nil,
            module: nil,
            node_name: nil,
            params: %{},
            param_specs: %{},
            command_specs: %{},
            interface_classes: [],
            description: "",
            poll_interval_ms: 5000,
            poll_timer_ref: nil,
            user_state: %{},
            runtime_properties: %{}
end
