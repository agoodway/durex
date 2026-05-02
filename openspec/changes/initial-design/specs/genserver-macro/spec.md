## ADDED Requirements

### Requirement: use Durex macro injects handle_info for periodic sync

The `use Durex` macro SHALL inject a `handle_info(:__durex_sync__, state)` clause into the using module. This clause SHALL call `Durex.checkpoint/2` and schedule the next sync via `Process.send_after/3`.

#### Scenario: Periodic checkpoint fires after interval
- **WHEN** the interval elapses after `Durex.start_sync/1` is called
- **THEN** the GenServer receives `:__durex_sync__` and writes serialized state to the configured store

#### Scenario: Next sync is scheduled after each checkpoint
- **WHEN** a `:__durex_sync__` message is handled
- **THEN** a new `Process.send_after(self(), :__durex_sync__, interval)` is scheduled

### Requirement: use Durex defines behaviour callbacks

The `use Durex` macro SHALL define `@behaviour Durex` on the using module, requiring three callbacks: `serialize/1`, `deserialize/1`, and `checkpoint_key/1`.

#### Scenario: Module missing serialize callback
- **WHEN** a module uses `use Durex` without defining `serialize/1`
- **THEN** the compiler emits a warning about the missing callback

#### Scenario: Module implements all callbacks
- **WHEN** a module uses `use Durex` and implements `serialize/1`, `deserialize/1`, and `checkpoint_key/1`
- **THEN** the module compiles without callback warnings

### Requirement: use Durex accepts configuration options

The `use Durex` macro SHALL accept the following options: `store` (module), `interval` (milliseconds), `ttl` (seconds), and `version` (positive integer).

#### Scenario: All options provided
- **WHEN** a module declares `use Durex, store: Durex.Store.Redis, interval: 30_000, ttl: 300, version: 1`
- **THEN** the injected `handle_info` uses these values for sync scheduling, store writes, and version tagging

#### Scenario: Missing required option
- **WHEN** a module declares `use Durex` without `store` option
- **THEN** compilation raises an error indicating the missing required option

#### Scenario: Runtime config exposed
- **WHEN** a module declares `use Durex, store: Durex.Store.Redis, interval: 30_000, ttl: 300, version: 1`
- **THEN** the module defines `__durex_config__/0` returning those values for Durex runtime operations

### Requirement: Durex.start_sync stashes bookkeeping and schedules first timer

`Durex.start_sync/1` SHALL expand in the caller module, read that module's generated `__durex_config__/0`, add a `__durex__` key to the state map containing interval and timer bookkeeping data, and schedule the first `:__durex_sync__` message.

#### Scenario: start_sync adds __durex__ key
- **WHEN** `Durex.start_sync(state)` is called with a map state
- **THEN** the returned state contains a `__durex__` key with interval and timer metadata

#### Scenario: start_sync schedules first sync
- **WHEN** `Durex.start_sync(state)` is called
- **THEN** a `:__durex_sync__` message is scheduled via `Process.send_after` for the configured interval

### Requirement: Durex.checkpoint writes state to store

`Durex.checkpoint/2` SHALL call `serialize/1` on the module, build the key, and write to the configured store. It SHALL always return `:ok`.

#### Scenario: Successful checkpoint
- **WHEN** `Durex.checkpoint(MyModule, state)` is called and the store is available
- **THEN** serialized state is written to the store under the built key with TTL

#### Scenario: Store unavailable during checkpoint
- **WHEN** `Durex.checkpoint(MyModule, state)` is called and the store returns `{:error, :unavailable}`
- **THEN** the error is logged and `:ok` is returned (no crash)

### Requirement: Durex.maybe_restore reads from store

`Durex.maybe_restore/2` SHALL build the key from the state, read from the store, and return either `{:ok, nil}` (no checkpoint) or `{:ok, deserialized_data}`. The user is responsible for merging into their state.

#### Scenario: Checkpoint exists and version matches
- **WHEN** `Durex.maybe_restore(MyModule, state)` is called and a valid checkpoint exists
- **THEN** `{:ok, deserialized_data}` is returned where `deserialized_data` is the result of `deserialize/1`

#### Scenario: No checkpoint exists
- **WHEN** `Durex.maybe_restore(MyModule, state)` is called and no checkpoint is stored
- **THEN** `{:ok, nil}` is returned

#### Scenario: Version mismatch
- **WHEN** `Durex.maybe_restore(MyModule, state)` is called and the stored version differs from the module's configured version
- **THEN** `{:ok, nil}` is returned and the stale checkpoint is discarded

#### Scenario: Store unavailable during restore
- **WHEN** `Durex.maybe_restore(MyModule, state)` is called and the store returns an error
- **THEN** `{:ok, nil}` is returned and the error is logged

### Requirement: __durex__ key excluded from serialization

The `__durex__` key in state SHALL be automatically stripped before passing state to `serialize/1`.

#### Scenario: Serialize does not see __durex__ key
- **WHEN** the periodic sync fires and state contains `__durex__` bookkeeping
- **THEN** the map passed to `serialize/1` does not contain the `__durex__` key
