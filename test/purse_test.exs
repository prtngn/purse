defmodule PurseTest do
  use ExUnit.Case, async: false
  doctest Purse

  setup do
    {:ok, purse: Purse.create()}
  end

  test ".create", %{purse: purse} do
    assert is_pid(purse)
  end

  test ".deposit", %{purse: purse} do
    assert Purse.deposit(purse, "USD", 100) == %{"USD" => 100}
  end

  test ".withdraw", %{purse: purse} do
    Purse.deposit(purse, "USD", 1000)

    assert Purse.withdraw(purse, "USD", 100) == %{"USD" => 900}
  end

  test ".peek", %{purse: purse} do
    Purse.deposit(purse, "USD", 1000)

    assert Purse.peek(purse) == [{"USD", 1000}]
    assert Purse.peek(purse, "USD") == 1000
    assert Purse.peek(purse, "EUR") == 0
  end

  test ".transfer", %{purse: purse} do
    purse2 = Purse.create()

    Purse.deposit(purse, "USD", 1000)
    Purse.deposit(purse, "EUR", 500)

    assert Purse.peek(purse) == [{"EUR", 500}, {"USD", 1000}]
    assert Purse.peek(purse2) == []

    Purse.transfer(purse, purse2, "USD", 100)

    assert Purse.peek(purse) == [{"EUR", 500}, {"USD", 900}]
    assert Purse.peek(purse2) == [{"USD", 100}]
  end
end
