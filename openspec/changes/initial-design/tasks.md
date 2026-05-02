## 1. Project Setup

- [x] 1.1 Add `jason` and `redix` dependencies to mix.exs
- [x] 1.2 Add app config structure (`config :durex, :app_name` and `config :durex, Durex.Store.Redis`)
- [x] 1.3 Create directory structure: `lib/durex/`, `lib/durex/store/`

## 2. Store Behaviour and Redis Implementation

- [x] 2.1 Create `Durex.Store` behaviour module with `write/3`, `read/1`, `delete/1` callbacks
- [x] 2.2 Implement `Durex.Store.Redis` using named Redix connection from config
- [x] 2.3 Write tests for `Durex.Store.Redis` (requires Redix in test env)

## 3. Key Builder

- [x] 3.1 Create `Durex.Key` module with `build/2` that constructs `durex:{app}:{module}:{user_key}`
- [x] 3.2 Write tests for key construction, underscored module formatting, and missing config error

## 4. Checkpoint Core

- [x] 4.1 Create `Durex.Checkpoint` module with `encode/2` (JSON + version tagging) and `decode/2` (JSON + version check)
- [x] 4.2 Add payload size limit enforcement (default 1MB, configurable)
- [x] 4.3 Write tests for encode/decode, version mismatch, size limits, and corrupted JSON

## 5. Durex Macro and Public API

- [x] 5.1 Define `Durex` behaviour (`serialize/1`, `deserialize/1`, `checkpoint_key/1` callbacks)
- [x] 5.2 Implement `__using__` macro: validate options, store as module attrs, inject `handle_info(:__durex_sync__)`
- [x] 5.3 Implement generated `__durex_config__/0` for runtime access to store, interval, ttl, and version
- [x] 5.4 Implement `Durex.start_sync/1` macro — expand caller module, stash `__durex__` in state, schedule first `Process.send_after`
- [x] 5.5 Implement `Durex.checkpoint/2` — strip `__durex__`, call serialize, encode, write to store with graceful degradation
- [x] 5.6 Implement `Durex.maybe_restore/2` — build key from state, read from store, decode, call deserialize, return `{:ok, data | nil}`
- [x] 5.7 Implement `Durex.delete/2` — build key from state and delete it from the configured store with graceful degradation
- [x] 5.8 Implement `__durex__` key stripping before serialize

## 6. Integration Tests

- [x] 6.1 Create a test GenServer that `use Durex` with all callbacks implemented
- [x] 6.2 Test full lifecycle: init → restore (nil) → periodic sync fires → checkpoint written → restore returns data
- [x] 6.3 Test graceful degradation: store errors don't crash GenServer
- [x] 6.4 Test version mismatch: old checkpoint ignored after version bump
- [x] 6.5 Test terminate checkpoint: final write on shutdown
- [x] 6.6 Test delete: checkpoint key is removed and store errors return `:ok`

## 7. Documentation

- [x] 7.1 Update README with installation, configuration, GenServer usage example, callbacks, Redis connection ownership, map-state constraint, and reserved `__durex__` key
