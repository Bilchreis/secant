defmodule SecantTest do
  use ExUnit.Case

  test "version is a string" do
    assert is_binary(Secant.version())
  end

  test "firmware includes version" do
    assert Secant.firmware() =~ "secant"
  end
end
