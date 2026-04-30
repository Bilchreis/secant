defmodule Secant.DataTypeTest do
  use ExUnit.Case, async: true

  alias Secant.DataType

  describe "to_datainfo/1" do
    test "double with options" do
      info = DataType.to_datainfo({:double, min: 0, max: 100, unit: "K"})
      assert info == %{"type" => "double", "min" => 0, "max" => 100, "unit" => "K"}
    end

    test "int" do
      assert %{"type" => "int", "min" => 0, "max" => 255} =
               DataType.to_datainfo({:int, min: 0, max: 255})
    end

    test "string" do
      assert %{"type" => "string", "maxchars" => 80} =
               DataType.to_datainfo({:string, maxchars: 80})
    end

    test "bool" do
      assert %{"type" => "bool"} = DataType.to_datainfo({:bool})
    end

    test "enum" do
      info = DataType.to_datainfo({:enum, %{"IDLE" => 100, "BUSY" => 300}})
      assert info == %{"type" => "enum", "members" => %{"IDLE" => 100, "BUSY" => 300}}
    end

    test "tuple" do
      info = DataType.to_datainfo({:tuple, [{:double, []}, {:string, []}]})
      assert info["type"] == "tuple"
      assert length(info["members"]) == 2
    end

    test "array" do
      info = DataType.to_datainfo({:array, {:double, []}, minlen: 1, maxlen: 10})
      assert info["type"] == "array"
      assert info["minlen"] == 1
      assert info["maxlen"] == 10
    end

    test "struct" do
      info = DataType.to_datainfo({:struct, %{x: {:double, []}, y: {:double, []}}})
      assert info["type"] == "struct"
      assert Map.has_key?(info["members"], "x")
    end

    test "null" do
      assert %{"type" => "null"} = DataType.to_datainfo(:null)
    end
  end

  describe "validate/2" do
    test "double in range" do
      assert {:ok, 25.0} = DataType.validate(25, {:double, min: 0, max: 100})
    end

    test "double below min" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate(-1, {:double, min: 0, max: 100})
    end

    test "double above max" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate(101, {:double, min: 0, max: 100})
    end

    test "int valid" do
      assert {:ok, 5} = DataType.validate(5, {:int, min: 0, max: 10})
    end

    test "int from float" do
      assert {:ok, 5} = DataType.validate(5.0, {:int, min: 0, max: 10})
    end

    test "int wrong type" do
      assert {:error, %Secant.Error{name: "WrongType"}} =
               DataType.validate("five", {:int, []})
    end

    test "string valid" do
      assert {:ok, "hello"} = DataType.validate("hello", {:string, []})
    end

    test "string too long" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate("hello world", {:string, maxchars: 5})
    end

    test "bool true" do
      assert {:ok, true} = DataType.validate(true, {:bool})
    end

    test "bool from integer" do
      assert {:ok, true} = DataType.validate(1, {:bool})
      assert {:ok, false} = DataType.validate(0, {:bool})
    end

    test "enum from string" do
      assert {:ok, 100} = DataType.validate("IDLE", {:enum, %{"IDLE" => 100, "BUSY" => 300}})
    end

    test "enum invalid member" do
      assert {:error, %Secant.Error{name: "BadValue"}} =
               DataType.validate("UNKNOWN", {:enum, %{"IDLE" => 100}})
    end

    test "tuple valid" do
      assert {:ok, [100, "IDLE"]} =
               DataType.validate([100, "IDLE"], {:tuple, [{:int, []}, {:string, []}]})
    end

    test "null" do
      assert {:ok, nil} = DataType.validate(nil, :null)
    end
  end

  describe "encode_value/2" do
    test "enum encodes integer to name" do
      assert "IDLE" = DataType.encode_value(100, {:enum, %{"IDLE" => 100, "BUSY" => 300}})
    end

    test "double stays float" do
      assert 25.0 = DataType.encode_value(25, {:double, []})
    end
  end
end
