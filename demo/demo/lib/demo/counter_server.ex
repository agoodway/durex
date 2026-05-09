defmodule Demo.CounterServer do
  @moduledoc """
  A GenServer that uses Durex to checkpoint its state to Tigris.

  Tracks a counter and a list of timestamped events, demonstrating
  how state survives process crashes via Durex checkpointing.
  """

  use GenServer
  use Durex, store: Durex.Store.Tigris, interval: 60_000, ttl: 300, version: 1

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    state = %{id: id, count: 0, events: []}
    state = Durex.start_sync(__MODULE__, state)

    case Durex.maybe_restore(__MODULE__, state) do
      {:ok, nil} -> {:ok, state}
      {:ok, restored} -> {:ok, Map.merge(state, restored)}
    end
  end

  @impl GenServer
  def handle_call(:increment, _from, state) do
    state = %{
      state
      | count: state.count + 1,
        events: state.events ++ [%{action: "increment", at: DateTime.utc_now(:second)}]
    }

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, Map.delete(state, :__durex__), state}
  end

  @impl GenServer
  def handle_call(:manual_checkpoint, _from, state) do
    Durex.checkpoint(__MODULE__, state)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:delete_checkpoint, _from, state) do
    Durex.delete(__MODULE__, state)
    {:reply, :ok, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Durex.checkpoint(__MODULE__, state)
  end

  @impl Durex
  @spec serialize(map()) :: map()
  def serialize(state), do: Map.take(state, [:id, :count, :events])

  @impl Durex
  @spec deserialize(map()) :: map()
  def deserialize(data) do
    Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  @impl Durex
  @spec checkpoint_key(map()) :: String.t()
  def checkpoint_key(state), do: state.id
end
