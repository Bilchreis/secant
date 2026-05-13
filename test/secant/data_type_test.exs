defmodule Secant.DataTypeTest do
  use ExUnit.Case, async: true

  alias Secant.DataType

  describe "to_datainfo/1" do
    test "double with options" do
      info = DataType.to_datainfo(%DataType.Double{min: 0, max: 100, unit: "K"})
      assert info == %{"type" => "double", "min" => 0, "max" => 100, "unit" => "K"}
    end

    test "int" do
      assert %{"type" => "int", "min" => 0, "max" => 255} =
               DataType.to_datainfo(%DataType.Int{min: 0, max: 255})
    end

    test "string" do
      assert %{"type" => "string", "maxchars" => 80} =
               DataType.to_datainfo(%DataType.String{maxchars: 80})
    end

    test "bool" do
      assert %{"type" => "bool"} = DataType.to_datainfo(%DataType.Bool{})
    end

    test "enum" do
      info = DataType.to_datainfo(%DataType.Enum{members: %{"IDLE" => 100, "BUSY" => 300}})
      assert info == %{"type" => "enum", "members" => %{"IDLE" => 100, "BUSY" => 300}}
    end

    test "tuple" do
      info = DataType.to_datainfo(%DataType.Tuple{types: [%DataType.Double{}, %DataType.String{}]})
      assert info["type"] == "tuple"
      assert length(info["members"]) == 2
    end

    test "array" do
      info = DataType.to_datainfo(%DataType.Array{type: %DataType.Double{}, minlen: 1, maxlen: 10})
      assert info["type"] == "array"
      assert info["minlen"] == 1
      assert info["maxlen"] == 10
    end

    test "struct" do
      info = DataType.to_datainfo(%DataType.Struct{fields: %{x: %DataType.Double{}, y: %DataType.Double{}}})
      assert info["type"] == "struct"
      assert Map.has_key?(info["members"], "x")
    end

    test "null" do
      assert %{"type" => "null"} = DataType.to_datainfo(:null)
    end
  end

  describe "to_datainfo/1 - complex nesting" do
    test "nested struct" do
      inner = %DataType.Struct{fields: %{x: %DataType.Double{}, y: %DataType.Double{}}}
      outer = %DataType.Struct{fields: %{position: inner, label: %DataType.String{}}}
      info = DataType.to_datainfo(outer)
      assert info["type"] == "struct"
      assert info["members"]["position"]["type"] == "struct"
      assert Map.has_key?(info["members"]["position"]["members"], "x")
      assert Map.has_key?(info["members"]["position"]["members"], "y")
      assert info["members"]["label"]["type"] == "string"
    end

    test "array of int" do
      info = DataType.to_datainfo(%DataType.Array{type: %DataType.Int{min: 0, max: 255}, minlen: 1, maxlen: 8})
      assert info == %{
        "type" => "array",
        "minlen" => 1,
        "maxlen" => 8,
        "members" => %{"type" => "int", "min" => 0, "max" => 255}
      }
    end

    test "array of bool" do
      info = DataType.to_datainfo(%DataType.Array{type: %DataType.Bool{}})
      assert info["type"] == "array"
      assert info["members"] == %{"type" => "bool"}
    end

    test "array of string" do
      info = DataType.to_datainfo(%DataType.Array{type: %DataType.String{maxchars: 20}})
      assert info["type"] == "array"
      assert info["members"]["type"] == "string"
      assert info["members"]["maxchars"] == 20
    end

    test "array of blob" do
      info = DataType.to_datainfo(%DataType.Array{type: %DataType.Blob{maxbytes: 64}})
      assert info["type"] == "array"
      assert info["members"]["type"] == "blob"
      assert info["members"]["maxbytes"] == 64
    end

    test "array of enum" do
      info =
        DataType.to_datainfo(
          %DataType.Array{
            type: %DataType.Enum{members: %{"LOW" => 0, "HIGH" => 1}},
            minlen: 1,
            maxlen: 4
          }
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
          %DataType.Array{
            type: %DataType.Struct{fields: %{name: %DataType.String{}, value: %DataType.Double{}}}
          }
        )

      assert info["type"] == "array"
      assert info["members"]["type"] == "struct"
      assert Map.has_key?(info["members"]["members"], "name")
      assert Map.has_key?(info["members"]["members"], "value")
    end

    test "array of tuple" do
      info =
        DataType.to_datainfo(
          %DataType.Array{
            type: %DataType.Tuple{types: [%DataType.Double{}, %DataType.Int{min: 0, max: 10}]},
            minlen: 0,
            maxlen: 5
          }
        )

      assert info["type"] == "array"
      assert info["members"]["type"] == "tuple"
      assert length(info["members"]["members"]) == 2
    end

    test "ragged array of arrays (minlen != maxlen)" do
      inner = %DataType.Array{type: %DataType.Double{}, minlen: 0, maxlen: 5}
      outer = %DataType.Array{type: inner, minlen: 1, maxlen: 3}
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
          %DataType.Tuple{
            types: [
              %DataType.Array{type: %DataType.Double{}, minlen: 2, maxlen: 2},
              %DataType.Array{type: %DataType.String{}, minlen: 1, maxlen: 5}
            ]
          }
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
          %DataType.Tuple{
            types: [
              %DataType.Struct{fields: %{x: %DataType.Double{}}},
              %DataType.Struct{fields: %{label: %DataType.String{}}}
            ]
          }
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
      assert {:ok, 25.0} = DataType.validate(25, %DataType.Double{min: 0, max: 100})
    end

    test "double below min" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate(-1, %DataType.Double{min: 0, max: 100})
    end

    test "double above max" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate(101, %DataType.Double{min: 0, max: 100})
    end

    test "int valid" do
      assert {:ok, 5} = DataType.validate(5, %DataType.Int{min: 0, max: 10})
    end

    test "int from float" do
      assert {:ok, 5} = DataType.validate(5.0, %DataType.Int{min: 0, max: 10})
    end

    test "int wrong type" do
      assert {:error, %Secant.Error{name: "WrongType"}} =
               DataType.validate("five", %DataType.Int{})
    end

    test "string valid" do
      assert {:ok, "hello"} = DataType.validate("hello", %DataType.String{})
    end

    test "string too long" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate("hello world", %DataType.String{maxchars: 5})
    end

    test "bool true" do
      assert {:ok, true} = DataType.validate(true, %DataType.Bool{})
    end

    test "bool from integer" do
      assert {:ok, true} = DataType.validate(1, %DataType.Bool{})
      assert {:ok, false} = DataType.validate(0, %DataType.Bool{})
    end

    test "enum from string" do
      assert {:ok, 100} = DataType.validate("IDLE", %DataType.Enum{members: %{"IDLE" => 100, "BUSY" => 300}})
    end

    test "enum invalid member" do
      assert {:error, %Secant.Error{name: "BadValue"}} =
               DataType.validate("UNKNOWN", %DataType.Enum{members: %{"IDLE" => 100}})
    end

    test "tuple valid" do
      assert {:ok, [100, "IDLE"]} =
               DataType.validate([100, "IDLE"], %DataType.Tuple{types: [%DataType.Int{}, %DataType.String{}]})
    end

    test "null" do
      assert {:ok, nil} = DataType.validate(nil, :null)
    end
  end

  describe "validate/2 - nested structs" do
    test "valid nested struct" do
      inner_type = %DataType.Struct{fields: %{x: %DataType.Double{}, y: %DataType.Double{}}}
      outer_type = %DataType.Struct{fields: %{position: inner_type, label: %DataType.String{}}}

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
      inner_type = %DataType.Struct{fields: %{x: %DataType.Double{}, y: %DataType.Double{}}}
      outer_type = %DataType.Struct{fields: %{position: inner_type}}

      assert {:error, %Secant.Error{name: "BadValue"}} =
               DataType.validate(%{"position" => %{"x" => 1.0}}, outer_type)
    end

    test "nested struct wrong type for inner field" do
      inner_type = %DataType.Struct{fields: %{x: %DataType.Double{}, y: %DataType.Double{}}}
      outer_type = %DataType.Struct{fields: %{position: inner_type}}

      assert {:error, %Secant.Error{name: "WrongType"}} =
               DataType.validate(
                 %{"position" => %{"x" => "not_a_number", "y" => 2.0}},
                 outer_type
               )
    end

    test "deeply nested struct (three levels)" do
      leaf = %DataType.Struct{fields: %{value: %DataType.Double{min: 0, max: 100}}}
      mid  = %DataType.Struct{fields: %{sensor: leaf, unit: %DataType.String{}}}
      root = %DataType.Struct{fields: %{channel: mid, enabled: %DataType.Bool{}}}

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
               DataType.validate([1, 2, 3], %DataType.Array{type: %DataType.Double{}, minlen: 1, maxlen: 5})
    end

    test "array too short" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([], %DataType.Array{type: %DataType.Double{}, minlen: 2, maxlen: 5})
    end

    test "array too long" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate(
                 [1, 2, 3, 4, 5, 6],
                 %DataType.Array{type: %DataType.Double{}, minlen: 1, maxlen: 5}
               )
    end

    test "array of int" do
      assert {:ok, [0, 100, 200]} =
               DataType.validate([0, 100, 200], %DataType.Array{type: %DataType.Int{min: 0, max: 255}})
    end

    test "array of int - element out of range" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([0, 300], %DataType.Array{type: %DataType.Int{min: 0, max: 255}})
    end

    test "array of bool" do
      assert {:ok, [true, false, true]} =
               DataType.validate([true, false, 1], %DataType.Array{type: %DataType.Bool{}})
    end

    test "array of bool - wrong element type" do
      assert {:error, %Secant.Error{name: "WrongType"}} =
               DataType.validate([true, "yes"], %DataType.Array{type: %DataType.Bool{}})
    end

    test "array of string" do
      assert {:ok, ["hello", "world"]} =
               DataType.validate(["hello", "world"], %DataType.Array{type: %DataType.String{maxchars: 10}})
    end

    test "array of string - element too long" do
      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate(
                 ["hello", "this string is too long"],
                 %DataType.Array{type: %DataType.String{maxchars: 10}}
               )
    end

    test "array of blob" do
      assert {:ok, ["abc", "de"]} =
               DataType.validate(["abc", "de"], %DataType.Array{type: %DataType.Blob{maxbytes: 10}})
    end

    test "array of enum" do
      members = %{"OFF" => 0, "ON" => 1}

      assert {:ok, [0, 1, 0]} =
               DataType.validate(["OFF", "ON", "OFF"], %DataType.Array{type: %DataType.Enum{members: members}})
    end

    test "array of enum - invalid member" do
      members = %{"OFF" => 0, "ON" => 1}

      assert {:error, %Secant.Error{name: "BadValue"}} =
               DataType.validate(["OFF", "MAYBE"], %DataType.Array{type: %DataType.Enum{members: members}})
    end

    test "array of struct" do
      type = %DataType.Array{
        type: %DataType.Struct{fields: %{x: %DataType.Double{}, y: %DataType.Double{}}}
      }

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
      type = %DataType.Array{
        type: %DataType.Tuple{types: [%DataType.Double{}, %DataType.Int{min: 0, max: 10}]}
      }

      assert {:ok, [[1.0, 5], [2.0, 0]]} =
               DataType.validate([[1, 5], [2, 0]], type)
    end
  end

  describe "validate/2 - ragged arrays (minlen != maxlen)" do
    test "variable-length inner arrays within bounds" do
      inner_type = %DataType.Array{type: %DataType.Double{}, minlen: 0, maxlen: 3}
      outer_type = %DataType.Array{type: inner_type, minlen: 1, maxlen: 4}

      assert {:ok, result} = DataType.validate([[1.0, 2.0], [3.0], []], outer_type)
      assert length(result) == 3
      assert hd(result) == [1.0, 2.0]
    end

    test "inner array exceeds its maxlen" do
      inner_type = %DataType.Array{type: %DataType.Double{}, minlen: 0, maxlen: 2}
      outer_type = %DataType.Array{type: inner_type, minlen: 1, maxlen: 4}

      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([[1.0, 2.0, 3.0]], outer_type)
    end

    test "outer array below minlen" do
      inner_type = %DataType.Array{type: %DataType.Double{}, minlen: 0, maxlen: 3}
      outer_type = %DataType.Array{type: inner_type, minlen: 2, maxlen: 4}

      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([[1.0]], outer_type)
    end

    test "outer array exceeds maxlen" do
      inner_type = %DataType.Array{type: %DataType.Double{}, minlen: 0, maxlen: 3}
      outer_type = %DataType.Array{type: inner_type, minlen: 1, maxlen: 2}

      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([[1.0], [2.0], [3.0]], outer_type)
    end

    test "all inner arrays at different valid lengths" do
      inner_type = %DataType.Array{type: %DataType.Int{min: 0, max: 100}, minlen: 1, maxlen: 5}
      outer_type = %DataType.Array{type: inner_type, minlen: 1, maxlen: 5}

      assert {:ok, result} =
               DataType.validate([[1], [2, 3], [4, 5, 6], [7, 8, 9, 10]], outer_type)

      assert Enum.map(result, &length/1) == [1, 2, 3, 4]
    end
  end

  describe "validate/2 - tuples of arrays and structs" do
    test "tuple of arrays - valid" do
      type =
        %DataType.Tuple{
          types: [
            %DataType.Array{type: %DataType.Double{}, minlen: 2, maxlen: 2},
            %DataType.Array{type: %DataType.String{}, minlen: 1, maxlen: 3}
          ]
        }

      assert {:ok, [[1.0, 2.0], ["a", "b"]]} =
               DataType.validate([[1, 2], ["a", "b"]], type)
    end

    test "tuple of arrays - inner array too long" do
      type =
        %DataType.Tuple{
          types: [
            %DataType.Array{type: %DataType.Double{}, maxlen: 2},
            %DataType.Array{type: %DataType.String{}, maxlen: 2}
          ]
        }

      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([[1.0, 2.0, 3.0], ["a"]], type)
    end

    test "tuple of arrays - wrong element type in sub-array" do
      type =
        %DataType.Tuple{
          types: [
            %DataType.Array{type: %DataType.Double{}},
            %DataType.Array{type: %DataType.Int{min: 0, max: 10}}
          ]
        }

      assert {:error, %Secant.Error{name: "WrongType"}} =
               DataType.validate([[1.0], ["not_an_int"]], type)
    end

    test "tuple of structs - valid" do
      type =
        %DataType.Tuple{
          types: [
            %DataType.Struct{fields: %{x: %DataType.Double{}, y: %DataType.Double{}}},
            %DataType.Struct{fields: %{label: %DataType.String{}, enabled: %DataType.Bool{}}}
          ]
        }

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
        %DataType.Tuple{
          types: [
            %DataType.Struct{fields: %{name: %DataType.String{}}},
            %DataType.Array{type: %DataType.Double{min: -100, max: 100}, minlen: 1, maxlen: 10}
          ]
        }

      assert {:ok, [%{"name" => "temp"}, readings]} =
               DataType.validate([%{"name" => "temp"}, [10, 20, 30]], type)

      assert readings == [10.0, 20.0, 30.0]
    end

    test "tuple of struct and array - array too long" do
      type =
        %DataType.Tuple{
          types: [
            %DataType.Struct{fields: %{name: %DataType.String{}}},
            %DataType.Array{type: %DataType.Double{}, minlen: 1, maxlen: 3}
          ]
        }

      assert {:error, %Secant.Error{name: "RangeError"}} =
               DataType.validate([%{"name" => "temp"}, [1, 2, 3, 4, 5]], type)
    end
  end

  describe "encode_value/2" do
    test "enum encodes as integer" do
      assert 100 = DataType.encode_value(100, %DataType.Enum{members: %{"IDLE" => 100, "BUSY" => 300}})
    end

    test "double stays float" do
      assert 25.0 = DataType.encode_value(25, %DataType.Double{})
    end
  end

  describe "encode_value/2 - complex nesting" do
    test "nested struct encodes recursively" do
      inner_type = %DataType.Struct{fields: %{x: %DataType.Double{}, y: %DataType.Double{}}}
      outer_type = %DataType.Struct{fields: %{position: inner_type, label: %DataType.String{}}}
      value = %{"position" => %{"x" => 1, "y" => 2}, "label" => "origin"}
      result = DataType.encode_value(value, outer_type)
      assert result["position"]["x"] == 1.0
      assert result["position"]["y"] == 2.0
      assert result["label"] == "origin"
    end

    test "array of enum encodes each element as integer" do
      members = %{"OFF" => 0, "ON" => 1}

      assert [0, 1, 0] =
               DataType.encode_value([0, 1, 0], %DataType.Array{type: %DataType.Enum{members: members}})
    end

    test "array of int stays integer" do
      assert [1, 2, 3] =
               DataType.encode_value([1, 2, 3], %DataType.Array{type: %DataType.Int{}})
    end

    test "array of double converts to float" do
      result = DataType.encode_value([1, 2, 3], %DataType.Array{type: %DataType.Double{}})
      assert result == [1.0, 2.0, 3.0]
      assert Enum.all?(result, &is_float/1)
    end

    test "array of arrays encodes recursively" do
      type = %DataType.Array{type: %DataType.Array{type: %DataType.Double{}}}
      result = DataType.encode_value([[1, 2], [3]], type)
      assert result == [[1.0, 2.0], [3.0]]
    end

    test "array of struct encodes each struct" do
      type = %DataType.Array{type: %DataType.Struct{fields: %{v: %DataType.Double{}}}}
      result = DataType.encode_value([%{"v" => 1}, %{"v" => 2}], type)
      assert Enum.map(result, & &1["v"]) == [1.0, 2.0]
    end

    test "tuple of arrays encodes each sub-array" do
      type =
        %DataType.Tuple{
          types: [
            %DataType.Array{type: %DataType.Double{}},
            %DataType.Array{type: %DataType.Enum{members: %{"A" => 1, "B" => 2}}}
          ]
        }

      assert [[1.0, 2.0], [1, 2]] =
               DataType.encode_value([[1, 2], [1, 2]], type)
    end

    test "tuple of structs encodes recursively" do
      type =
        %DataType.Tuple{
          types: [
            %DataType.Struct{fields: %{v: %DataType.Double{}}},
            %DataType.Struct{fields: %{s: %DataType.Enum{members: %{"X" => 10}}}}
          ]
        }

      assert [%{"v" => 1.0}, %{"s" => 10}] =
               DataType.encode_value([%{"v" => 1}, %{"s" => 10}], type)
    end
  end
end
