## Requirements

### Requirement: JSON encoding with per-module versioning

Durex core SHALL JSON-encode the serialized map in an envelope with a `"v"` version field set to the module's configured version number and a `"d"` data field containing the serialized state map. The compatibility decode API SHALL return `{:ok, nil}` for version mismatches, while `Durex.Checkpoint.decode_detailed/2` SHALL return a structured version mismatch conflict reason.

#### Scenario: Version embedded in payload
- **WHEN** state is checkpointed for a module with `version: 2`
- **THEN** the JSON payload contains `"v": 2`
- **AND** the serialized state is stored under the `"d"` field

#### Scenario: Version mismatch on compatibility decode
- **WHEN** a stored payload has `"v": 1` but the module declares `version: 2`
- **THEN** `Durex.Checkpoint.decode/2` returns `{:ok, nil}`

#### Scenario: Version mismatch on detailed decode
- **WHEN** a stored payload has `"v": 1` but the module declares `version: 2`
- **THEN** `Durex.Checkpoint.decode_detailed/2` returns `{:conflict, {:version_mismatch, 2, 1}}`

#### Scenario: Missing version field in stored data
- **WHEN** a stored payload lacks `"v"` version metadata
- **THEN** `Durex.Checkpoint.decode/2` returns `{:ok, nil}`
- **AND** `Durex.Checkpoint.decode_detailed/2` returns `{:conflict, {:invalid_envelope, decoded}}`

### Requirement: Graceful degradation on all store operations

All store interactions (write, read, delete) SHALL be wrapped by Durex core. Any `{:error, reason}` from the store SHALL be logged and converted to a safe return value (`:ok` for writes/deletes). Restore reads SHALL call `restore_conflicted({:store_read_error, reason}, key, [])` before returning `{:ok, nil}` when recovery is not provided.

#### Scenario: Write fails gracefully
- **WHEN** the store returns `{:error, :connection_refused}` during checkpoint
- **THEN** a warning is logged and `:ok` is returned to the caller

#### Scenario: Read fails gracefully without recovery
- **WHEN** the store returns `{:error, :timeout}` during restore
- **AND** `restore_conflicted({:store_read_error, :timeout}, key, [])` returns `nil`
- **THEN** a warning is logged and `{:ok, nil}` is returned

#### Scenario: Read fails gracefully with recovery
- **WHEN** the store returns `{:error, :timeout}` during restore
- **AND** `restore_conflicted({:store_read_error, :timeout}, key, [])` returns a map
- **THEN** a warning is logged and `{:ok, recovered_data}` is returned

#### Scenario: Delete fails gracefully
- **WHEN** the store returns `{:error, reason}` during delete
- **THEN** a warning is logged and `:ok` is returned

### Requirement: JSON decode handles invalid data

If the stored binary is not valid JSON, Durex core SHALL log a warning. The compatibility decode API SHALL return `{:ok, nil}`, while `Durex.Checkpoint.decode_detailed/2` SHALL return a structured corrupted JSON conflict reason.

#### Scenario: Corrupted JSON in compatibility decode
- **WHEN** a read returns a binary that fails JSON parsing
- **THEN** `Durex.Checkpoint.decode/2` returns `{:ok, nil}` and a warning is logged

#### Scenario: Corrupted JSON in detailed decode
- **WHEN** a read returns a binary that fails JSON parsing
- **THEN** `Durex.Checkpoint.decode_detailed/2` returns `{:conflict, {:corrupted_json, reason}}` and a warning is logged

#### Scenario: Invalid envelope in detailed decode
- **WHEN** a read returns JSON that does not match the checkpoint envelope
- **THEN** `Durex.Checkpoint.decode_detailed/2` returns `{:conflict, {:invalid_envelope, decoded}}` and a warning is logged

#### Scenario: Matching version with invalid data envelope in detailed decode
- **WHEN** a read returns JSON with the expected version but a non-map data field
- **THEN** `Durex.Checkpoint.decode_detailed/2` returns `{:conflict, {:invalid_envelope, decoded}}` and a warning is logged

#### Scenario: Missing checkpoint in detailed decode
- **WHEN** `Durex.Checkpoint.decode_detailed/2` receives `nil`
- **THEN** it returns `{:conflict, :missing_checkpoint}`
