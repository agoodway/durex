# Inspector Review: add-restore-conflicted-callback

## Verdict

Ready.

The `initial-design` dependency has been synced into canonical specs and archived, so this change now modifies existing `checkpoint-core` and `genserver-macro` specs cleanly.

## Critical Findings

None.

## Warning Findings

None.

## Suggestion Findings

None.

## Patches applied

11 patch entries were applied, covering 7 auto-patchable findings. 1 finding was patched after user guidance. 0 findings remain unresolved.

### Auto-patched

1. **Missing invalid callback return test task** — `openspec/changes/add-restore-conflicted-callback/tasks.md:17` -> added task 3.11 requiring `ArgumentError` coverage for non-map, non-nil `restore_conflicted/3` returns.

2. **Missing callback argument test task** — `openspec/changes/add-restore-conflicted-callback/tasks.md:21` -> added task 3.12 requiring assertions for the fully built key and `[]` opts across conflict paths.

3. **Missing telemetry verification task** — `openspec/changes/add-restore-conflicted-callback/design.md:85` -> added task 3.13 requiring telemetry assertions for recovered missing/decode conflicts and recovered store read errors.

4. **Detailed decoder invalid data classification gap** — `lib/durex/checkpoint.ex:58` -> added OpenSpec coverage in `openspec/changes/add-restore-conflicted-callback/specs/checkpoint-core/spec.md:63` for matching-version non-map data returning `{:invalid_envelope, decoded}`.

5. **Detailed decode API references were generic** — `openspec/changes/add-restore-conflicted-callback/specs/checkpoint-core/spec.md:5` -> replaced generic “detailed decode API” references with `Durex.Checkpoint.decode_detailed/2`.

6. **Telemetry semantics under recovery were implicit** — `openspec/changes/add-restore-conflicted-callback/specs/genserver-macro/spec.md:37` -> added restore telemetry expectations for missing checkpoint recovery.

7. **Telemetry semantics under decode conflicts were implicit** — `openspec/changes/add-restore-conflicted-callback/specs/genserver-macro/spec.md:43` -> added restore telemetry expectations for version mismatch, invalid envelope, and corrupted JSON conflicts.

8. **Telemetry semantics under store read recovery were implicit** — `openspec/changes/add-restore-conflicted-callback/specs/genserver-macro/spec.md:59` -> added restore-failed telemetry expectation for store read errors even when recovery returns data.

9. **No canonical checkpoint-core spec** — `openspec/changes/add-restore-conflicted-callback/specs/checkpoint-core/spec.md:1` -> synced `initial-design` into `openspec/specs/checkpoint-core/spec.md` and archived `initial-design`.

10. **No canonical genserver-macro spec** — `openspec/changes/add-restore-conflicted-callback/specs/genserver-macro/spec.md:1` -> synced `initial-design` into `openspec/specs/genserver-macro/spec.md` and archived `initial-design`.

11. **Version metadata wording conflict** — `openspec/changes/add-restore-conflicted-callback/specs/checkpoint-core/spec.md:5` -> aligned canonical and change specs around the implemented `"v"`/`"d"` checkpoint envelope.

### User-guided patches

1. **Detailed decode API was unnamed** — `openspec/changes/add-restore-conflicted-callback/design.md:65` -> named the API `Durex.Checkpoint.decode_detailed/2` in the design, specs, and task list. User chose: `decode_detailed/2`.

### Skipped

None.
