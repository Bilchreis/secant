defmodule Secant.ModuleTest do
  use ExUnit.Case, async: true

  @status_datatype "tuple([enum(%{\"DISABLED\" => 0, \"IDLE\" => 100, \"WARN\" => 200, \"BUSY\" => 300, \"ERROR\" => 400}), string()])"

  # Define inline test modules at compile time
  defmodule TestReadable do
    use Secant.Module.Readable

    description "Test readable module"
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

    description "Test drivable module"

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

    description "Module with custom command"

    defcommand :_my_cmd, %{description: "custom", argument: :null, result: :null}
  end

  defmodule TestWithImplementation do
    use Secant.Module.Readable

    description "Readable module with custom implementation string"
    implementation "my_app.sensors.thermometer"

    defparam :value, %{
      description: "current reading",
      datatype: double(unit: "K"),
      readonly: true
    }

    defparam :status, %{
      description: "module status",
      datatype: tuple([enum(%{"DISABLED" => 0, "IDLE" => 100, "WARN" => 200, "BUSY" => 300, "ERROR" => 400}), string()]),
      readonly: true
    }
  end

  defmodule TestWithFeatures do
    use Secant.Module.Readable

    description "Readable module with features declared"
    features ["has_target", "pausable"]

    defparam :value, %{
      description: "current reading",
      datatype: double(unit: "K"),
      readonly: true
    }

    defparam :status, %{
      description: "module status",
      datatype: tuple([enum(%{"DISABLED" => 0, "IDLE" => 100, "WARN" => 200, "BUSY" => 300, "ERROR" => 400}), string()]),
      readonly: true
    }
  end

  describe "interface class injection" do
    test "readable gets correct interface classes" do
      assert TestReadable.__secant_interface_classes__() == ["Readable"]
    end

    test "drivable gets correct interface classes" do
      assert TestDrivable.__secant_interface_classes__() == ["Drivable", "Writable", "Readable"]
    end

    test "bare module has no interface classes" do
      assert TestWithCustomCommand.__secant_interface_classes__() == []
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
          description "bad status module"
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
          description "bad status enum module"
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
          description "bad status string module"
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
          description "type mismatch module"
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
          description "min mismatch module"
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
          description "max mismatch module"
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
        description "valid range module"
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

  describe "implementation" do
    test "defaults to full Elixir module name" do
      assert TestReadable.__secant_implementation__() == "Secant.ModuleTest.TestReadable"
    end

    test "declared implementation string is returned" do
      assert TestWithImplementation.__secant_implementation__() == "my_app.sensors.thermometer"
    end

    test "bare module defaults to its full module name" do
      assert TestWithCustomCommand.__secant_implementation__() == "Secant.ModuleTest.TestWithCustomCommand"
    end
  end

  describe "features" do
    test "defaults to empty list when not declared" do
      assert TestReadable.__secant_features__() == []
    end

    test "declared features are returned" do
      assert TestWithFeatures.__secant_features__() == ["has_target", "pausable"]
    end

    test "bare module defaults to empty list" do
      assert TestWithCustomCommand.__secant_features__() == []
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

      description "Custom class test module"

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
               ["TestController", "Drivable", "Writable", "Readable"]
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
            description "missing ramp module"
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
            description "custom type mismatch module"
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

  describe "description enforcement" do
    test "module without description raises CompileError" do
      assert_raise CompileError, ~r/non-empty description/, fn ->
        Code.eval_string("""
        defmodule NoDescription do
          use Secant.Module
          defcommand :_my_cmd, %{description: "cmd", argument: :null, result: :null}
        end
        """)
      end
    end

    test "module with empty description raises CompileError" do
      assert_raise CompileError, ~r/non-empty description/, fn ->
        Code.eval_string("""
        defmodule EmptyDescription do
          use Secant.Module
          description ""
          defcommand :_my_cmd, %{description: "cmd", argument: :null, result: :null}
        end
        """)
      end
    end

    test "parameter with empty description raises CompileError" do
      assert_raise CompileError, ~r/non-empty :description/, fn ->
        Code.eval_string("""
        defmodule EmptyParamDesc do
          use Secant.Module
          description "valid module description"
          defparam :_foo, %{description: "", datatype: double(), readonly: true}
        end
        """)
      end
    end

    test "parameter with nil description raises CompileError" do
      assert_raise CompileError, ~r/non-empty :description/, fn ->
        Code.eval_string("""
        defmodule NilParamDesc do
          use Secant.Module
          description "valid module description"
          defparam :_foo, %{description: nil, datatype: double(), readonly: true}
        end
        """)
      end
    end

    test "command with empty description raises CompileError" do
      assert_raise CompileError, ~r/non-empty :description/, fn ->
        Code.eval_string("""
        defmodule EmptyCommandDesc do
          use Secant.Module
          description "valid module description"
          defcommand :_my_cmd, %{description: "", argument: :null, result: :null}
        end
        """)
      end
    end
  end
end
