defmodule Secant.ModuleTest do
  use ExUnit.Case, async: true

  @status_datatype "tuple([enum(%{\"DISABLED\" => 0, \"IDLE\" => 100, \"WARN\" => 200, \"BUSY\" => 300, \"ERROR\" => 400}), string()])"

  # Define inline test modules at compile time
  defmodule TestReadable do
    use Secant.Module.Readable

    defproperty :_manufacturer, "TestCorp"

    defparam :value, %{
      description: "test reading",
      datatype: double(min: 0, max: 100, unit: "K"),
      readonly: true
    }

    defparam :status, %{
      description: "module status",
      datatype: tuple([enum(%{"DISABLED" => 0, "IDLE" => 100, "WARN" => 200, "BUSY" => 300, "ERROR" => 400}), string()]),
      readonly: true
    }

    @impl Secant.Module.Readable
    def read_value(state), do: {:ok, 42.0, state}
  end

  defmodule TestDrivable do
    use Secant.Module.Drivable

    defparam :value, %{
      description: "current value",
      datatype: double(),
      readonly: true
    }

    defparam :status, %{
      description: "module status",
      datatype: tuple([enum(%{"DISABLED" => 0, "IDLE" => 100, "WARN" => 200, "BUSY" => 300, "ERROR" => 400}), string()]),
      readonly: true
    }

    defparam :target, %{
      description: "target value",
      datatype: double(),
      readonly: false
    }

    defparam :_custom_param, %{
      description: "a custom parameter",
      datatype: string(),
      readonly: true
    }

    defcommand :stop, %{description: "Stop", argument: :null, result: :null}
    defcommand :_custom_cmd, %{description: "custom command", argument: :null, result: :null}
  end

  defmodule TestWithCustomCommand do
    use Secant.Module

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

  describe "parameters" do
    test "readable has declared value and status" do
      param_names = TestReadable.__secant_params__() |> Enum.map(&elem(&1, 0))
      assert :value in param_names
      assert :status in param_names
    end

    test "value param spec matches declaration" do
      params = TestReadable.__secant_params__()
      {_, value_spec} = Enum.find(params, fn {n, _} -> n == :value end)
      assert Map.get(value_spec, :datatype) == %Secant.DataType.Double{min: 0, max: 100, unit: "K"}
    end

    test "drivable has value, status, and target" do
      param_names = TestDrivable.__secant_params__() |> Enum.map(&elem(&1, 0))
      assert :value in param_names
      assert :status in param_names
      assert :target in param_names
    end

    test "custom params with underscore are allowed" do
      param_names = TestDrivable.__secant_params__() |> Enum.map(&elem(&1, 0))
      assert :_custom_param in param_names
    end
  end

  describe "commands" do
    test "drivable has stop command" do
      cmd_names = TestDrivable.__secant_commands__() |> Enum.map(&elem(&1, 0))
      assert :stop in cmd_names
    end

    test "custom commands with underscore are allowed" do
      cmd_names = TestDrivable.__secant_commands__() |> Enum.map(&elem(&1, 0))
      assert :_custom_cmd in cmd_names
    end
  end

  describe "semantic validation" do
    test "status with non-enum first element raises CompileError" do
      assert_raise CompileError, ~r/first tuple element must be/, fn ->
        Code.eval_string("""
        defmodule BadStatus do
          use Secant.Module, interface: :readable
          defparam :value, %{description: "v", datatype: double(), readonly: true}
          defparam :status, %{description: "s", datatype: tuple([int(), string()]), readonly: true}
        end
        """)
      end
    end

    test "status enum code out of [0, 499] raises CompileError" do
      assert_raise CompileError, ~r/\[0, 499\]/, fn ->
        Code.eval_string("""
        defmodule BadStatusEnum do
          use Secant.Module, interface: :readable
          defparam :value, %{description: "v", datatype: double(), readonly: true}
          defparam :status, %{description: "s", datatype: tuple([enum(%{"IDLE" => 100, "BAD" => 500}), string()]), readonly: true}
        end
        """)
      end
    end

    test "status with non-string second element raises CompileError" do
      assert_raise CompileError, ~r/second element must be a string type/, fn ->
        Code.eval_string("""
        defmodule BadStatusString do
          use Secant.Module, interface: :readable
          defparam :value, %{description: "v", datatype: double(), readonly: true}
          defparam :status, %{description: "s", datatype: tuple([enum(%{"DISABLED" => 0, "IDLE" => 100, "WARN" => 200, "BUSY" => 300, "ERROR" => 400}), int()]), readonly: true}
        end
        """)
      end
    end

    test "value/target type mismatch raises CompileError" do
      assert_raise CompileError, ~r/same datatype/, fn ->
        Code.eval_string("""
        defmodule TypeMismatch do
          use Secant.Module, interface: :writable
          defparam :value, %{description: "v", datatype: double(), readonly: true}
          defparam :status, %{description: "s", datatype: #{@status_datatype}, readonly: true}
          defparam :target, %{description: "t", datatype: int(), readonly: false}
        end
        """)
      end
    end

    test "value min more restrictive than target min raises CompileError" do
      assert_raise CompileError, ~r/value min.*more restrictive/, fn ->
        Code.eval_string("""
        defmodule MinMismatch do
          use Secant.Module, interface: :writable
          defparam :value, %{description: "v", datatype: double(min: 20.0, max: 400.0), readonly: true}
          defparam :status, %{description: "s", datatype: #{@status_datatype}, readonly: true}
          defparam :target, %{description: "t", datatype: double(min: 0.0, max: 400.0), readonly: false}
        end
        """)
      end
    end

    test "value max more restrictive than target max raises CompileError" do
      assert_raise CompileError, ~r/value max.*more restrictive/, fn ->
        Code.eval_string("""
        defmodule MaxMismatch do
          use Secant.Module, interface: :writable
          defparam :value, %{description: "v", datatype: double(min: 0.0, max: 350.0), readonly: true}
          defparam :status, %{description: "s", datatype: #{@status_datatype}, readonly: true}
          defparam :target, %{description: "t", datatype: double(min: 0.0, max: 400.0), readonly: false}
        end
        """)
      end
    end

    test "value range encompassing target range is valid" do
      Code.eval_string("""
      defmodule ValidRange do
        use Secant.Module, interface: :writable
        defparam :value, %{description: "v", datatype: double(min: 0.0, max: 400.0), readonly: true}
        defparam :status, %{description: "s", datatype: #{@status_datatype}, readonly: true}
        defparam :target, %{description: "t", datatype: double(min: 20.0, max: 350.0), readonly: false}
      end
      """)
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
          use Secant.Module
          defparam :weird_custom, %{description: "bad", datatype: double(), readonly: true}
        end
        """)
      end
    end

    test "non-standard command without underscore raises CompileError" do
      assert_raise CompileError, ~r/prefixed with '_'/, fn ->
        Code.eval_string("""
        defmodule BadCmd do
          use Secant.Module
          defcommand :mycommand, %{description: "bad", argument: :null, result: :null}
        end
        """)
      end
    end

    test "property without underscore raises CompileError" do
      assert_raise CompileError, ~r/prefixed with '_'/, fn ->
        Code.eval_string("""
        defmodule BadProp do
          use Secant.Module
          defproperty :manufacturer, "ACME"
        end
        """)
      end
    end
  end

  describe "custom interface class" do
    defmodule TestCustomClass do
      use Secant.InterfaceClass,
        name: "TestController",
        extends: :drivable,
        requires_params: [:ramp]
    end

    defmodule TestCustomModule do
      use TestCustomClass

      defparam :value, %{description: "current value", datatype: double(), readonly: true}

      defparam :status, %{
        description: "module status",
        datatype: tuple([enum(%{"DISABLED" => 0, "IDLE" => 100, "WARN" => 200, "BUSY" => 300, "ERROR" => 400}), string()]),
        readonly: true
      }

      defparam :target, %{description: "target value", datatype: double(), readonly: false}
      defparam :ramp,   %{description: "ramp rate",    datatype: double(), readonly: false}
      defcommand :stop, %{description: "Stop", argument: :null, result: :null}
    end

    test "produces correct interface_classes list" do
      assert TestCustomModule.__secant_interface_classes__() ==
               ["TestController", "Drivable", "Writable", "Readable", "Module"]
    end

    test "missing extra required param raises CompileError" do
      assert_raise CompileError, ~r/missing required parameter 'ramp'/, fn ->
        Code.eval_string("""
        defmodule CustomMissingRamp do
          defmodule Ctrl do
            use Secant.InterfaceClass, name: "Ctrl", extends: :drivable, requires_params: [:ramp]
          end
          defmodule Mod do
            use Ctrl
            defparam :value,  %{description: "v", datatype: double(), readonly: true}
            defparam :status, %{description: "s", datatype: #{@status_datatype}, readonly: true}
            defparam :target, %{description: "t", datatype: double(), readonly: false}
            defcommand :stop, %{description: "Stop", argument: :null, result: :null}
          end
        end
        """)
      end
    end

    test "value/target compatibility still validated through custom class" do
      assert_raise CompileError, ~r/same datatype/, fn ->
        Code.eval_string("""
        defmodule CustomTypeMismatch do
          defmodule Ctrl2 do
            use Secant.InterfaceClass, name: "Ctrl2", extends: :drivable, requires_params: [:ramp]
          end
          defmodule Mod2 do
            use Ctrl2
            defparam :value,  %{description: "v", datatype: double(), readonly: true}
            defparam :status, %{description: "s", datatype: #{@status_datatype}, readonly: true}
            defparam :target, %{description: "t", datatype: int(),    readonly: false}
            defparam :ramp,   %{description: "r", datatype: double(), readonly: false}
            defcommand :stop, %{description: "Stop", argument: :null, result: :null}
          end
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
