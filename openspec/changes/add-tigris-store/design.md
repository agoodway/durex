## Context

Durex currently has a minimal `Durex.Store` behaviour and one first-party Redis backend. The core checkpoint pipeline already owns serialization, versioning, payload size limits, graceful degradation, and key construction; store modules are byte pipes that implement `write/3`, `read/1`, and `delete/1`.

Tigris is S3-compatible object storage. It can provide durable checkpoint persistence while preserving Durex's current design constraint that host applications own infrastructure configuration and Durex does not start supervisors or connection processes.

## Goals / Non-Goals

**Goals:**
- Add `Durex.Store.Tigris` as a production-supported first-party store backend.
- Use `Req` directly with AWS Signature Version 4 signing.
- Default to Tigris endpoint `https://t3.storage.dev` and region `auto`.
- Support a required bucket and optional object key prefix.
- Preserve raw binary store semantics: Durex core remains responsible for checkpoint encoding and decoding.
- Emulate TTL by storing expiration metadata and treating expired objects as missing on read.
- Keep store failures explicit at the store layer and gracefully handled by Durex core.

**Non-Goals:**
- No generic S3 adapter abstraction in this change.
- No bucket creation, object listing, lifecycle policy management, or migration tooling.
- No Durex-owned HTTP pool, supervisor, or credential refresh process.
- No changes to `Durex.Store` callbacks or Durex core public API.
- No support for AssumeRole, STS, or temporary session tokens unless Req SigV4 and Tigris support are extended in a future change.

## Decisions

### 1. Name the backend `Durex.Store.Tigris`

The backend will be Tigris-specific instead of a generic `Durex.Store.S3`.

**Why**: The production target is Tigris, not arbitrary S3-compatible storage. A Tigris-specific module can provide correct defaults (`https://t3.storage.dev`, region `auto`) and documentation without implying broader compatibility guarantees.

**Alternative considered**: `Durex.Store.S3`. Rejected because it would either need broader provider compatibility commitments or a more generic configuration surface than this change needs.

### 2. Use Req with AWS SigV4

`Durex.Store.Tigris` will issue plain HTTP `PUT`, `GET`, and `DELETE` requests using `Req` and its `:aws_sigv4` option with `service: "s3"`.
`GET` requests will disable body decoding so the store always returns the raw binary object body expected by the `Durex.Store` behaviour.

**Why**: Durex only needs single-object operations. Using Req avoids pulling in a full S3 SDK while still relying on a maintained SigV4 implementation.

**Alternative considered**: `ex_aws_s3`. Rejected because the requested implementation is Req-based and the store does not need SDK-level features like bucket listing or multipart upload.

### 3. Keep credentials and endpoint in application config

The store will read configuration from `config :durex, Durex.Store.Tigris`. Required configuration is `:bucket`, `:access_key_id`, and `:secret_access_key`. Optional configuration is `:prefix`, `:endpoint`, `:region`, and safe transport `:req_options`.

Defaults:

```elixir
endpoint: "https://t3.storage.dev"
region: "auto"
prefix: nil
```

**Why**: This matches existing Redis configuration ownership: Durex reads configuration, but the host application owns secrets and runtime configuration. Production apps can source values from environment variables in their own runtime config.

**Alternative considered**: Reading environment variables inside the store. Rejected because library code should not hard-code runtime secret lookup policy for host applications.

### 4. Use virtual-hosted object URLs

Object URLs will be built as:

```text
https://{bucket}.t3.storage.dev/{prefix}/{durex-key}
```

When a custom endpoint is configured, the bucket will be applied as a subdomain of that endpoint host.
Supported endpoints must be absolute `https` URLs with scheme, host, and optional port only; endpoints with plain HTTP, path, query, fragment, or userinfo are invalid configuration.

**Why**: Tigris examples use virtual addressing. Keeping the Durex key intact avoids coupling `Durex.Store.Tigris` to the internal structure of `Durex.Key` output.

**Alternative considered**: Path-style URLs such as `https://t3.storage.dev/{bucket}/{key}`. Rejected because virtual-hosted style is the Tigris-documented S3 addressing style.

### 5. Preserve Durex keys and only prepend optional prefix

The object key will be the Durex key, optionally prefixed with a normalized prefix:

```text
without prefix: durex:my_app:my_app.session_server:session_123
with prefix:    checkpoints/durex:my_app:my_app.session_server:session_123
```

**Why**: `Durex.Key` already owns namespacing. The store should not parse or reshape key segments.
The final object path will percent-encode each key path segment so reserved URL characters in Durex keys cannot alter the request path, query, or SigV4 canonical request. `/` characters introduced by the configured prefix remain path separators; reserved characters inside the Durex key itself are encoded as object-key bytes.

**Alternative considered**: Convert colon-delimited keys to slash paths. Rejected because it duplicates key semantics and creates provider-specific key behavior.

### 6. Emulate TTL with metadata

When `write/3` receives `ttl: seconds`, the store will include an object metadata header containing the expiration timestamp. `read/1` will inspect the returned metadata and return `{:ok, nil}` when the checkpoint has expired.
The metadata header will be `x-amz-meta-durex-expires-at`, and its value will be a Unix timestamp in UTC seconds. Missing or malformed expiration metadata is treated as non-expiring so a metadata parse problem does not hide an otherwise readable checkpoint.

**Why**: Tigris/S3 object storage does not provide Redis-style per-object TTL semantics through the simple object API. Metadata TTL preserves Durex behavior without wrapping the raw payload.

**Alternative considered**: Ignore TTL. Rejected because Durex users reasonably expect `ttl` to affect checkpoint visibility for first-party stores.

**Alternative considered**: Store an S3-specific envelope in the object body. Rejected because store modules should preserve raw binary payloads and Durex core owns envelopes.

## Risks / Trade-offs

- **[Expired objects remain stored]** -> Reads treat expired checkpoints as missing; documentation should recommend Tigris lifecycle cleanup for high-churn workloads.
- **[Higher latency than Redis]** -> Position Tigris as durable object-backed checkpointing, not a low-latency cache replacement.
- **[Clock skew affects TTL checks]** -> Use UTC seconds and keep TTL behavior best-effort, consistent with Durex checkpointing guarantees.
- **[Manual URL construction must match SigV4 canonicalization]** -> Keep URL building small, deterministic, and covered by tests around request behavior.
- **[Credential misconfiguration causes runtime failures]** -> Return `{:error, reason}` from the store and rely on Durex core graceful degradation.

## Migration Plan

Existing Redis users are unaffected. Host applications can opt into Tigris by adding the optional Req dependency through Durex, configuring `Durex.Store.Tigris`, and changing their `use Durex, store: ...` option for selected GenServers.
Because `Req` is optional, applications that use `Durex.Store.Tigris` must include `:req` in their own dependencies; if `Req` is unavailable, the store returns `{:error, :req_not_available}` instead of raising. Advanced `:req_options` are limited to safe transport options so callers cannot override request URLs, methods, signing, headers, or bodies.

Rollback is configuration-only for adopters: switch the `store:` option back to `Durex.Store.Redis` or another store and deploy. Existing Tigris objects can be deleted manually or left to lifecycle cleanup.

## Open Questions

- Should future versions support temporary session tokens if Tigris adds support?
- Should Durex eventually expose shared helpers for HTTP object stores if more object backends are added?
