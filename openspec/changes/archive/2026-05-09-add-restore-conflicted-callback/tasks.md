## 1. Behavior And Restore Flow

- [x] 1.1 Add `restore_conflict_reason` type documentation to `Durex`.
- [x] 1.2 Add optional `restore_conflicted/3` callback to the `Durex` behavior.
- [x] 1.3 Inject a default no-op overridable `restore_conflicted/3` implementation from `use Durex`.
- [x] 1.4 Update `maybe_restore/2` to call `restore_conflicted/3` for missing checkpoints.
- [x] 1.5 Update `maybe_restore/2` to call `restore_conflicted/3` for version mismatches, invalid envelopes, and corrupted JSON.
- [x] 1.6 Update `maybe_restore/2` to call `restore_conflicted/3` after store read errors while preserving current warning and telemetry behavior.
- [x] 1.7 Validate callback return values so maps recover and `nil` preserves current behavior.

## 2. Checkpoint Decode Details

- [x] 2.1 Add `Durex.Checkpoint.decode_detailed/2` returning structured conflict reasons.
- [x] 2.2 Preserve existing `Durex.Checkpoint.decode/2` compatibility and tests.
- [x] 2.3 Preserve existing warning logs for version mismatch, invalid envelope, and corrupted JSON.

## 3. Tests

- [x] 3.1 Update behavior tests to include `restore_conflicted/3`.
- [x] 3.2 Add tests proving default `restore_conflicted/3` returns `nil` and can be overridden.
- [x] 3.3 Add detailed decode tests for valid payloads, missing input, version mismatch, invalid envelope, matching-version non-map data, and corrupted JSON.
- [x] 3.4 Add integration tests for callback recovery from missing checkpoints.
- [x] 3.5 Add integration tests for callback recovery from version mismatches.
- [x] 3.6 Add integration tests for callback recovery from invalid envelopes.
- [x] 3.7 Add integration tests for callback recovery from corrupted JSON.
- [x] 3.8 Add integration tests for callback recovery from store read errors.
- [x] 3.9 Add integration tests proving callback `nil` returns preserve `{:ok, nil}`.
- [x] 3.10 Add backward compatibility tests for modules without a custom callback override.
- [x] 3.11 Add integration tests proving non-map, non-nil callback returns raise `ArgumentError`.
- [x] 3.12 Add integration tests proving the callback receives the fully built key and `[]` opts for missing checkpoints, decode conflicts, and store read errors.
- [x] 3.13 Add telemetry tests proving recovered missing/decode conflicts still emit `[:durex, :restore, :ok]` with `found: false` and recovered store read errors still emit `[:durex, :restore, :failed]`.

## 4. Documentation

- [x] 4.1 Update README usage text to describe three required callbacks plus optional `restore_conflicted/3`.
- [x] 4.2 Add README example for `restore_conflicted/3`.
- [x] 4.3 Update README callback table with the callback contract and reason values.
- [x] 4.4 Update version mismatch/corruption restore documentation to mention optional recovery.
- [x] 4.5 Document that recovered missing/decode conflicts still emit restore-ok telemetry with `found: false`, while recovered store read errors still emit restore-failed telemetry.

## 5. Verification

- [x] 5.1 Run targeted tests for Durex behavior, checkpoint decode, and integration restore paths.
- [x] 5.2 Run `mix check` and fix any failures.
