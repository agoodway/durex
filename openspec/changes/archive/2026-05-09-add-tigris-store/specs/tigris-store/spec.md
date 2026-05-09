## ADDED Requirements

### Requirement: Tigris store uses configured bucket and credentials
`Durex.Store.Tigris` SHALL read its bucket, access key ID, secret access key, endpoint, region, optional prefix, and safe transport request options from `config :durex, Durex.Store.Tigris`.

#### Scenario: Required configuration is present
- **WHEN** `Durex.Store.Tigris.write/3`, `read/1`, or `delete/1` is called with a configured bucket and credentials
- **THEN** the store uses that configuration when building and signing the Tigris request

#### Scenario: Required configuration is missing
- **WHEN** `Durex.Store.Tigris.write/3`, `read/1`, or `delete/1` is called without a configured bucket, access key ID, or secret access key
- **THEN** the store returns `{:error, reason}` without raising an exception

#### Scenario: Optional configuration is omitted
- **WHEN** `Durex.Store.Tigris.write/3`, `read/1`, or `delete/1` is called without configured endpoint, region, or prefix
- **THEN** the store uses endpoint `"https://t3.storage.dev"`, region `"auto"`, and no object key prefix

#### Scenario: Req dependency is unavailable
- **WHEN** `Durex.Store.Tigris.write/3`, `read/1`, or `delete/1` is called and `Req` is not available at runtime
- **THEN** the store returns `{:error, :req_not_available}` without raising an exception

### Requirement: Tigris store signs requests with Req AWS SigV4
`Durex.Store.Tigris` SHALL use `Req` to perform Tigris object requests signed with AWS Signature Version 4 using service `s3`.

#### Scenario: Request is signed for Tigris
- **WHEN** the store sends a request to Tigris
- **THEN** the request is signed with AWS SigV4 using the configured access key ID, secret access key, region, and service `s3`

#### Scenario: Read returns raw binary body
- **WHEN** `Durex.Store.Tigris.read/1` receives an object body that looks like JSON or another decodable content type
- **THEN** the store returns the raw binary object body without Req response body decoding

### Requirement: Tigris store builds virtual-hosted object URLs
`Durex.Store.Tigris` SHALL build virtual-hosted object URLs by applying the configured bucket as a subdomain of the configured endpoint host and appending the normalized object key path.

#### Scenario: Default endpoint URL is built
- **WHEN** the configured bucket is `"my-bucket"`, the endpoint is omitted, and the key is `"durex:app:mod:k1"`
- **THEN** the store builds the object URL `https://my-bucket.t3.storage.dev/durex:app:mod:k1`

#### Scenario: Custom endpoint URL is built
- **WHEN** the configured bucket is `"my-bucket"`, endpoint is `"https://objects.example.com:8443"`, and the key is `"durex:app:mod:k1"`
- **THEN** the store builds the object URL `https://my-bucket.objects.example.com:8443/durex:app:mod:k1`

#### Scenario: Invalid endpoint URL is rejected
- **WHEN** the configured endpoint uses plain HTTP, includes a path, query string, fragment, userinfo, or lacks a scheme or host
- **THEN** the store returns `{:error, reason}` without raising an exception

### Requirement: Tigris store writes raw checkpoint payloads
`Durex.Store.Tigris.write/3` SHALL store the given binary payload as the raw object body at the object key derived from the Durex key and optional prefix.

#### Scenario: Write without prefix
- **WHEN** `Durex.Store.Tigris.write("durex:app:mod:k1", <<"json">>, [])` is called without a configured prefix
- **THEN** the store writes the payload to the object key `durex:app:mod:k1`

#### Scenario: Write with prefix
- **WHEN** `Durex.Store.Tigris.write("durex:app:mod:k1", <<"json">>, [])` is called with prefix `"checkpoints"`
- **THEN** the store writes the payload to the object key `checkpoints/durex:app:mod:k1`

#### Scenario: Write with reserved URL characters in key
- **WHEN** `Durex.Store.Tigris.write("durex:app:mod:k 1?#%", <<"json">>, [])` is called
- **THEN** the store preserves the logical object key while percent-encoding reserved characters in the request path so they cannot alter the URL query, fragment, or SigV4 canonical path

#### Scenario: Write returns error on request failure
- **WHEN** the Tigris write request fails or returns a non-success status
- **THEN** the store returns `{:error, reason}`

### Requirement: Tigris store emulates TTL with object metadata
`Durex.Store.Tigris.write/3` SHALL include `x-amz-meta-durex-expires-at` expiration metadata containing a Unix timestamp in UTC seconds when passed `ttl: seconds`, and `Durex.Store.Tigris.read/1` SHALL treat expired objects as missing.

#### Scenario: Write with TTL stores expiration metadata
- **WHEN** `Durex.Store.Tigris.write("durex:app:mod:k1", payload, ttl: 300)` is called
- **THEN** the store writes metadata containing an expiration timestamp approximately 300 seconds in the future

#### Scenario: Read expired object
- **WHEN** `Durex.Store.Tigris.read("durex:app:mod:k1")` reads an object whose expiration metadata is in the past
- **THEN** the store returns `{:ok, nil}`

#### Scenario: Read unexpired object
- **WHEN** `Durex.Store.Tigris.read("durex:app:mod:k1")` reads an object whose expiration metadata is absent or in the future
- **THEN** the store returns `{:ok, binary}` with the object body

#### Scenario: Read object with malformed expiration metadata
- **WHEN** `Durex.Store.Tigris.read("durex:app:mod:k1")` reads an object whose expiration metadata cannot be parsed as a Unix timestamp in UTC seconds
- **THEN** the store treats the object as non-expiring and returns `{:ok, binary}` with the object body

### Requirement: Tigris store returns nil for missing objects
`Durex.Store.Tigris.read/1` SHALL return `{:ok, nil}` when the requested object does not exist.

#### Scenario: Read missing object
- **WHEN** Tigris returns a missing-object response for the requested object key
- **THEN** `Durex.Store.Tigris.read/1` returns `{:ok, nil}`

### Requirement: Tigris store deletes objects idempotently
`Durex.Store.Tigris.delete/1` SHALL remove the object for the given key and SHALL treat missing objects as successfully deleted.

#### Scenario: Delete existing object
- **WHEN** `Durex.Store.Tigris.delete("durex:app:mod:k1")` is called and the object exists
- **THEN** the store deletes the object and returns `:ok`

#### Scenario: Delete missing object
- **WHEN** `Durex.Store.Tigris.delete("durex:app:mod:missing")` is called and the object does not exist
- **THEN** the store returns `:ok`

#### Scenario: Delete returns error on request failure
- **WHEN** the Tigris delete request fails with a non-success response other than missing object
- **THEN** the store returns `{:error, reason}`
