defmodule PurseTest do
  use ExUnit.Case, async: false
  doctest Purse

  setup do
    {:ok, pid} = Purse.create("wallet1")
    {:ok, purse: pid}
  end

  test ".create", %{purse: purse} do
    assert is_pid(purse)
  end

  test ".deposit", %{purse: purse} do
    assert Purse.deposit(purse, "USD", 100) == {:ok, [{"USD", 100}]}
  end

  test ".withdraw", %{purse: purse} do
    Purse.deposit(purse, "USD", 1000)

    assert Purse.withdraw(purse, "USD", 100) == {:ok, [{"USD", 900}]}
  end

  test ".peek", %{purse: purse} do
    Purse.deposit(purse, "USD", 1000)

    assert Purse.peek(purse) == [{"USD", 1000}]
    assert Purse.peek(purse, "USD") == [{"USD", 1000}]
    assert Purse.peek(purse, "EUR") == []
  end

  test ".transfer", %{purse: purse} do
    {:ok, purse2} = Purse.create("wallet2")

    Purse.deposit(purse, "USD", 1000)
    Purse.deposit(purse, "EUR", 500)

    assert Purse.peek(purse) == [{"USD", 1000}, {"EUR", 500}]
    assert Purse.peek(purse2) == []

    assert Purse.transfer(purse, purse2, "USD", 100) == {:ok, [{"USD", 100}]}

    assert Purse.peek(purse) == [{"USD", 900}, {"EUR", 500}]
    assert Purse.peek(purse2) == [{"USD", 100}]
  end
end
