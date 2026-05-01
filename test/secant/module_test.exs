defmodule Secant.ModuleTest do
  use ExUnit.Case, async: true

  # Define inline test modules at compile time
  defmodule TestReadable do
    use Secant.Module, interface: :readable

    defproperty :_manufacturer, "TestCorp"

    defparam :value, %{
      description: "test reading",
      datatype: {:double, min: 0, max: 100, unit: "K"},
      readonly: true
    }

    def read_value(state), do: {:ok, 42.0, state}
  end

  defmodule TestDrivable do
    use Secant.Module, interface: :drivable

    defparam :value, %{
      description: "current value",
      datatype: {:double, []},
      readonly: true
    }

    defparam :target, %{
      description: "target value",
      datatype: {:double, []},
      readonly: false
    }

    defparam :_custom_param, %{
      description: "a custom parameter",
      datatype: {:string, []},
      readonly: true
    }

    defcommand :stop, %{description: "Stop", argument: :null, result: :null}
    defcommand :_custom_cmd, %{description: "custom command", argument: :null, result: :null}
  end

  defmodule TestWithCustomCommand do
    use Secant.Module, interface: :module

    defcommand :_my_cmd, %{description: "custom", argument: :null, result: :null}
  end

  describe "interface class injection" do
    test "readable gets correct interface classes" do
      assert TestReadable.__secant_interface_classes__() == ["Readable", "Module"]
    end

    test "drivable gets correct interface classes" do
      assert TestDrivable.__secant_interface_classes__() == ["Drivable", "Writable", "Readable", "Module"]
    end

    test "module interface class" do
      assert TestWithCustomCommand.__secant_interface_classes__() == ["Module"]
    end
  end

  describe "parameter injection" do
    test "readable injects pollinterval, value, status" do
      param_names = TestReadable.__secant_params__() |> Enum.map(&elem(&1, 0))
      assert :pollinterval in param_names
      assert :value in param_names
      assert :status in param_names
    end

    test "user value param overrides injected default" do
      params = TestReadable.__secant_params__()
      {_, value_spec} = Enum.find(params, fn {n, _} -> n == :value end)
      assert Map.get(value_spec, :datatype) == {:double, min: 0, max: 100, unit: "K"}
    end

    test "drivable has target and value" do
      param_names = TestDrivable.__secant_params__() |> Enum.map(&elem(&1, 0))
      assert :value in param_names
      assert :target in param_names
    end

    test "custom params with underscore are allowed" do
      param_names = TestDrivable.__secant_params__() |> Enum.map(&elem(&1, 0))
      assert :_custom_param in param_names
    end
  end

  describe "command injection" do
    test "drivable injects stop command" do
      cmd_names = TestDrivable.__secant_commands__() |> Enum.map(&elem(&1, 0))
      assert :stop in cmd_names
    end

    test "custom commands with underscore are allowed" do
      cmd_names = TestDrivable.__secant_commands__() |> Enum.map(&elem(&1, 0))
      assert :_custom_cmd in cmd_names
    end
  end

  describe "properties" do
    test "custom properties are collected" do
      props = TestReadable.__secant_properties__()
      assert {:_manufacturer, "TestCorp"} in props
    end
  end

  describe "underscore prefix enforcement" do
    test "non-standard param without underscore raises CompileError" do
      assert_raise CompileError, ~r/prefixed with '_'/, fn ->
        Code.eval_string("""
        defmodule BadParam do
          use Secant.Module, interface: :module
          defparam :weird_custom, %{description: "bad", datatype: {:double, []}, readonly: true}
        end
        """)
      end
    end

    test "non-standard command without underscore raises CompileError" do
      assert_raise CompileError, ~r/prefixed with '_'/, fn ->
        Code.eval_string("""
        defmodule BadCmd do
          use Secant.Module, interface: :module
          defcommand :mycommand, %{description: "bad", argument: :null, result: :null}
        end
        """)
      end
    end

    test "property without underscore raises CompileError" do
      assert_raise CompileError, ~r/prefixed with '_'/, fn ->
        Code.eval_string("""
        defmodule BadProp do
          use Secant.Module, interface: :module
          defproperty :manufacturer, "ACME"
        end
        """)
      end
    end
  end

  describe "default callbacks" do
    test "init_module returns ok with empty map" do
      assert {:ok, %{}} = TestReadable.init_module([])
    end

    test "do_poll returns ok" do
      assert {:ok, _} = TestReadable.do_poll(%{})
    end
  end
end
