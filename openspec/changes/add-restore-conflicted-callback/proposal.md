## Why

`Durex.maybe_restore/2` currently collapses all unusable restore outcomes to `{:ok, nil}`. That is safe for graceful degradation, but host GenServers have no structured opportunity to recover from known restore conflicts, fall back to another source of truth, or initialize replacement state when a checkpoint is missing, stale, corrupt, invalid, or temporarily unreadable.

## What Changes

- Add an optional `Durex.restore_conflicted/3` callback for modules that `use Durex`.
- Invoke the callback whenever `maybe_restore/2` would otherwise return `{:ok, nil}`.
- Pass a structured reason, the fully built checkpoint key, and an options keyword list to the callback.
- Preserve backward compatibility by injecting a default no-op implementation that returns `nil`.
- Add detailed checkpoint decode outcomes for internal restore handling while preserving the existing `Durex.Checkpoint.decode/2` return shape.
- Document the callback contract, reason values, and return behavior.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `genserver-macro`: Adds optional restore conflict recovery callback behavior to the Durex macro and restore flow.
- `checkpoint-core`: Adds structured decode conflict reasons for restore conflict handling while keeping existing decode compatibility.

## Impact

- Updates `Durex` behavior docs and macro injection in `lib/durex.ex`.
- Updates restore flow in `Durex.maybe_restore/2`.
- Adds a detailed decode API in `lib/durex/checkpoint.ex` without breaking `decode/2`.
- Adds tests for callback behavior, conflict reasons, restore fallback outcomes, and backward compatibility.
- Updates README callback guidance and OpenSpec capability specs.
