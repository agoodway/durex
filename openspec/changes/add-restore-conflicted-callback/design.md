## Context

The current restore path intentionally degrades safely. `Durex.maybe_restore/2` returns `{:ok, nil}` when a checkpoint is missing, stale due to version mismatch, malformed, corrupted, or unavailable because the store read failed. This keeps GenServers alive, but it prevents applications from implementing conflict-specific recovery.

For example, an application may want to rebuild state from a database when a checkpoint is missing, migrate from an older checkpoint format when versions differ, or initialize safe default state while recording that corruption occurred.

## Goals / Non-Goals

**Goals:**

- Add a restore conflict callback that can recover from any nil restore outcome.
- Preserve compatibility for existing Durex users that implement only the original callbacks.
- Preserve the existing `maybe_restore/2` return shape: `{:ok, map() | nil}`.
- Preserve the existing `Durex.Checkpoint.decode/2` behavior for external callers and tests.
- Provide structured reasons so callers can distinguish missing, stale, invalid, corrupted, and store-error cases.

**Non-Goals:**

- No change to the `maybe_restore/2` arity or public return shape.
- No automatic merge into GenServer state; callers remain responsible for merging restored maps.
- No new storage behavior callbacks.
- No checkpoint migration framework beyond exposing enough context for application-defined recovery.

## Decisions

### 1. Add optional `restore_conflicted/3`

The callback will be optional and default to `nil`:

```elixir
@type restore_conflict_reason ::
        :missing_checkpoint
        | {:version_mismatch, expected :: pos_integer(), actual :: term()}
        | {:invalid_envelope, term()}
        | {:corrupted_json, term()}
        | {:store_read_error, term()}

@callback restore_conflicted(restore_conflict_reason(), key :: String.t(), opts :: keyword()) :: map() | nil
@optional_callbacks restore_conflicted: 3
```

Modules that `use Durex` will receive a default overridable implementation:

```elixir
@impl Durex
def restore_conflicted(_reason, _key, _opts), do: nil

defoverridable restore_conflicted: 3
```

**Why**: Making the callback optional avoids a breaking change for existing GenServers. Returning `nil` preserves current behavior.

### 2. Pass reason, key, and opts

The callback arguments will be:

- `reason`: a structured restore conflict reason.
- `key`: the fully built Durex checkpoint key attempted during restore.
- `opts`: reserved extension point; initially `[]` because `maybe_restore/2` currently has no options parameter.

**Why**: The key is useful for logging and external recovery. The options argument gives the callback contract room to grow without adding a new arity later.

### 3. Keep `decode/2`, add `decode_detailed/2`

`Durex.Checkpoint.decode/2` will keep returning `{:ok, map() | nil}`. A new
`Durex.Checkpoint.decode_detailed/2` API will return:

```elixir
{:ok, data}
{:conflict, :missing_checkpoint}
{:conflict, {:version_mismatch, expected, actual}}
{:conflict, {:invalid_envelope, decoded}}
{:conflict, {:corrupted_json, reason}}
```

**Why**: The restore flow needs reasoned outcomes, but changing `decode/2` would break callers and existing tests.

### 4. Callback return handling

If `restore_conflicted/3` returns a map, `maybe_restore/2` will return `{:ok, map}`. If it returns `nil`, `maybe_restore/2` will return `{:ok, nil}`.

Non-map, non-nil return values should raise `ArgumentError` because they indicate an invalid callback implementation.

**Why**: This keeps the public restore contract simple and catches programmer errors early.

### 5. Telemetry remains compatible

The restore flow will preserve existing telemetry semantics unless implementation reveals a need for a new event. Missing and decode-conflict cases remain restore-ok outcomes with `found: false`; store read errors remain restore-failed outcomes.

**Why**: The callback augments recovery behavior but should not silently redefine existing telemetry meaning.

## Risks / Trade-offs

- **[Reason shape stability]** Once documented, reason tuples become part of the callback contract.
- **[Callback side effects]** Application-defined recovery may do work during GenServer initialization; documentation should keep examples simple and explicit.
- **[Telemetry ambiguity]** A callback may recover data after a `found: false` telemetry event. This is acceptable for compatibility but should be documented if needed.

## Migration Plan

Existing Durex users are unaffected. Modules without a custom `restore_conflicted/3` keep returning `{:ok, nil}` for all current nil restore outcomes.

Users can opt into recovery by defining:

```elixir
@impl Durex
def restore_conflicted(reason, key, _opts) do
  # return a replacement map or nil
end
```
