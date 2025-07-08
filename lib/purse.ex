defmodule Purse do
  def create, do: spawn_link(&loop/0)

  def deposit(purse, currency, amount) do
    call(purse, :deposit, [currency, amount])
  end

  def withdraw(purse, currency, amount) do
    call(purse, :withdraw, [currency, amount])
  end

  def peek(purse, currency \\ nil) do
    call(purse, :peek, [currency])
  end

  def transfer(from_purse, to_purse, currency, amount) do
    Process.monitor(from_purse)
    Process.monitor(to_purse)

    balance_ref = make_ref()
    withdraw_ref = make_ref()
    deposit_ref = make_ref()
    fallback_deposit_ref = make_ref()

    task_state = %{
      balance_ref: balance_ref,
      withdraw_ref: withdraw_ref,
      deposit_ref: deposit_ref,
      fallback_deposit_ref: fallback_deposit_ref
    }

    {:ok, task} =
      Task.start_link(fn ->
        transfer_loop(from_purse, to_purse, currency, amount, task_state)
      end)

    send(from_purse, {:peek, [currency], balance_ref, task})
  end

  defp transfer_loop(from_purse, to_purse, currency, amount, state) do
    balance_ref = state.balance_ref
    withdraw_ref = state.withdraw_ref
    deposit_ref = state.deposit_ref
    fallback_deposit_ref = state.fallback_deposit_ref

    new_state =
      receive do
        {^balance_ref, :ok, current_balance} ->
          if current_balance >= amount do
            send(from_purse, {:withdraw, [currency, amount], withdraw_ref, self()})
            Map.put(state, :from_purse_balance, :ok)
          else
            Map.put(state, :from_purse_balance, :not_enough_money)
          end

        {^withdraw_ref, :ok, _new_state} ->
          send(to_purse, {:deposit, [currency, amount], deposit_ref, self()})
          Map.put(state, :from_purse_withdraw, :ok)

        {^deposit_ref, :ok, _new_state} ->
          Map.put(state, :to_purse_deposit, :ok)

        {^withdraw_ref, :error, reason} ->
          Map.put(state, :from_purse_withdraw, reason)

        {^deposit_ref, :error, reason} ->
          send(from_purse, {:deposit, [currency, amount], fallback_deposit_ref, self()})
          Map.put(state, :to_purse_deposit, reason)

        {^fallback_deposit_ref, :ok, _new_state} ->
          Map.put(state, :from_purse_fallback_deposit, :ok)

        {^fallback_deposit_ref, :error, reason} ->
          Map.put(state, :from_purse_fallback_deposit, reason)

        any ->
          IO.puts(inspect(any))
          state
      end

    transfer_loop(from_purse, to_purse, currency, amount, new_state)
  end

  defp call(purse, message, args) do
    Process.monitor(purse)

    ref = make_ref()
    send(purse, {message, args, ref, self()})

    receive do
      {^ref, :ok, result} ->
        result

      {^ref, :error, reason} ->
        {:error, reason}

      {:DOWN, _ref, :process, ^purse, reason} ->
        {:error, reason}
    end
  end

  defp loop(state \\ %{}) do
    state =
      receive do
        message ->
          handle_message(message, state)
      end

    loop(state)
  end

  defp handle_message({:deposit, [currency, amount], ref, sender}, state) do
    new_state = Map.update(state, currency, amount, &(&1 + amount))
    send(sender, {ref, :ok, new_state})
    new_state
  end

  defp handle_message({:withdraw, [currency, amount], ref, sender}, state) do
    case Map.get(state, currency, 0) do
      current_amount when current_amount >= amount ->
        new_state = Map.put(state, currency, current_amount - amount)
        send(sender, {ref, :ok, new_state})
        new_state

      _ ->
        send(sender, {ref, :error, "Not enough money"})
        state
    end
  end

  defp handle_message({:peek, [nil], ref, sender}, state) do
    send(sender, {ref, :ok, Map.to_list(state)})
    state
  end

  defp handle_message({:peek, [currency], ref, sender}, state) do
    send(sender, {ref, :ok, Map.get(state, currency, 0)})
    state
  end

  defp handle_message({:DOWN, _ref, :process, _purse, reason}, _state) do
    {:error, reason}
  end
end
