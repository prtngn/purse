defmodule Purse do
  use GenServer

  defdelegate create, to: Purse.Supervisor, as: :start_child

  def start_link(_, _) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(_) do
    {:ok, %{}}
  end

  def deposit(pid, currency, amount) do
    GenServer.call(pid, {:deposit, currency, amount})
  end

  def withdraw(pid, currency, amount) do
    GenServer.call(pid, {:withdraw, currency, amount})
  end

  def peek(pid, currency \\ nil) do
    GenServer.call(pid, {:peek, currency})
  end

  def transfer(from_pid, to_pid, currency, amount) do
    case GenServer.call(from_pid, {:withdraw, currency, amount}) do
      {:ok, _new_state} ->
        case GenServer.call(to_pid, {:deposit, currency, amount}) do
          {:ok, new_state} ->
            {:ok, new_state}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_enough_money} ->
        {:error, :not_enough_money}
    end
  end

  def handle_call({:deposit, currency, amount}, _, state) do
    new_state = Map.update(state, currency, amount, &(&1 + amount))

    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call({:withdraw, currency, amount}, _, state) do
    case Map.get(state, currency, 0) do
      current_balance when current_balance >= amount ->
        new_state = Map.update(state, currency, amount, &(&1 - amount))
        {:reply, {:ok, new_state}, new_state}

      _ ->
        {:reply, {:error, :not_enough_money}, state}
    end
  end

  def handle_call({:peek, nil}, _, state) do
    {:reply, Map.to_list(state), state}
  end

  def handle_call({:peek, currency}, _, state) do
    {:reply, Map.get(state, currency, 0), state}
  end
end
