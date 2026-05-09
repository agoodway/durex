## Requirements

### Requirement: use Durex macro injects handle_info for periodic sync

The `use Durex` macro SHALL inject a `handle_info(:__durex_sync__, state)` clause into the using module. This clause SHALL call `Durex.checkpoint/2` and schedule the next sync via `Process.send_after/3`.

#### Scenario: Periodic checkpoint fires after interval
- **WHEN** the interval elapses after `Durex.start_sync/2` is called
- **THEN** the GenServer receives `:__durex_sync__` and writes serialized state to the configured store

#### Scenario: Next sync is scheduled after each checkpoint
- **WHEN** a `:__durex_sync__` message is handled
- **THEN** a new `Process.send_after(self(), :__durex_sync__, interval)` is scheduled

### Requirement: use Durex defines behaviour callbacks

The `use Durex` macro SHALL define `@behaviour Durex` on the using module, requiring three callbacks: `serialize/1`, `deserialize/1`, and `checkpoint_key/1`. It SHALL also provide an optional overridable `restore_conflicted/3` callback.

#### Scenario: Module missing serialize callback
- **WHEN** a module uses `use Durex` without defining `serialize/1`
- **THEN** the compiler emits a warning about the missing callback

#### Scenario: Module implements all required callbacks
- **WHEN** a module uses `use Durex` and implements `serialize/1`, `deserialize/1`, and `checkpoint_key/1`
- **THEN** the module compiles without callback warnings

#### Scenario: Module omits restore conflict callback
- **WHEN** a module uses `use Durex` and does not define `restore_conflicted/3`
- **THEN** the default `restore_conflicted/3` implementation returns `nil`
- **AND** existing nil restore behavior is preserved

#### Scenario: Module overrides restore conflict callback
- **WHEN** a module uses `use Durex` and defines `restore_conflicted/3`
- **THEN** the module's callback is used when restore conflicts occur

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

`Durex.start_sync/2` SHALL read the provided module's generated `__durex_config__/0`, add a `__durex__` key to the state map containing interval and timer bookkeeping data, and schedule the first `:__durex_sync__` message.

#### Scenario: start_sync adds __durex__ key
- **WHEN** `Durex.start_sync(MyModule, state)` is called with a map state
- **THEN** the returned state contains a `__durex__` key with interval and timer metadata

#### Scenario: start_sync schedules first sync
- **WHEN** `Durex.start_sync(MyModule, state)` is called
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

`Durex.maybe_restore/2` SHALL build the key from the state, read from the store, and return either `{:ok, nil}` or `{:ok, deserialized_or_recovered_data}`. The user is responsible for merging returned data into their state.

#### Scenario: Checkpoint exists and version matches
- **WHEN** `Durex.maybe_restore(MyModule, state)` is called and a valid checkpoint exists
- **THEN** `{:ok, deserialized_data}` is returned where `deserialized_data` is the result of `deserialize/1`

#### Scenario: No checkpoint exists and callback returns nil
- **WHEN** `Durex.maybe_restore(MyModule, state)` is called and no checkpoint is stored
- **AND** `restore_conflicted(:missing_checkpoint, key, [])` returns `nil`
- **THEN** `{:ok, nil}` is returned

#### Scenario: No checkpoint exists and callback returns recovered data
- **WHEN** `Durex.maybe_restore(MyModule, state)` is called and no checkpoint is stored
- **AND** `restore_conflicted(:missing_checkpoint, key, [])` returns a map
- **THEN** `{:ok, recovered_data}` is returned
- **AND** restore telemetry is emitted as `[:durex, :restore, :ok]` with `found: false`

#### Scenario: Version mismatch invokes restore conflict callback
- **WHEN** `Durex.maybe_restore(MyModule, state)` is called and the stored version differs from the module's configured version
- **THEN** `restore_conflicted({:version_mismatch, expected, actual}, key, [])` is called
- **AND** the callback result controls whether `{:ok, recovered_data}` or `{:ok, nil}` is returned
- **AND** restore telemetry is emitted as `[:durex, :restore, :ok]` with `found: false`

#### Scenario: Invalid envelope invokes restore conflict callback
- **WHEN** `Durex.maybe_restore(MyModule, state)` is called and the stored checkpoint has an invalid envelope
- **THEN** `restore_conflicted({:invalid_envelope, decoded}, key, [])` is called
- **AND** the callback result controls whether `{:ok, recovered_data}` or `{:ok, nil}` is returned
- **AND** restore telemetry is emitted as `[:durex, :restore, :ok]` with `found: false`

#### Scenario: Corrupted JSON invokes restore conflict callback
- **WHEN** `Durex.maybe_restore(MyModule, state)` is called and the stored checkpoint cannot be decoded as JSON
- **THEN** `restore_conflicted({:corrupted_json, reason}, key, [])` is called
- **AND** the callback result controls whether `{:ok, recovered_data}` or `{:ok, nil}` is returned
- **AND** restore telemetry is emitted as `[:durex, :restore, :ok]` with `found: false`

#### Scenario: Store unavailable during restore invokes restore conflict callback
- **WHEN** `Durex.maybe_restore(MyModule, state)` is called and the store returns an error
- **THEN** the error is logged
- **AND** `restore_conflicted({:store_read_error, reason}, key, [])` is called
- **AND** the callback result controls whether `{:ok, recovered_data}` or `{:ok, nil}` is returned
- **AND** restore telemetry is emitted as `[:durex, :restore, :failed]`

#### Scenario: Restore conflict callback returns invalid value
- **WHEN** `restore_conflicted/3` returns a value that is neither a map nor `nil`
- **THEN** Durex raises an error identifying the invalid callback return

### Requirement: __durex__ key excluded from serialization

The `__durex__` key in state SHALL be automatically stripped before passing state to `serialize/1`.

#### Scenario: Serialize does not see __durex__ key
- **WHEN** the periodic sync fires and state contains `__durex__` bookkeeping
- **THEN** the map passed to `serialize/1` does not contain the `__durex__` key
