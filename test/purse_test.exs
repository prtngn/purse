defmodule PurseTest do
  use ExUnit.Case
  doctest Purse

  test "greets the world" do
    assert Purse.hello() == :world
  end
end
