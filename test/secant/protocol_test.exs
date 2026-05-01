defmodule Secant.ProtocolTest do
  use ExUnit.Case, async: true

  alias Secant.Protocol

  describe "get_next_message/1" do
    test "extracts a complete message" do
      assert {:ok, {"describe", nil, nil}, ""} = Protocol.get_next_message("describe\n")
    end

    test "extracts message with specifier" do
      assert {:ok, {"read", "temp:value", nil}, ""} =
               Protocol.get_next_message("read temp:value\n")
    end

    test "extracts message with JSON data" do
      assert {:ok, {"change", "temp:target", 25.0}, ""} =
               Protocol.get_next_message("change temp:target 25.0\n")
    end

    test "returns :more when buffer incomplete" do
      assert {:more, "describe"} = Protocol.get_next_message("describe")
    end

    test "handles *IDN? request" do
      assert {:ok, {"*IDN?", nil, nil}, ""} = Protocol.get_next_message("*IDN?\n")
    end

    test "leaves remainder in buffer" do
      assert {:ok, {"describe", nil, nil}, "read temp:value\n"} =
               Protocol.get_next_message("describe\nread temp:value\n")
    end

    test "handles \\r\\n line endings" do
      assert {:ok, {"describe", nil, nil}, ""} = Protocol.get_next_message("describe\r\n")
    end
  end

  describe "encode_frame/1" do
    test "encodes action only" do
      assert "describe\n" = Protocol.encode_frame({"describe", nil, nil})
    end

    test "encodes action + empty specifier" do
      assert "active\n" = Protocol.encode_frame({"active", "", nil})
    end

    test "encodes action + specifier + data" do
      frame = Protocol.encode_frame({"reply", "temp:value", [25.0, %{"t" => 1000.0}]})
      assert String.starts_with?(frame, "reply temp:value ")
      assert String.ends_with?(frame, "\n")
    end

    test "encodes ping/pong" do
      frame = Protocol.encode_frame({"pong", "tok1", [nil, %{"t" => 1.0}]})
      assert frame =~ "pong tok1"
    end
  end

  describe "parse_specifier/1" do
    test "parses module:param" do
      assert {:ok, "temp", "value"} = Protocol.parse_specifier("temp:value")
    end

    test "parses module only" do
      assert {:ok, "temp", nil} = Protocol.parse_specifier("temp")
    end

    test "handles nil" do
      assert {:ok, nil, nil} = Protocol.parse_specifier(nil)
    end

    test "handles dot" do
      assert {:ok, ".", nil} = Protocol.parse_specifier(".")
    end
  end
end
