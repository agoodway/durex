# Inspector Review - add-tigris-store

**Reviewed:** 2026-05-08
**Reviewer:** inspector/review-update
**Verdict:** Ready to implement

## Summary

The change proposes a first-party `Durex.Store.Tigris` backend using Req and Tigris/S3-compatible object storage. The review found several spec and design gaps around sequencing, URL construction, raw response handling, optional dependencies, and TTL metadata semantics. All findings were resolved in the OpenSpec artifacts, including one user-guided TTL metadata decision.

**Counts:** Critical: 0 | Warning: 6 | Suggestion: 1

## Scope inspected

- Proposal: `openspec/changes/add-tigris-store/proposal.md`
- Design: `openspec/changes/add-tigris-store/design.md`
- Tasks: `openspec/changes/add-tigris-store/tasks.md`
- Deltas:
  - `openspec/changes/add-tigris-store/specs/tigris-store/spec.md`
- Canonical specs consulted: none
- Other active changes consulted: `openspec/changes/initial-design/proposal.md`

## Critical

_None._

## Warning

_None._

## Suggestion

_None._

## Patches applied

7 findings were patched. 6 findings were auto-patched. 1 finding was patched after user guidance. 0 findings were skipped.

### Auto-patched

1. **Document dependency on initial design** - `openspec/changes/add-tigris-store/proposal.md:3` -> Added an impact note that this change depends on `initial-design` landing first because that change introduces `Durex.Store`, `Durex.Store.Redis`, and the core checkpoint API. See `openspec/changes/add-tigris-store/proposal.md:29`.
2. **Specify optional config defaults** - `openspec/changes/add-tigris-store/specs/tigris-store/spec.md:4` -> Added a scenario requiring default endpoint `"https://t3.storage.dev"`, region `"auto"`, and no prefix when optional config is omitted. See `openspec/changes/add-tigris-store/specs/tigris-store/spec.md:14`.
3. **Add virtual-hosted URL requirements** - `openspec/changes/add-tigris-store/tasks.md:12` -> Added delta requirements for virtual-hosted object URLs, default and custom endpoints, invalid endpoints, and expanded URL-construction test coverage. See `openspec/changes/add-tigris-store/specs/tigris-store/spec.md:33` and `openspec/changes/add-tigris-store/tasks.md:23`.
4. **Define URL encoding for reserved key characters** - `openspec/changes/add-tigris-store/design.md:75` -> Added design and spec language requiring percent-encoding for reserved URL characters in Durex keys, plus test coverage. See `openspec/changes/add-tigris-store/design.md:85`, `openspec/changes/add-tigris-store/specs/tigris-store/spec.md:59`, and `openspec/changes/add-tigris-store/tasks.md:32`.
5. **Require raw body reads** - `openspec/changes/add-tigris-store/design.md:37` -> Added design, spec, and task coverage requiring Req response decoding to be disabled for reads so JSON-looking payloads remain raw binaries. See `openspec/changes/add-tigris-store/design.md:38`, `openspec/changes/add-tigris-store/specs/tigris-store/spec.md:29`, and `openspec/changes/add-tigris-store/tasks.md:15`.
6. **Document optional Req dependency behavior** - `openspec/changes/add-tigris-store/tasks.md:3` -> Added docs/tasks/spec coverage that Tigris users must add `:req`, and that unavailable Req returns `{:error, :req_not_available}`. See `openspec/changes/add-tigris-store/design.md:111`, `openspec/changes/add-tigris-store/specs/tigris-store/spec.md:18`, and `openspec/changes/add-tigris-store/tasks.md:40`.

### User-guided patches

1. **Define TTL metadata semantics** - `openspec/changes/add-tigris-store/design.md:88` -> Defined `x-amz-meta-durex-expires-at` with Unix UTC seconds and specified that missing or malformed expiration metadata is treated as non-expiring. User chose: treat malformed metadata as non-expiring. See `openspec/changes/add-tigris-store/design.md:92`, `openspec/changes/add-tigris-store/specs/tigris-store/spec.md:67`, and `openspec/changes/add-tigris-store/tasks.md:31`.

### Skipped

_None._

## Alignment notes

- **Other active changes:** No conflict found. The sequencing dependency on `initial-design` is now explicit in `openspec/changes/add-tigris-store/proposal.md:29`.
- **Canonical specs:** None exist under `openspec/specs/`; this change only adds the new `tigris-store` capability.
- **Codebase assumptions verified:** `Durex.Store` and `Durex.Store.Redis` exist in the current codebase, `Req` is not currently in `mix.exs`, and README currently documents Redis/custom store usage but not Tigris.

## What looks good

- The change preserves the existing `Durex.Store` behaviour and keeps Tigris as a backend-only addition.
- The design correctly keeps host applications responsible for infrastructure, secrets, and dependency/runtime configuration.
- The task list now covers implementation, edge-case tests, documentation, and verification for the major Tigris integration risks.
