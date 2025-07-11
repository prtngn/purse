defmodule Purse do
  use GenServer

  @save_interval_ms Application.compile_env(:purse, :save_interval_ms)

  defdelegate create(name), to: Purse.Supervisor, as: :start_child

  def start_link(_, name) do
    GenServer.start_link(__MODULE__, name)
  end

  def init(name) do
    table =
      case File.exists?("#{name}.ets") do
        true ->
          {:ok, table} = :ets.file2tab(~c"#{name}.ets")
          table

        false ->
          :ets.new(:"#{name}", [:set, :protected])
      end

    schedule_save()

    {:ok, %{name: name, table: table, transaction: nil}}
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
    transaction_ref = make_ref()

    result =
      case GenServer.call(from_pid, {:transaction, :start, transaction_ref}) do
        {:ok, _new_state} ->
          case GenServer.call(to_pid, {:transaction, :start, transaction_ref}) do
            {:ok, _new_state} -> do_transfer(from_pid, to_pid, transaction_ref, currency, amount)
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end

    GenServer.call(from_pid, {:transaction, :end, transaction_ref})
    GenServer.call(to_pid, {:transaction, :end, transaction_ref})

    result
  end

  def do_transfer(from_pid, to_pid, transaction_ref, currency, amount) do
    case GenServer.call(from_pid, {:withdraw, currency, amount, transaction_ref}) do
      {:ok, _new_state} ->
        case GenServer.call(to_pid, {:deposit, currency, amount, transaction_ref}) do
          {:ok, new_state} ->
            {:ok, new_state}

          {:error, reason_to} ->
            case GenServer.call(from_pid, {:deposit, currency, amount}) do
              {:ok, _new_state} ->
                {:error, {:cannot_deposit_to_second_wallet, reason_to}}

              {:error, reason_from} ->
                {:error, {:cannot_deposit_to_first_wallet, reason_to, reason_from}}
            end
        end

      {:error, :not_enough_money} ->
        {:error, :not_enough_money}
    end
  end

  def handle_call({:transaction, :start, transaction_ref}, _, %{transaction: nil} = state) do
    new_state = %{state | transaction: transaction_ref}

    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call({:transaction, :start, _transaction_ref}, _, state) do
    {:reply, {:error, :transaction_already_started}, state}
  end

  def handle_call({:transaction, :end, transaction_ref}, _, %{transaction: transaction} = state)
      when transaction != transaction_ref do
    {:reply, {:error, :wrong_transaction}, state}
  end

  def handle_call({:transaction, :end, _transaction_ref}, _, %{transaction: nil} = state) do
    {:reply, {:error, :transaction_not_started}, state}
  end

  def handle_call({:transaction, :end, _transaction_ref}, _, state) do
    new_state = %{state | transaction: nil}

    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call(
        {:deposit, _currency, _amount, _transaction_ref},
        _,
        %{transaction: nil} = state
      ) do
    {:reply, {:error, :transaction_not_started}, state}
  end

  def handle_call(
        {:deposit, _currency, _amount, transaction_ref},
        _,
        %{transaction: transaction} = state
      )
      when transaction != transaction_ref do
    {:reply, {:error, :wrong_transaction}, state}
  end

  def handle_call({:deposit, currency, amount, _transaction_ref}, _, state) do
    do_deposit(state, currency, amount)
  end

  def handle_call({:deposit, currency, amount}, _, %{transaction: nil} = state) do
    do_deposit(state, currency, amount)
  end

  def handle_call({:deposit, _currency, _amount}, _, state) do
    {:reply, {:error, :wallet_is_in_transaction}, state}
  end

  def handle_call(
        {:withdraw, _currency, _amount, _transaction_ref},
        _,
        %{transaction: nil} = state
      ) do
    {:reply, {:error, :transaction_not_started}, state}
  end

  def handle_call(
        {:withdraw, _currency, _amount, transaction_ref},
        _,
        %{transaction: transaction} = state
      )
      when transaction != transaction_ref do
    {:reply, {:error, :wrong_transaction}, state}
  end

  def handle_call({:withdraw, currency, amount, _transaction_ref}, _, state) do
    do_withdraw(state, currency, amount)
  end

  def handle_call({:withdraw, currency, amount}, _, %{transaction: nil} = state) do
    do_withdraw(state, currency, amount)
  end

  def handle_call({:withdraw, _currency, _amount}, _, state) do
    {:reply, {:error, :wallet_is_in_transaction}, state}
  end

  def handle_call({:peek, nil}, _, state) do
    {:reply, :ets.tab2list(state.table), state}
  end

  def handle_call({:peek, currency}, _, state) do
    {:reply, :ets.lookup(state.table, currency), state}
  end

  def handle_info(:save, state) do
    :ets.tab2file(state.table, ~c"#{state.name}.ets")

    schedule_save()

    {:noreply, state}
  end

  defp do_deposit(state, currency, amount) do
    old_amount = amount(state.table, currency)
    :ets.update_element(state.table, currency, {2, old_amount + amount}, {currency, 0})

    {:reply, {:ok, :ets.tab2list(state.table)}, state}
  end

  defp do_withdraw(state, currency, amount) do
    old_amount = amount(state.table, currency)

    case old_amount >= amount do
      true ->
        :ets.update_element(state.table, currency, {2, old_amount - amount})
        {:reply, {:ok, :ets.tab2list(state.table)}, state}

      false ->
        {:reply, {:error, :not_enough_money}, state}
    end
  end

  defp amount(table, currency) do
    case :ets.lookup(table, currency) do
      [{_, amount}] -> amount
      _ -> 0
    end
  end

  defp schedule_save, do: Process.send_after(self(), :save, @save_interval_ms)
end
