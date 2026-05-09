## Context

Durex is a new Elixir package (not an application) that provides GenServer state checkpointing to external stores. The pattern is extracted from `LeadRouter.ProcessCheckpoint` and `LeadRouter.Dialer.RuntimeCheckpoint`, which implement Redis-backed state persistence for crash recovery and node migration in a Horde cluster.

The host application owns the store connection (e.g., a Redix process in its supervision tree). Durex provides the macro, behaviour, and serialization logic — it does not start its own supervisor or connection pool.

## Goals / Non-Goals

**Goals:**
- Macro that wires periodic checkpointing into any GenServer with minimal boilerplate
- Pluggable store backends via a simple 3-function behaviour
- Redis backend as the first implementation
- Per-module versioning so schema changes invalidate stale checkpoints
- Graceful degradation: store failures never crash the GenServer
- Restore-on-init as an explicit user call (not automatic)
- Checkpoint on terminate as an explicit user call

**Non-Goals:**
- Durex does NOT start or supervise store connections (host app responsibility)
- No automatic conflict resolution or merge strategies
- No distributed locking or leader election
- No Postgres or S3 backends in this change (future work)
- No supervision tree or OTP application (pure library)

## Decisions

### 1. Macro injects `handle_info` only, init/terminate are explicit

The `use Durex` macro injects a single `handle_info(:__durex_sync__, state)` clause. Init restore and terminate checkpoint are one-liner calls the user adds themselves.

**Why**: Wrapping `init/1` via `@before_compile` is too magical and hard to debug. The user already writes `init` — adding one line is trivial. The injected `handle_info` is the only thing that's truly boilerplate with no user variation.

**Alternative considered**: Full `@before_compile` wrapping of init/terminate. Rejected for debuggability.

### 2. `Process.send_after` loop (not `:timer.send_interval`)

Each sync schedules the next via `Process.send_after`. This prevents drift accumulation and allows future "skip if clean" optimization.

**Why**: `send_interval` can queue up messages if a checkpoint takes longer than the interval. `send_after` guarantees at least `interval` ms between checkpoints.

### 3. `__durex__` key in GenServer state

`use Durex` defines `__durex_config__/0`, which exposes the module's `store`, `interval`, `ttl`, and `version` options at runtime. `Durex.start_sync/1` is a macro that expands in the caller module and stashes `%{__durex__: %{interval: ..., timer_ref: ..., last_checkpoint_at: ...}}` in the state map. The injected `handle_info` reads timer bookkeeping from this key and reads store/version configuration through `__durex_config__/0`.

**Why**: Module attributes are compile-time only. A generated `__durex_config__/0` function gives public API calls and injected code a single runtime source of truth, while the state key keeps per-process timer bookkeeping accessible and inspectable. The key is automatically excluded from serialization.

**Constraint**: State must be a map. Struct-based states work fine (structs are maps).

### 4. Store behaviour is minimal: write/read/delete

```elixir
@callback write(key :: String.t(), payload :: binary(), opts :: keyword()) :: :ok | {:error, term()}
@callback read(key :: String.t()) :: {:ok, binary() | nil} | {:error, term()}
@callback delete(key :: String.t()) :: :ok | {:error, term()}
```

Stores receive and return raw binaries (JSON-encoded by Durex core). TTL is passed in `opts` — stores that don't support TTL can ignore it or emulate it.

**Why**: Keeping stores as dumb byte pipes means Durex core owns all serialization, versioning, and size logic. Stores don't need to know about JSON or versions.

### 5. Key format: `durex:{app}:{module}:{user_key}`

- `app` — from `config :durex, :app_name` (required)
- `module` — the using module split into segments, underscored, downcased, and dot-separated (e.g., `my_app.session_server`)
- `user_key` — from `checkpoint_key/1` callback

**Why**: Prevents collisions between apps sharing a Redis instance. Module segment prevents collisions between GenServers in the same app. User key identifies the specific process instance.

### 6. Per-module versioning

Each `use Durex, version: N` declares the schema version for that module. On read, if the stored version doesn't match, Durex returns `{:ok, nil}` (stale checkpoint discarded).

**Why**: Global versioning (as in ProcessCheckpoint) forces all GenServers to invalidate when any one changes. Per-module is more precise.

### 7. Graceful degradation in Durex core, not stores

Stores return `{:error, reason}` honestly. `Durex.checkpoint/2`, `Durex.maybe_restore/2`, and `Durex.delete/2` catch all errors, log them, and return safe defaults (`:ok` for writes/deletes, `{:ok, nil}` for reads).

**Why**: Consistent behaviour regardless of backend. Store authors don't need to think about degradation.

### 8. Redis store uses a named Redix process from host app

`Durex.Store.Redis` calls `Redix.command(connection_name, [...])` where `connection_name` is configured:

```elixir
config :durex, Durex.Store.Redis,
  connection: MyApp.Redis  # Named Redix process started by host app
```

**Why**: Durex doesn't own the connection lifecycle. The host app may already have a Redix pool or connection. Durex just uses it.

## Risks / Trade-offs

- **[State must be a map]** → Document clearly. Keyword-list or tuple states won't work. This covers 95%+ of GenServer usage.
- **[`__durex__` key collision]** → Unlikely but document as reserved. If user has a `__durex__` key, it will be overwritten.
- **[Large state payloads]** → Enforce max payload size (1MB default, configurable). Log warning and skip if exceeded.
- **[Store unavailability at restore time]** → Returns `{:ok, nil}`, GenServer starts fresh. User should handle this case in their init.
- **[Message ordering]** → If GenServer mailbox is full, `:__durex_sync__` may be delayed. Acceptable — checkpoint is best-effort, not a guarantee.
