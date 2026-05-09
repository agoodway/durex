## MODIFIED Requirements

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
