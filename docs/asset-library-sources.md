# Asset Library sources and provenance

## Openverse

Openverse is the first external catalog provider. The Flutter adapter accepts
only HTTPS provider URLs and stores the provider asset ID, landing URL, download
URL, thumbnail URL, creator, license, license URL, tags, and attribution. A
provider result is not treated as a user upload until the user saves it to the
project library.

- API: <https://api.openverse.org/v1/>
- Project: <https://openverse.org/>
- License guidance: <https://docs.openverse.org/>

The application does not scrape or copy a Canva catalog. It does not claim that
an Openverse license removes the user's obligation to check the individual
asset's terms. The details view must keep the source/creator/license visible;
exports should preserve attribution where the selected license requires it.
External provider results without a license cannot be saved into the project
catalog; the database enforces the same rule as the client.

## Provider proxy

Production Web builds may use `supabase/functions/asset-library`. The proxy
requires an authenticated-user JWT (the public anon role is rejected) and
allowlists only the Openverse images and audio API paths. It
bounds query/page size, rejects unsafe redirects, limits the response body, and
uses an exact `ALLOWED_ORIGINS` list. Provider credentials, if a future provider
requires them, belong in Edge Function secrets and never in Flutter code.

Enable it only after the function is deployed:

```text
flutter build web --dart-define=ASSET_LIBRARY_PROVIDER_PROXY=true
```

## Project uploads

Uploaded binaries are kept in local storage and/or the `assets` Storage bucket.
Managed catalog objects use the project-scoped `images`, `files`, `audio`,
`video`, or `library` namespaces with a UUID-prefixed filename; collaboration,
AI, and drawing-paper paths are not catalog-owned. Uploads use `upsert: false`
and Storage RLS rejects non-UUID library paths and library-object updates. The
shared `assets` bucket is public for existing canvas compatibility, so a public
URL is not a confidentiality boundary; use a private bucket and signed URLs if
private uploads become a requirement. Postgres, document JSON, and CRDT operations contain
metadata and durable references only. Data-URI previews are transient and are removed before local
catalog serialization, remote catalog upsert, document manifest mapping, and
canvas node insertion.

Before a binary-backed catalog item is saved, the client checks its size,
extension/MIME, magic bytes, checksum, project-scoped Storage path, and the
512 MB limit. Server-side triggers and RLS remain authoritative; client checks
are not a substitute for them. Deletion removes Storage before the catalog row;
failed or ambiguous operations retain a project-scoped tombstone for retry, and
aged UUID objects can be reconciled by the orphan cleanup job.

## Verification

The committed database integration checks cover scope isolation, quota
reservation/release, Storage path rules, RLS, and Storage-API-only deletion:

```text
supabase test db --local supabase/tests/asset_library.sql
```

The linked project test session currently reports `pgtap` as present but cannot
call `plan(integer)`, so `supabase test db --linked` is not an executable gate
there. Keep the linked check as an environment follow-up and use the local
pgTAP run plus the authenticated Storage HTTP check for deployed-schema
verification.

The optional Storage HTTP check exercises a real bucket upload, no-overwrite
behavior, catalog pairing, and Storage-API cleanup. Run it only against an
isolated test project with a service-role key supplied through the environment:

```text
ASSET_LIBRARY_INTEGRATION=1 \
SUPABASE_URL=https://your-test-project.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=... \
flutter test --no-pub test/supabase/asset_library_storage_integration_test.dart
```

The proxy helper suite is runtime-independent and can be run without a
production credential:

```text
npx --yes deno test supabase/functions/asset-library/index_test.ts
```

After deployment, verify that `asset-library` is `ACTIVE` with JWT verification
enabled. Requests using the public anon role must receive `401`; requests from
an origin outside the configured `ALLOWED_ORIGINS` list must receive `403`.
The RLS hardening migration also removes the asset-library-specific performance
advisor findings. The security advisor still reports the deliberately
authenticated, scope-checked `record_asset_library_usage` RPC and may classify
`TO authenticated` policies under its generic anonymous-access warning; verify
`pg_policies.roles` and the HTTP RLS checks before changing those policies.
