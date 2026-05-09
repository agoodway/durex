## Why

GenServers that manage important state need crash recovery and node-migration resilience. Currently, each project re-implements checkpoint logic (serialize, store, restore, periodic sync) from scratch. Durex extracts this into a reusable package with a macro-based API, pluggable storage backends, and built-in graceful degradation.

## What Changes

- New `Durex` module with `__using__` macro that injects periodic sync via `Process.send_after` and a `handle_info` clause
- Behaviour callbacks: `serialize/1`, `deserialize/1`, `checkpoint_key/1`
- Public API: `Durex.maybe_restore/2`, `Durex.start_sync/1`, `Durex.checkpoint/2`, `Durex.delete/2`
- `Durex.Store` behaviour with `write/3`, `read/1`, `delete/1` callbacks
- `Durex.Store.Redis` implementation using Redix
- `Durex.Key` module for building namespaced keys (`durex:{app}:{module}:{user_key}`) with `build/2`
- `Durex.Checkpoint` module for JSON encoding, versioning (per-module), and size guards
- Graceful degradation baked into core: store errors never crash the GenServer
- `__durex__` key stashed in GenServer state for timer bookkeeping

## Capabilities

### New Capabilities
- `genserver-macro`: The `use Durex` macro that injects `handle_info(:__durex_sync__)`, defines the behaviour, and stores config as module attributes
- `store-behaviour`: The `Durex.Store` behaviour and `Durex.Store.Redis` implementation
- `checkpoint-core`: Key building, JSON versioning, size limits, and graceful degradation logic

### Modified Capabilities

## Impact

- New dependency: `redix` (for Redis store)
- New dependency: `jason` (for JSON serialization)
- Users add `use Durex` to their GenServer modules and implement 3 callbacks
- State maps gain a `__durex__` key (excluded from serialization automatically)
- No OTP application supervisor needed initially (Redix connection owned by host app)
