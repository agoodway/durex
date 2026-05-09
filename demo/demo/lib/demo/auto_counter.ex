defmodule Demo.AutoCounter do
  @moduledoc """
  A GenServer that auto-increments a counter every second and checkpoints
  to Tigris via Durex. Prints each tick to stdout.

  Kill it with Ctrl-C and restart to see state restored from Tigris.
  """

  use GenServer
  use Durex, store: Durex.Store.Tigris, interval: 1_000, ttl: 600, version: 1

  @tick_interval 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    state = %{id: id, count: 0, started_at: DateTime.utc_now(:second)}
    state = Durex.start_sync(__MODULE__, state)

    state =
      case Durex.maybe_restore(__MODULE__, state) do
        {:ok, nil} -> state
        {:ok, restored} -> Map.merge(state, restored)
      end

    schedule_tick()
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    state = %{state | count: state.count + 1}

    IO.puts(
      "  #{IO.ANSI.cyan()}[tick]#{IO.ANSI.reset()} count=#{state.count}  " <>
        "#{IO.ANSI.faint()}(checkpoint every 10s, Ctrl-C to stop)#{IO.ANSI.reset()}"
    )

    schedule_tick()
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Durex.checkpoint(__MODULE__, state)
  end

  @impl Durex
  @spec serialize(map()) :: map()
  def serialize(state), do: Map.take(state, [:id, :count, :started_at])

  @impl Durex
  @spec deserialize(map()) :: map()
  def deserialize(data) do
    Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  @impl Durex
  @spec checkpoint_key(map()) :: String.t()
  def checkpoint_key(state), do: state.id

  @spec schedule_tick() :: reference()
  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_interval)
end
