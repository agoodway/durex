## Why

Durex currently ships with Redis as its only first-party store, which works well for hot ephemeral recovery but does not cover durable object-backed checkpointing. Tigris provides an S3-compatible object store that fits production checkpoint persistence without requiring Durex to own a connection process or supervisor.

## What Changes

- Add a production-supported `Durex.Store.Tigris` backend.
- Use `Req` with AWS Signature Version 4 signing instead of an S3 SDK.
- Store checkpoint payloads as raw object bodies in a configured Tigris bucket.
- Support an optional object key prefix for bucket organization.
- Emulate checkpoint TTL by writing expiration metadata and treating expired objects as missing on read.
- Document Tigris configuration, credential expectations, and TTL cleanup behavior.

## Capabilities

### New Capabilities
- `tigris-store`: First-party Tigris object storage backend for Durex checkpoints.

### Modified Capabilities
- None.

## Impact

- Adds `Durex.Store.Tigris` under `lib/durex/store/`.
- Adds `Req` as an optional runtime dependency for the Tigris store.
- Adds tests for Tigris request construction, missing-object handling, TTL metadata behavior, and delete semantics.
- Updates README/config examples to show Tigris usage.
- Does not change the `Durex.Store` behaviour or Durex core checkpoint API.
- Depends on the active `initial-design` change landing first because it introduces `Durex.Store`, `Durex.Store.Redis`, and the core checkpoint API this backend extends.
