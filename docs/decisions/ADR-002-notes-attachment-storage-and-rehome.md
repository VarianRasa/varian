# ADR-002: Store Notes Attachments in Scoped Private Storage

## Status

Accepted for implementation. The decision authorizes local source, test, Edge Function, and additive migration-file changes only. It does not authorize remote migrations, deployments, or data changes.

## Date

2026-10-21

## Context

Notes supports private and project-shared records, encrypted offline access, and scope rehoming when a project is deleted. Attachments need to follow the same access boundary as their note. The existing `assets` bucket is project-only and is shared by unrelated features, so it cannot safely represent private Notes files.

PostgreSQL can update Notes metadata transactionally, but it cannot atomically move bytes in Supabase Storage. A database trigger that changes attachment scope before copying bytes can strand or expose an object. Synchronous client-only copying also loses progress when the client disconnects.

The user approved the embed syntax `![[attachment:<uuid>]]`, encrypted offline caching under the Notes key, and rehoming metadata and bytes with Notes. The user selected a persistent pending workflow with a server-side worker that retries failures and delays project deletion until rehoming completes.

## Decision

1. Store attachment metadata in a Notes-specific table and bytes in a dedicated private `workspace-note-assets` bucket. Do not broaden the existing `assets` bucket. Private object paths bind to the owner; project object paths bind to the project. Every read and write checks current Notes scope and project permissions at the server boundary.
2. Accept only PNG, JPEG, GIF, WebP, and PDF. Enforce a 25 MiB per-file ceiling and verify file signatures before storing or rendering. Markdown can reference only a stable attachment UUID in the same scope. Signed URLs are transient and never enter Markdown, local state, or exports.
3. Cache offline bytes only as AES-GCM ciphertext under the Notes key. Bind AAD to account, attachment ID, and scope, and recheck the current account and authorization before reads and replay.
4. Use a durable rehome job for note scope changes and project deletion. Database guards keep the source metadata and object authoritative while a job is pending. A server-side worker copies bytes to the owner-bound private path, verifies the destination bytes and allowed signature, switches the metadata pointer only after verification, then removes the source object. The job completes only after source cleanup. Each step is idempotent and retryable. Project deletion remains pending until every attachment job completes; failed copies preserve the source and pending state.
5. Keep legacy Markdown and ZIP v1 note-only. Add a separately versioned v2 note bundle for attachments in exactly one selected scope. Validate the complete archive, manifest, IDs, paths, signatures, and limits before writing any record or object. Generate fresh IDs on import and remap only included references. Templates and Canvas snapshots belong only in a separate explicit same-scope workspace bundle.
6. Poll the durable queue once per minute with `pg_cron` and `pg_net`. The migration sends only the configured public API key and a dedicated worker secret from Vault; it does not store a service-role key in the scheduled SQL.

## Worker provisioning

The migration registers a scheduled poller that does nothing until all three Vault secrets exist:

- `notes_attachment_project_url`: the HTTPS Supabase project URL, without a path.
- `notes_attachment_anon_key`: the project’s public anon/publishable API key.
- `notes_attachment_worker_secret`: a random secret of at least 16 characters.

Configure the Edge Function secret `NOTES_ATTACHMENT_WORKER_SECRET` to the same value as `notes_attachment_worker_secret`. Keep the service-role credential only in the Edge Function’s server-side environment. No Vault values, remote migrations, or function deployments are performed by this implementation.

The queue must not accept client-selected Storage paths. A worker may act only on pending jobs and paths derived from validated metadata and UUIDs. Service-role access stays inside the worker; it must not return object bytes, signed URLs, keys, or credentials in responses or logs.

## Alternatives Considered

### Reuse the project-only `assets` bucket

Rejected. It cannot provide private-owner storage, and changing its policies would widen access for unrelated assets.

### Change scope synchronously in a PostgreSQL trigger

Rejected. A trigger cannot copy, verify, or remove a Storage object in the same transaction. Updating metadata first can strand bytes; deleting bytes first can lose the only copy if the transaction fails.

### Keep project-scoped objects after rehoming metadata

Rejected. Project paths must remain project-bound, and leaving bytes behind violates the user's decision that attachment bytes rehome with the note.

### Perform rehome only in the active client

Rejected. A disconnect can interrupt a scope change or project deletion without durable progress or retry. The user selected a pending server-side worker workflow.

## Consequences

- Scope changes and project deletion become asynchronous while attachment rehome jobs are pending. Callers must expose pending/failure state and allow safe retries.
- The migration must enforce scope guards and prevent a project from being deleted while its required attachment rehome is incomplete.
- The worker needs an authenticated internal invocation or scheduler, bounded retries/leases, and an observable terminal failure state. It must derive object paths from database records, never from untrusted request fields.
- Worker tests must cover copy verification, idempotent retry, interruption before and after the metadata switch, failed source cleanup, project deletion gating, and authorization boundaries.
- Local Notes cache schema and tests must cover account/scope-bound encryption, offline reads, and account switching.
- Storage, migrations, functions, and UI are source-only until separately authorized deployment. No remote migration or worker invocation is included.

## Related Documents

- [Notes parity spec](../superpowers/specs/2026-10-21-notes-obsidian-parity-design.md)
- [Templates and Canvas ADR](ADR-001-notes-templates-and-canvas-persistence.md)
