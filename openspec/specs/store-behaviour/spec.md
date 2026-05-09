## Requirements

### Requirement: Store behaviour defines write/read/delete callbacks

The `Durex.Store` behaviour SHALL define three callbacks: `write/3`, `read/1`, and `delete/1`. Stores operate on raw binaries (not maps).

#### Scenario: Store implementation satisfies behaviour
- **WHEN** a module implements `@behaviour Durex.Store` with `write/3`, `read/1`, and `delete/1`
- **THEN** the module compiles without missing callback warnings

### Requirement: write callback stores binary payload with options

`write(key, payload, opts)` SHALL store the binary payload at the given key. The `opts` keyword list MAY contain `:ttl` (seconds). Stores that support TTL SHALL apply it. Returns `:ok` or `{:error, reason}`.

#### Scenario: Write with TTL on Redis
- **WHEN** `write("durex:app:mod:k1", <<json>>, ttl: 300)` is called on Redis store
- **THEN** the key is set with a 300-second expiry

#### Scenario: Write returns error on failure
- **WHEN** the underlying store connection fails
- **THEN** `{:error, reason}` is returned

### Requirement: read callback returns binary or nil

`read(key)` SHALL return `{:ok, binary}` when the key exists, `{:ok, nil}` when it does not, or `{:error, reason}` on failure.

#### Scenario: Read existing key
- **WHEN** `read("durex:app:mod:k1")` is called and the key exists
- **THEN** `{:ok, <<stored_binary>>}` is returned

#### Scenario: Read missing key
- **WHEN** `read("durex:app:mod:k1")` is called and the key does not exist
- **THEN** `{:ok, nil}` is returned

#### Scenario: Read returns error on connection failure
- **WHEN** the store connection is unavailable
- **THEN** `{:error, reason}` is returned

### Requirement: delete callback removes key

`delete(key)` SHALL remove the key from the store. Returns `:ok` or `{:error, reason}`. Deleting a non-existent key SHALL return `:ok`.

#### Scenario: Delete existing key
- **WHEN** `delete("durex:app:mod:k1")` is called
- **THEN** the key is removed and `:ok` is returned

#### Scenario: Delete non-existent key
- **WHEN** `delete("durex:app:mod:missing")` is called
- **THEN** `:ok` is returned

### Requirement: Redis store uses configured named connection

`Durex.Store.Redis` SHALL use a named Redix connection configured via `config :durex, Durex.Store.Redis, connection: MyApp.Redis`.

#### Scenario: Redis store reads connection from config
- **WHEN** `Durex.Store.Redis.read(key)` is called
- **THEN** it executes the command against the configured named Redix process

#### Scenario: Redis connection not started
- **WHEN** the configured Redix process is not running
- **THEN** `{:error, reason}` is returned (not a crash)
