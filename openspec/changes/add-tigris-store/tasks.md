## 1. Dependency And Configuration

- [x] 1.1 Add `req` as an optional runtime dependency in `mix.exs`.
- [x] 1.2 Add commented Tigris configuration examples to `config/config.exs`.
- [x] 1.3 Decide and document required config keys: `:bucket`, `:access_key_id`, and `:secret_access_key`.

## 2. Tigris Store Implementation

- [x] 2.1 Create `Durex.Store.Tigris` implementing the `Durex.Store` behaviour.
- [x] 2.2 Implement config loading with defaults for `endpoint: "https://t3.storage.dev"`, `region: "auto"`, and `prefix: nil`.
- [x] 2.3 Implement object key normalization that preserves Durex keys and prepends an optional normalized prefix.
- [x] 2.4 Implement virtual-hosted Tigris URL construction for configured bucket and endpoint.
- [x] 2.5 Implement Req request construction with AWS SigV4 signing using service `s3`.
- [x] 2.6 Implement `write/3` with raw payload body upload and optional `x-amz-meta-durex-expires-at` Unix UTC seconds expiration metadata from `ttl`.
- [x] 2.7 Implement `read/1` with missing-object handling, expiration metadata checks, disabled response body decoding, and raw body return.
- [x] 2.8 Implement `delete/1` with idempotent missing-object handling.
- [x] 2.9 Ensure all request failures, unavailable optional dependencies, and invalid configuration paths return `{:error, reason}` without raising.

## 3. Tests

- [x] 3.1 Add unit tests for required and optional Tigris configuration handling.
- [x] 3.2 Add unit tests for object key prefix normalization.
- [x] 3.3 Add unit tests for virtual-hosted URL construction, including default endpoints, custom endpoints with ports, trailing slashes, and invalid path/query endpoints.
- [x] 3.4 Add unit tests or request stubs verifying Req AWS SigV4 options include service `s3` and configured credentials.
- [x] 3.5 Add tests for successful `write/3`, including TTL expiration metadata.
- [x] 3.6 Add tests for `read/1` returning `{:ok, nil}` for missing objects.
- [x] 3.7 Add tests for `read/1` returning `{:ok, nil}` for expired objects.
- [x] 3.8 Add tests for `read/1` returning `{:ok, binary}` for unexpired or non-expiring objects.
- [x] 3.9 Add tests for `delete/1` returning `:ok` for existing and missing objects.
- [x] 3.10 Add tests for non-success request responses returning `{:error, reason}`.
- [x] 3.11 Add tests for malformed expiration metadata being treated as non-expiring.
- [x] 3.12 Add tests for reserved URL characters in Durex keys and JSON-looking binary payloads remaining raw binaries on read.

## 4. Documentation

- [x] 4.1 Update README configuration examples for `Durex.Store.Tigris`.
- [x] 4.2 Document Tigris credential expectations and recommended runtime config usage.
- [x] 4.3 Document metadata TTL semantics and the need for lifecycle cleanup for high-churn workloads.
- [x] 4.4 Document when to choose Redis versus Tigris.
- [x] 4.5 Document that Tigris users must add `:req` to their application dependencies because Durex declares it optional.

## 5. Verification

- [x] 5.1 Run `mix format`.
- [x] 5.2 Run `mix check` and fix any failures.
