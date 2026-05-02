# Durex

GenServer state checkpointing to external stores for crash recovery and node migration.

Durex provides a macro-based API that injects periodic state checkpointing into any GenServer, with pluggable storage backends, per-module versioning, and built-in graceful degradation.

## Installation

Add `durex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:durex, "~> 0.1.0"}
  ]
end
```

## Configuration

```elixir
# config/config.exs
config :durex, :app_name, :my_app

config :durex, Durex.Store.Redis,
  connection: MyApp.Redis  # Named Redix process started by your app

# Optional: custom max payload size (default 1MB)
# config :durex, :max_payload_bytes, 2_097_152
```

## Redis Connection Ownership

Durex does **not** start or manage Redis connections. Your application must start a named Redix process in its supervision tree:

```elixir
# application.ex
children = [
  {Redix, name: MyApp.Redis, host: "localhost"}
]
```

## Usage

Add `use Durex` to your GenServer and implement three callbacks:

```elixir
defmodule MyApp.SessionServer do
  use GenServer
  use Durex,
    store: Durex.Store.Redis,
    interval: 30_000,  # checkpoint every 30s
    ttl: 300,          # expire after 5 minutes
    version: 1         # bump when serialization format changes

  def init(args) do
    state = %{session_id: args[:session_id], data: %{}}

    # Start periodic sync timer
    state = Durex.start_sync(__MODULE__, state)

    # Restore from checkpoint if available
    case Durex.maybe_restore(__MODULE__, state) do
      {:ok, nil}      -> {:ok, state}
      {:ok, restored} -> {:ok, Map.merge(state, restored)}
    end
  end

  def terminate(_reason, state) do
    # Final checkpoint on shutdown
    Durex.checkpoint(__MODULE__, state)
  end

  # --- Durex callbacks ---

  @impl Durex
  def serialize(state), do: Map.take(state, [:session_id, :data])

  @impl Durex
  def deserialize(data) do
    # JSON round-trips atom keys to strings — convert back safely
    Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  @impl Durex
  def checkpoint_key(state), do: state.session_id
end
```

## Callbacks

| Callback | Purpose |
|---|---|
| `serialize/1` | Convert state to a map for storage. The `__durex__` key is already stripped. |
| `deserialize/1` | Convert stored map back for merging into state. JSON round-trips atom keys to strings — use `String.to_existing_atom/1` to convert back (never `String.to_atom/1`). |
| `checkpoint_key/1` | Return a non-empty string identifying this process instance (e.g., a session ID). Receives state with `__durex__` stripped. |

## Options

| Option | Default | Description |
|---|---|---|
| `:store` | (required) | Store module implementing `Durex.Store` behaviour |
| `:interval` | `30_000` | Milliseconds between periodic checkpoints |
| `:ttl` | `nil` | TTL in seconds for stored checkpoints (store-dependent) |
| `:version` | `1` | Schema version; bump to invalidate stale checkpoints |

## Telemetry

Durex emits telemetry events that you can attach to for monitoring:

| Event | When |
|---|---|
| `[:durex, :checkpoint, :write]` | Successful checkpoint write (includes `:duration`) |
| `[:durex, :checkpoint, :write_failed]` | Store returned an error (includes `:reason`) |
| `[:durex, :checkpoint, :skipped]` | Payload too large or encode failed (includes `:reason`) |
| `[:durex, :restore, :ok]` | Restore completed (includes `:found` boolean) |
| `[:durex, :restore, :failed]` | Store error during restore (includes `:reason`) |

## Constraints

- **State must be a map.** Structs work fine (they are maps). Keyword lists and tuples are not supported.
- **The `__durex__` key is reserved.** Durex stashes timer bookkeeping in `state[:__durex__]`. This key is automatically excluded from serialization. Do not use it for your own data.
- **Place `use Durex` before your own `handle_info` clauses.** Durex injects a `handle_info(:__durex_sync__, ...)` clause. If you have a catch-all `handle_info/2`, it must come after `use Durex` to avoid shadowing the sync handler.
