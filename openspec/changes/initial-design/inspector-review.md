# Inspector Review — initial-design

**Reviewed:** 2026-05-02
**Reviewer:** inspector/review-update
**Verdict:** Ready to implement

## Summary

This change proposes the initial Durex package design: a macro-based GenServer checkpointing API, pluggable store behaviour, Redis backend, key construction, JSON checkpoint encoding, and graceful degradation. The quick review found several specification ambiguities that would have blocked implementation if left unresolved. All review findings were patched in the OpenSpec artifacts.

**Counts:** Critical: 1 · Warning: 5 · Suggestion: 0

## Scope inspected

- Proposal: `openspec/changes/initial-design/proposal.md`
- Design: `openspec/changes/initial-design/design.md`
- Tasks: `openspec/changes/initial-design/tasks.md`
- Deltas: `openspec/changes/initial-design/specs/checkpoint-core/spec.md`, `openspec/changes/initial-design/specs/store-behaviour/spec.md`, `openspec/changes/initial-design/specs/genserver-macro/spec.md`
- Canonical specs consulted: none found under `openspec/specs/`
- Other active changes consulted: none found under `openspec/changes/`
- Git state: unavailable because `/Users/tbrewer/projects/goodway/durex` is not a Git repository

## Critical

_None._

## Warning

_None._

## Suggestion

_None._

## Patches applied

6 findings were patched. 5 findings were patched after user guidance. 0 findings were skipped.

### Auto-patched

1. **Document README work** — `openspec/changes/initial-design/tasks.md:44` → Added a documentation task covering installation, configuration, GenServer usage, callbacks, Redis ownership, map-state constraint, and the reserved `__durex__` key.

### User-guided patches

1. **Normalize key-builder arity** — `openspec/changes/initial-design/specs/checkpoint-core/spec.md:5` → Changed the key builder requirement from `Durex.Key.build/3` to `Durex.Key.build/2` and aligned the proposal with `build/2` (user chose: use `build/2`).
2. **Define runtime config ownership** — `openspec/changes/initial-design/design.md:43` → Added generated `__durex_config__/0` as the runtime source for `store`, `interval`, `ttl`, and `version`; limited `__durex__` state to timer bookkeeping (user chose: generated config function).
3. **Resolve module key formatting** — `openspec/changes/initial-design/design.md:64` → Specified module segments are underscored, downcased, and dot-separated; updated the key example and tests task (user chose: underscore modules).
4. **Make `Durex.start_sync/1` implementable** — `openspec/changes/initial-design/specs/genserver-macro/spec.md:45` → Defined `Durex.start_sync/1` as a macro that expands in the caller module and reads that module's generated config (user chose: keep `Durex.start_sync/1`).
5. **Add core delete API** — `openspec/changes/initial-design/proposal.md:9` → Added `Durex.delete/2` to the public API, checkpoint-core requirements, and implementation/test tasks (user chose: add `Durex.delete/2`).

### Skipped

_None._

## Alignment notes

- **Other active changes:** No other active changes were found in this workspace.
- **Canonical specs:** No canonical specs were found for the touched capabilities, so there is no canonical conflict to report.
- **Codebase assumptions verified:** The current codebase is still the generated package scaffold, with `lib/durex.ex` and `test/durex_test.exs` not yet implementing the proposed design. This is expected for an initial design change, and the tasks now cover the required implementation and documentation work.

## What looks good

- The change cleanly separates macro integration, store behaviour, and checkpoint encoding into separate capabilities.
- Restore-on-init and terminate checkpointing are explicit, which keeps GenServer lifecycle behavior understandable.
- The store behaviour remains a simple raw-binary interface, keeping serialization and versioning in Durex core.
- Graceful degradation is specified consistently for write, read, and the newly added delete flow.
