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

  describe "to_datainfo/1 - complex nesting" do
    test "nested struct" do
      inner = {:struct, %{x: {:double, []}, y: {:double, []}}}
      outer = {:struct, %{position: inner, label: {:string, []}}}
      info = DataType.to_datainfo(outer)
      assert info["type"] == "struct"
      assert info["members"]["position"]["type"] == "struct"
      assert Map.has_key?(info["members"]["position"]["members"], "x")
      assert Map.has_key?(info["members"]["position"]["members"], "y")
      assert info["members"]["label"]["type"] == "string"
    end

    test "array of int" do
      info = DataType.to_datainfo({:array, {:int, min: 0, max: 255}, minlen: 1, maxlen: 8})
      assert info == %{
        "type" => "array",
        "minlen" => 1,
        "maxlen" => 8,
        "members" => %{"type" => "int", "min" => 0, "max" => 255}
      }
    end

    test "array of bool" do
      info = DataType.to_datainfo({:array, {:bool}, []})
      assert info["type"] == "array"
      assert info["members"] == %{"type" => "bool"}
    end

    test "array of string" do
      info = DataType.to_datainfo({:array, {:string, maxchars: 20}, []})
      assert info["type"] == "array"
      assert info["members"]["type"] == "string"
      assert info["members"]["maxchars"] == 20
    end

    test "array of blob" do
      info = DataType.to_datainfo({:array, {:blob, maxbytes: 64}, []})
      assert info["type"] == "array"
      assert info["members"]["type"] == "blob"
      assert info["members"]["maxbytes"] == 64
    end

    test "array of enum" do
      info =
        DataType.to_datainfo(
          {:array, {:enum, %{"LOW" => 0, "HIGH" => 1}}, minlen: 1, maxlen: 4}
        )

      assert info["type"] == "array"
      assert info["members"]["type"] == "enum"
      assert info["members"]["members"] == %{"LOW" => 0, "HIGH" => 1}
      assert info["minlen"] == 1
      assert info["maxlen"] == 4
    end

    test "array of struct" do
      info =
        DataType.to_datainfo(
          {:array, {:struct, %{name: {:string, []}, value: {:double, []}}}, []}
        )

      assert info["type"] == "array"
      assert info["members"]["type"] == "struct"
      assert Map.has_key?(info["members"]["members"], "name")
      assert Map.has_key?(info["members"]["members"], "value")
    end

    test "array of tuple" do
      info =
        DataType.to_datainfo(
          {:array, {:tuple, [{:double, []}, {:int, min: 0, max: 10}]}, minlen: 0, maxlen: 5}
        )

      assert info["type"] == "array"
      assert info["members"]["type"] == "tuple"
      assert length(info["members"]["members"]) == 2
    end

    test "ragged array of arrays (minlen != maxlen)" do
      inner = {:array, {:double, []}, minlen: 0, maxlen: 5}
      outer = {:array, inner, minlen: 1, maxlen: 3}
      info = DataType.to_datainfo(outer)
      assert info["type"] == "array"
      assert info["minlen"] == 1
      assert info["maxlen"] == 3
      assert info["members"]["type"] == "array"
      assert info["members"]["minlen"] == 0
      assert info["members"]["maxlen"] == 5
      assert info["members"]["members"]["type"] == "double"
    end

    test "tuple of arrays" do
      info =
        DataType.to_datainfo(
          {:tuple,
           [
             {:array, {:double, []}, minlen: 2, maxlen: 2},
             {:array, {:string, []}, minlen: 1, maxlen: 5}
           ]}
        )

      assert info["type"] == "tuple"
      assert length(info["members"]) == 2
      [first, second] = info["members"]
      assert first["type"] == "array"
      assert first["members"]["type"] == "double"
      assert second["type"] == "array"
      assert second["members"]["type"] == "string"
    end

    test "tuple of structs" do
      info =
        DataType.to_datainfo(
          {:tuple,
           [
             {:struct, %{x: {:double, []}}},
             {:struct, %{label: {:string, []}}}
           ]}
        )

      assert info["type"] == "tuple"
      assert length(info["members"]) == 2
      [first, second] = info["members"]
      assert first["type"] == "struct"
      assert second["type"] == "struct"
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

  describe "validate/2 - nested structs" do
    test "valid nested struct" do
      inner_type = {:struct, %{x: {:double, []}, y: {:double, []}}}
      outer_type = {:struct, %{position: inner_type, label: {:string, []}}}

      assert {:ok, result} =
               DataType.validate(
                 %{"position" => %{"x" => 1.0, "y" => 2.0}, "label" => "origin"},
                 outer_type
               )

      assert result["position"]["x"] == 1.0
      assert result["position"]["y"] == 2.0
      assert result["label"] == "origin"
    end

    test "nested struct missing inner key" do
      inner_type = {:struct, %{x: {:double, []}, y: {:double, []}}}
      outer_type = {:struct, %{position: inner_type}}

      assert {:error, %Secant.Error{name: "BadValue"}} =
               DataType.validate(%{"position" => %{"x" => 1.0}}, outer_type)
    end

    test "nested struct wrong type for inner field" do
      inner_type = {:struct, %{x: {:double, []}, y: {:double, []}}}
      outer_type = {:struct, %{position: inner_type}}

      assert {:error, %Secant.Error{name: "WrongType"}} =
               DataType.validate(
                 %{"position" => %{"x" => "not_a_number", "y" => 2.0}},
                 outer_type
               )
    end

    test "deeply nested struct (three levels)" do
      leaf = {:struct, %{value: {:double, min: 0, max: 100}}}
      mid = {:struct, %{sensor: leaf, unit: {:string, []}}}
      root = {:struct, %{channel: mid, enabled: {:bool}}}

      assert {:ok, result} =
               DataType.validate(
                 %{
                   "channel" => %{
                     "sensor" => %{"value" => 42.0},
                     "unit" => "K"
                   },
                   "enabled" => true
                 },
                 root
               )

      assert result["channel"]["sensor"]["value"] == 42.0
      assert result["channel"]["unit"] == "K"
      assert result["enabled"] == true
    end
  end

  describe "validate/2 - arrays" do
    test "valid array of doubles" do
      assert {:ok, [1.0, 2.0, 3.0]} =
               DataType.validate([1, 2, 3], {:array, {:double, []}, minlen: 1, maxlen: 5})
    end

    test "array too short" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([], {:array, {:double, []}, minlen: 2, maxlen: 5})
    end

    test "array too long" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate(
                 [1, 2, 3, 4, 5, 6],
                 {:array, {:double, []}, minlen: 1, maxlen: 5}
               )
    end

    test "array of int" do
      assert {:ok, [0, 100, 200]} =
               DataType.validate([0, 100, 200], {:array, {:int, min: 0, max: 255}, []})
    end

    test "array of int - element out of range" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([0, 300], {:array, {:int, min: 0, max: 255}, []})
    end

    test "array of bool" do
      assert {:ok, [true, false, true]} =
               DataType.validate([true, false, 1], {:array, {:bool}, []})
    end

    test "array of bool - wrong element type" do
      assert {:error, %Secant.Error{name: "WrongType"}} =
               DataType.validate([true, "yes"], {:array, {:bool}, []})
    end

    test "array of string" do
      assert {:ok, ["hello", "world"]} =
               DataType.validate(["hello", "world"], {:array, {:string, maxchars: 10}, []})
    end

    test "array of string - element too long" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate(
                 ["hello", "this string is too long"],
                 {:array, {:string, maxchars: 10}, []}
               )
    end

    test "array of blob" do
      assert {:ok, ["abc", "de"]} =
               DataType.validate(["abc", "de"], {:array, {:blob, maxbytes: 10}, []})
    end

    test "array of enum" do
      members = %{"OFF" => 0, "ON" => 1}

      assert {:ok, [0, 1, 0]} =
               DataType.validate(["OFF", "ON", "OFF"], {:array, {:enum, members}, []})
    end

    test "array of enum - invalid member" do
      members = %{"OFF" => 0, "ON" => 1}

      assert {:error, %Secant.Error{name: "BadValue"}} =
               DataType.validate(["OFF", "MAYBE"], {:array, {:enum, members}, []})
    end

    test "array of struct" do
      type = {:array, {:struct, %{x: {:double, []}, y: {:double, []}}}, []}

      assert {:ok, result} =
               DataType.validate(
                 [%{"x" => 1.0, "y" => 2.0}, %{"x" => 3.0, "y" => 4.0}],
                 type
               )

      assert length(result) == 2
      assert hd(result)["x"] == 1.0
      assert List.last(result)["y"] == 4.0
    end

    test "array of tuple" do
      type = {:array, {:tuple, [{:double, []}, {:int, min: 0, max: 10}]}, []}

      assert {:ok, [[1.0, 5], [2.0, 0]]} =
               DataType.validate([[1, 5], [2, 0]], type)
    end
  end

  describe "validate/2 - ragged arrays (minlen != maxlen)" do
    test "variable-length inner arrays within bounds" do
      inner_type = {:array, {:double, []}, minlen: 0, maxlen: 3}
      outer_type = {:array, inner_type, minlen: 1, maxlen: 4}

      assert {:ok, result} = DataType.validate([[1.0, 2.0], [3.0], []], outer_type)
      assert length(result) == 3
      assert hd(result) == [1.0, 2.0]
    end

    test "inner array exceeds its maxlen" do
      inner_type = {:array, {:double, []}, minlen: 0, maxlen: 2}
      outer_type = {:array, inner_type, minlen: 1, maxlen: 4}

      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([[1.0, 2.0, 3.0]], outer_type)
    end

    test "outer array below minlen" do
      inner_type = {:array, {:double, []}, minlen: 0, maxlen: 3}
      outer_type = {:array, inner_type, minlen: 2, maxlen: 4}

      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([[1.0]], outer_type)
    end

    test "outer array exceeds maxlen" do
      inner_type = {:array, {:double, []}, minlen: 0, maxlen: 3}
      outer_type = {:array, inner_type, minlen: 1, maxlen: 2}

      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([[1.0], [2.0], [3.0]], outer_type)
    end

    test "all inner arrays at different valid lengths" do
      inner_type = {:array, {:int, min: 0, max: 100}, minlen: 1, maxlen: 5}
      outer_type = {:array, inner_type, minlen: 1, maxlen: 5}

      assert {:ok, result} =
               DataType.validate([[1], [2, 3], [4, 5, 6], [7, 8, 9, 10]], outer_type)

      assert Enum.map(result, &length/1) == [1, 2, 3, 4]
    end
  end

  describe "validate/2 - tuples of arrays and structs" do
    test "tuple of arrays - valid" do
      type =
        {:tuple,
         [
           {:array, {:double, []}, minlen: 2, maxlen: 2},
           {:array, {:string, []}, minlen: 1, maxlen: 3}
         ]}

      assert {:ok, [[1.0, 2.0], ["a", "b"]]} =
               DataType.validate([[1, 2], ["a", "b"]], type)
    end

    test "tuple of arrays - inner array too long" do
      type =
        {:tuple,
         [
           {:array, {:double, []}, minlen: 0, maxlen: 2},
           {:array, {:string, []}, minlen: 0, maxlen: 2}
         ]}

      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([[1.0, 2.0, 3.0], ["a"]], type)
    end

    test "tuple of arrays - wrong element type in sub-array" do
      type =
        {:tuple,
         [
           {:array, {:double, []}, []},
           {:array, {:int, min: 0, max: 10}, []}
         ]}

      assert {:error, %Secant.Error{name: "WrongType"}} =
               DataType.validate([[1.0], ["not_an_int"]], type)
    end

    test "tuple of structs - valid" do
      type =
        {:tuple,
         [
           {:struct, %{x: {:double, []}, y: {:double, []}}},
           {:struct, %{label: {:string, []}, enabled: {:bool}}}
         ]}

      assert {:ok, [pos, meta]} =
               DataType.validate(
                 [%{"x" => 1.0, "y" => 2.0}, %{"label" => "sensor", "enabled" => true}],
                 type
               )

      assert pos["x"] == 1.0
      assert pos["y"] == 2.0
      assert meta["label"] == "sensor"
      assert meta["enabled"] == true
    end

    test "tuple of struct and array - valid" do
      type =
        {:tuple,
         [
           {:struct, %{name: {:string, []}}},
           {:array, {:double, min: -100, max: 100}, minlen: 1, maxlen: 10}
         ]}

      assert {:ok, [%{"name" => "temp"}, readings]} =
               DataType.validate([%{"name" => "temp"}, [10, 20, 30]], type)

      assert readings == [10.0, 20.0, 30.0]
    end

    test "tuple of struct and array - array too long" do
      type =
        {:tuple,
         [
           {:struct, %{name: {:string, []}}},
           {:array, {:double, []}, minlen: 1, maxlen: 3}
         ]}

      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([%{"name" => "temp"}, [1, 2, 3, 4, 5]], type)
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

  describe "encode_value/2 - complex nesting" do
    test "nested struct encodes recursively" do
      inner_type = {:struct, %{x: {:double, []}, y: {:double, []}}}
      outer_type = {:struct, %{position: inner_type, label: {:string, []}}}
      value = %{"position" => %{"x" => 1, "y" => 2}, "label" => "origin"}
      result = DataType.encode_value(value, outer_type)
      assert result["position"]["x"] == 1.0
      assert result["position"]["y"] == 2.0
      assert result["label"] == "origin"
    end

    test "array of enum encodes each element to name" do
      members = %{"OFF" => 0, "ON" => 1}

      assert ["OFF", "ON", "OFF"] =
               DataType.encode_value([0, 1, 0], {:array, {:enum, members}, []})
    end

    test "array of int stays integer" do
      assert [1, 2, 3] =
               DataType.encode_value([1, 2, 3], {:array, {:int, []}, []})
    end

    test "array of double converts to float" do
      result = DataType.encode_value([1, 2, 3], {:array, {:double, []}, []})
      assert result == [1.0, 2.0, 3.0]
      assert Enum.all?(result, &is_float/1)
    end

    test "array of arrays encodes recursively" do
      type = {:array, {:array, {:double, []}, []}, []}
      result = DataType.encode_value([[1, 2], [3]], type)
      assert result == [[1.0, 2.0], [3.0]]
    end

    test "array of struct encodes each struct" do
      type = {:array, {:struct, %{v: {:double, []}}}, []}
      result = DataType.encode_value([%{"v" => 1}, %{"v" => 2}], type)
      assert Enum.map(result, & &1["v"]) == [1.0, 2.0]
    end

    test "tuple of arrays encodes each sub-array" do
      type =
        {:tuple,
         [
           {:array, {:double, []}, []},
           {:array, {:enum, %{"A" => 1, "B" => 2}}, []}
         ]}

      assert [[1.0, 2.0], ["A", "B"]] =
               DataType.encode_value([[1, 2], [1, 2]], type)
    end

    test "tuple of structs encodes recursively" do
      type =
        {:tuple,
         [
           {:struct, %{v: {:double, []}}},
           {:struct, %{s: {:enum, %{"X" => 10}}}}
         ]}

      assert [%{"v" => 1.0}, %{"s" => "X"}] =
               DataType.encode_value([%{"v" => 1}, %{"s" => 10}], type)
    end
  end
end
