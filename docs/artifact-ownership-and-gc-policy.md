# Artifact ownership and garbage-collection policy

**Status:** adopted for current local project lifecycle and duplication behavior; remote storage deletion remains out of scope.

## Current model

Canvas payloads and `DocumentAssetManifest` entries persist stable artifact references (for example `varian-image://…`, `varian-file://…`, and project-scoped Supabase Storage paths). Native and Web artifact stores persist bytes outside the canvas JSON: native stores use application-support files, and Web stores use IndexedDB. A project document references those objects; the object is not currently a child row/file owned exclusively by that project. Hydrated URLs, native paths, and object URLs are runtime handles, not durable ownership identifiers.

Store `dispose` releases transient render resources (such as a Web object URL); it must not delete durable source bytes. Current artifact-store interfaces do not expose durable deletion. Keep these responsibilities separate.

## Duplication and branching

Project duplication/branching creates a new project/document identity but preserves stable artifact references. Treat this as sharing immutable content-address-independent artifact objects between local documents, not as a request for a physical copy. The existing behavior preserves editability/preview access as long as the referenced bytes remain in the device's shared artifact store.

Any feature that needs an independently owned copy must explicitly copy bytes into a new artifact and relink the copied document/manifest. It must not mutate or delete the source object. A semantic duplicate or a node copy inside the same document can continue to share immutable bytes.

## Trash and local purge

Trash and restore change local project metadata only. Local permanent purge removes that project's document, history, queues, metadata, and project-scoped caches; it must not remove native or IndexedDB artifact bytes. A purged project's references may consequently become unreferenced, but their status is not provable from the current metadata and they remain on-device until a safe collection mechanism exists.

Local lifecycle actions must not call cloud project-deletion or Storage-object deletion RPCs. Cloud deletion request/cancellation is a separate owner-authorized operation; it is not immediate deletion and does not imply artifact cleanup.

## Garbage collection requirements (not implemented)

Do not add byte deletion or a collector until a durable reference/ownership index is designed and backfilled. A future collector must account for all live documents and manifests, versions, recovery journals, autosave checkpoints, branch/duplicate projects, undo/redo and AI transactions where applicable, published snapshots, import/export staging, and any other durable references. It must also define cross-account/device semantics for remote objects, leases or concurrent writers, retention/undo windows, failure recovery, and an auditable dry-run/commit boundary.

Collection may delete only an object proven unreferenced within its complete ownership domain, after a safety grace period and a fresh index check. Unknown, malformed, legacy, inaccessible, or cross-scope references must retain the object. Never infer ownership from a project path fragment, local role, filename, room code, cache miss, or the fact that one project was purged. Server-side authorization and reference policy must govern remote bytes.

## Consequences and follow-up

- Accept on-device orphan bytes as the safe current trade-off; do not promise storage reclamation on project purge.
- Preserve stable references during duplicate/branch operations and avoid byte copying by default.
- Design and migrate a complete local/remote reference index before any automatic GC or cloud Storage cleanup.
- Add focused tests proving duplicate and purge preserve referenced bytes once the persistence tests can use a durable artifact-store adapter rather than only inline fixtures.
- Revisit this policy only with an explicit product decision for physical-copy semantics or retention/deletion requirements.
