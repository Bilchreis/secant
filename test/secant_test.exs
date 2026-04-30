defmodule SecantTest do
  use ExUnit.Case
  doctest Secant

  test "greets the world" do
    assert Secant.hello() == :world
  end
end
