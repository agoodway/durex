## ADDED Requirements

### Requirement: Key builder constructs namespaced keys

`Durex.Key.build/2` SHALL construct keys in the format `durex:{app}:{module}:{user_key}` where `app` comes from `config :durex, :app_name`, `module` is the using module split into segments, underscored, downcased, and dot-separated, and `user_key` is from `checkpoint_key/1`.

#### Scenario: Key built from config and module
- **WHEN** `Durex.Key.build(MyApp.SessionServer, "session_123")` is called with app_name `:my_app`
- **THEN** the key `"durex:my_app:my_app.session_server:session_123"` is returned

#### Scenario: Missing app_name config
- **WHEN** `:app_name` is not configured
- **THEN** a compile-time or runtime error indicates the missing config

### Requirement: JSON encoding with per-module versioning

Durex core SHALL JSON-encode the serialized map and include a `_durex_version` field set to the module's configured version number.

#### Scenario: Version embedded in payload
- **WHEN** state is checkpointed for a module with `version: 2`
- **THEN** the JSON payload contains `"_durex_version": 2`

#### Scenario: Version mismatch on decode
- **WHEN** a stored payload has `_durex_version: 1` but the module declares `version: 2`
- **THEN** decoding returns `nil` (stale checkpoint discarded)

#### Scenario: Missing version field in stored data
- **WHEN** a stored payload lacks `_durex_version`
- **THEN** decoding returns `nil`

### Requirement: Payload size limit

Durex core SHALL enforce a maximum payload size (default 1MB). Payloads exceeding this limit SHALL be skipped with a warning log.

#### Scenario: Payload within limit
- **WHEN** JSON-encoded state is under 1MB
- **THEN** it is written to the store

#### Scenario: Payload exceeds limit
- **WHEN** JSON-encoded state exceeds 1MB
- **THEN** the write is skipped, a warning is logged, and `:ok` is returned

#### Scenario: Custom max payload size
- **WHEN** `config :durex, :max_payload_bytes, 2_097_152` is set
- **THEN** the 2MB limit is used instead of the default

### Requirement: Graceful degradation on all store operations

All store interactions (write, read, delete) SHALL be wrapped by Durex core. Any `{:error, reason}` from the store SHALL be logged and converted to a safe return value (`:ok` for writes/deletes, `{:ok, nil}` for reads).

#### Scenario: Write fails gracefully
- **WHEN** the store returns `{:error, :connection_refused}` during checkpoint
- **THEN** a warning is logged and `:ok` is returned to the caller

#### Scenario: Read fails gracefully
- **WHEN** the store returns `{:error, :timeout}` during restore
- **THEN** a warning is logged and `{:ok, nil}` is returned

#### Scenario: Delete fails gracefully
- **WHEN** the store returns `{:error, reason}` during delete
- **THEN** a warning is logged and `:ok` is returned

### Requirement: Durex.delete removes stored checkpoints

`Durex.delete/2` SHALL build the checkpoint key from the module and state, call the configured store's `delete/1`, and always return `:ok`.

#### Scenario: Stored checkpoint deleted
- **WHEN** `Durex.delete(MyModule, state)` is called and the checkpoint key exists
- **THEN** the key is removed from the configured store and `:ok` is returned

#### Scenario: Stored checkpoint missing during delete
- **WHEN** `Durex.delete(MyModule, state)` is called and the checkpoint key does not exist
- **THEN** `:ok` is returned

### Requirement: JSON decode handles invalid data

If the stored binary is not valid JSON, Durex core SHALL log a warning and return `{:ok, nil}`.

#### Scenario: Corrupted JSON in store
- **WHEN** a read returns a binary that fails JSON parsing
- **THEN** `{:ok, nil}` is returned and a warning is logged
