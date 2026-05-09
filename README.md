# Durex

GenServer state checkpointing to external stores for crash recovery and node migration.

Durex provides a macro-based API that injects periodic state checkpointing into any GenServer, with pluggable storage backends, per-module versioning, and built-in graceful degradation.

## Installation

Add `durex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:durex, github: "agoodway/durex"}
  ]
end
```

If you use `Durex.Store.Tigris`, also add `:req` because Durex declares it as an optional dependency:

```elixir
def deps do
  [
    {:durex, github: "agoodway/durex"},
    {:req, "~> 0.5"}
  ]
end
```

## Configuration

```elixir
# config/config.exs
config :durex, :app_name, :my_app

config :durex, Durex.Store.Redis,
  connection: MyApp.Redis  # Named Redix process started by your app

# Optional Tigris object storage backend
config :durex, Durex.Store.Tigris,
  bucket: "my-bucket",
  access_key_id: "tid_xxx",
  secret_access_key: "tsec_xxx",
  prefix: "checkpoints"

# Optional: custom max payload size (default 1MB)
# config :durex, :max_payload_bytes, 2_097_152
```

For production, source Tigris credentials from your host application's `runtime.exs` or equivalent runtime configuration. Required keys are `:bucket`, `:access_key_id`, and `:secret_access_key`. Optional keys are `:endpoint` (defaults to `"https://t3.storage.dev"`), `:region` (defaults to `"auto"`), `:prefix`, and advanced `:req_options` for safe transport options such as `:adapter`, `:connect_options`, `:receive_timeout`, and `:pool_timeout`.

Tigris endpoints must be HTTPS origin URLs with a scheme, host, and optional port only, such as `"https://objects.example.com:8443"`. Paths, query strings, fragments, userinfo, and plain HTTP endpoints are rejected. Bucket names must be DNS-compatible because they are used in virtual-hosted object URLs.

## Redis Connection Ownership

Durex does **not** start or manage Redis connections. Your application must start a named Redix process in its supervision tree:

```elixir
# application.ex
children = [
  {Redix, name: MyApp.Redis, host: "localhost"}
]
```

## Redis Versus Tigris

Use `Durex.Store.Redis` for low-latency hot recovery when your application already owns a Redis connection. Use `Durex.Store.Tigris` when you want durable object-backed checkpointing and can tolerate object storage latency.

Tigris stores checkpoint payloads as raw object bodies. When you pass `ttl: seconds`, Durex writes an `x-amz-meta-durex-expires-at` metadata value and treats expired objects as missing on read. Expired objects are not physically deleted by Durex, so configure Tigris lifecycle cleanup for high-churn workloads.

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

### Force an Immediate Sync

Call `Durex.checkpoint/2` directly to write state to the store without waiting for the next periodic tick:

```elixir
def handle_call(:force_sync, _from, state) do
  Durex.checkpoint(__MODULE__, state)
  {:reply, :ok, state}
end
```

### Delete a Checkpoint

Remove a stored checkpoint when the process is done and no longer needs crash recovery:

```elixir
def handle_call(:finish, _from, state) do
  Durex.delete(__MODULE__, state)
  {:reply, :ok, state}
end
```

### Version Bumping

When your serialization format changes, bump the `:version` option. Durex will discard any stale checkpoints written with an older version and log a warning:

```elixir
# Before: stored checkpoints have version 1
use Durex, store: Durex.Store.Redis, version: 1

# After: bump to version 2, old checkpoints are ignored on restore
use Durex, store: Durex.Store.Redis, version: 2
```

### Custom Store Backend

Implement the `Durex.Store` behaviour to use any storage backend:

```elixir
defmodule MyApp.Store.S3 do
  @behaviour Durex.Store

  @impl Durex.Store
  def write(key, payload, opts) do
    ttl = Keyword.get(opts, :ttl)
    # write payload to S3...
    :ok
  end

  @impl Durex.Store
  def read(key) do
    # read from S3, return {:ok, binary} or {:ok, nil}
  end

  @impl Durex.Store
  def delete(key) do
    # delete from S3...
    :ok
  end
end
```

Then reference it in your GenServer:

```elixir
use Durex, store: MyApp.Store.S3, interval: 60_000, ttl: 3600
```

### Observing Telemetry

Attach to Durex telemetry events for monitoring and alerting:

```elixir
# In your application startup
:telemetry.attach_many(
  "durex-logger",
  [
    [:durex, :checkpoint, :write],
    [:durex, :checkpoint, :write_failed],
    [:durex, :checkpoint, :skipped],
    [:durex, :restore, :ok],
    [:durex, :restore, :failed]
  ],
  &MyApp.DurexTelemetry.handle_event/4,
  nil
)
```

```elixir
defmodule MyApp.DurexTelemetry do
  require Logger

  def handle_event([:durex, :checkpoint, :write], %{duration: duration}, %{module: mod}, _config) do
    Logger.info("[Durex] #{inspect(mod)} checkpoint wrote in #{System.convert_time_unit(duration, :native, :millisecond)}ms")
  end

  def handle_event([:durex, :checkpoint, :write_failed], _measurements, %{module: mod, reason: reason}, _config) do
    Logger.error("[Durex] #{inspect(mod)} checkpoint write failed: #{inspect(reason)}")
  end

  def handle_event([:durex, :restore, :ok], _measurements, %{module: mod, found: found?}, _config) do
    Logger.info("[Durex] #{inspect(mod)} restore: found=#{found?}")
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok
end
```

### Recovering from Restore Conflicts

By default, `maybe_restore/2` returns `{:ok, nil}` when a checkpoint is missing, has a version mismatch, is corrupted, or can't be read from the store. You can override `restore_conflicted/3` to recover from these cases:

```elixir
@impl Durex
def restore_conflicted(:missing_checkpoint, _key, _opts) do
  # Rebuild state from database when no checkpoint exists
  %{counter: MyApp.Repo.get_counter()}
end

def restore_conflicted({:version_mismatch, _expected, _actual}, _key, _opts) do
  # Migrate from older checkpoint format
  %{counter: 0, migrated: true}
end

def restore_conflicted(_reason, _key, _opts) do
  # For other conflicts, preserve default nil behavior
  nil
end
```

Return a map to recover with that data, or `nil` to keep the default `{:ok, nil}` behavior. Non-map, non-nil returns raise `ArgumentError`.

> **Note:** Maps returned from `restore_conflicted/3` bypass `deserialize/1` — return data in the format your `init/1` expects.

#### Conflict Reasons

| Reason | When |
|---|---|
| `:missing_checkpoint` | No checkpoint exists for the key |
| `{:version_mismatch, expected, actual}` | Stored version differs from module's configured version |
| `{:invalid_envelope, decoded}` | Stored JSON doesn't match the `%{"v" => _, "d" => _}` envelope |
| `{:corrupted_json, reason}` | Stored binary is not valid JSON |
| `{:store_read_error, reason}` | The store returned an error during read |

## Callbacks

| Callback | Purpose |
|---|---|
| `serialize/1` | Convert state to a map for storage. The `__durex__` key is already stripped. |
| `deserialize/1` | Convert stored map back for merging into state. JSON round-trips atom keys to strings — use `String.to_existing_atom/1` to convert back (never `String.to_atom/1`). |
| `checkpoint_key/1` | Return a non-empty string identifying this process instance (e.g., a session ID). Receives state with `__durex__` stripped. |
| `restore_conflicted/3` | *(optional)* Called when restore encounters a conflict. Return a map to recover, or `nil` to preserve default behavior. Default returns `nil`. |

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
| `[:durex, :restore, :ok]` | Restore completed (includes `:found` and `:recovered` booleans). `found: true` for valid checkpoints. `recovered: true` when `restore_conflicted/3` returned recovery data. |
| `[:durex, :restore, :failed]` | Store error during restore (includes `:reason`). `restore_conflicted/3` is still called after this event. |

## Constraints

- **State must be a map.** Structs work fine (they are maps). Keyword lists and tuples are not supported.
- **The `__durex__` key is reserved.** Durex stashes timer bookkeeping in `state[:__durex__]`. This key is automatically excluded from serialization. Do not use it for your own data.
- **Place `use Durex` before your own `handle_info` clauses.** Durex injects a `handle_info(:__durex_sync__, ...)` clause. If you have a catch-all `handle_info/2`, it must come after `use Durex` to avoid shadowing the sync handler.
