# Notes Expansion Design

**Status:** Draft for user review after builder check, no implementation started  
**Date:** 2026-10-16

## Intent

Extend the existing private Notes workspace with folder and favorite organization, bulk Markdown portability, unlimited content history, durable offline edits, and real-time project-member collaboration. Preserve Markdown as the canonical user-facing format, existing stable wiki-link markers, note revisions, Trash, and account/project authorization.

## Confirmed decisions

- Add both favorites/pins and folders.
- Support importing ZIP archives and selecting multiple `.md` files. Support bulk ZIP export while retaining single-note `.md` export.
- Keep every saved content version without a retention limit. Create a version for each successful save that changes the note content; do not create no-op versions.
- Include offline synchronization and real-time collaborative editing with cursor/presence.
- Merge concurrent edits automatically; surface an explicit recovery choice if they cannot be merged safely.
- Use existing Canvas project membership for collaboration. Notes remain private by default and can be associated with one Canvas project. Removing a note's creator from the project does not delete or move the note; current project members continue to access it and the removed member loses access.
- Add a user-created recovery passphrase to recover the local offline encryption key on a new device or after secure-storage loss.

## Verified current architecture

- `WorkspaceNotesProvider` scopes state to the authenticated account and constructs `WorkspaceNoteRepository`; that repository currently reads and writes `public.workspace_notes` directly through Supabase, uses revision CAS, and calls `rename_workspace_notes_with_links` for rename.
- Existing Notes RLS is owner-only. The current rename migration and function assume the authenticated user owns every affected row.
- Canvas collaboration already has project roles (`owner`, `editor`, `commenter`, `viewer`), Supabase Broadcast/Presence, CRDT operation/snapshot RPCs, version vectors, and a `CrdtTextSequence`. The existing `CrdtEngine` materializes Canvas-node text, so Notes needs a note-specific adapter rather than treating notes as Canvas nodes.
- Local persistence uses Drift and account-scoped storage elsewhere, but Notes has no durable offline cache/outbox today.
- `file_picker`, `archive`, `flutter_secure_storage`, `pointycastle`, and `crypto` are already dependencies. Existing single-note export uses `ExportFileSaver`.
- The current checkout is intentionally dirty. Preserve all unrelated modified/untracked files. The previous local PostgreSQL smoke database and its temporary roles were removed. The remote rename migration was previously authorized and applied, but no new remote schema change or deployment is authorized by this design.

## Product and data model

### Ownership, project access, and folders

- Add nullable `project_id` to `workspace_notes`, referencing `public.projects(id)` with `ON DELETE RESTRICT`; `NULL` means private to `owner_user_id`, and existing notes remain private after migration.
- A note linked to one project is visible to that project's current authenticated members. Reuse `project_role`/`can_read_project`/`can_edit_project`; `owner` and `editor` may edit, `commenter` and `viewer` are read-only for Notes. Notes comments are not part of this scope. `owner_user_id` is not an access bypass for a project-linked note, so removing its creator revokes that creator's access while the note remains available to remaining members.
- Add immutable `created_by` for attribution (backfilled from existing `owner_user_id`). Private notes use `owner_user_id` for access; linked notes use current project membership. A private note owner may link their note to a project where they are an owner/editor. Once linked, only a project owner may move or unlink it. Unlinking transfers private ownership to the acting project owner, preventing access from being silently restored to a removed creator. A `BEFORE DELETE` project trigger rehomes linked notes/folders to the project's owner-owned private collection and preserves `created_by`; if a project has no owner, deletion is rejected until the notes are reassigned.
- Add nested folders with one parent per folder and at most one folder per note. A private folder's owner must match its private notes; project folders and notes must share the same `project_id`. Deleting a folder moves its notes and child folders to its parent (or root), never deletes notes.
- Favorites are per-user preferences, not shared note metadata. A project member can pin/unpin a shared note for themselves without changing other members' views.
- Search may include all notes the user can read, but wiki-link resolution, backlinks, suggestions, and rename rewrites are restricted to one scope: the same private owner for private notes or the same project for linked notes. Cross-project/private links remain unresolved and never reveal titles or content. Moving a note across scopes previews which links will become unresolved and does not rewrite them automatically.
- Update RLS, repository filters, the rename RPC, and write-lock authorization so linked project notes are accessible only through current project membership. Rename snapshots must contain the complete active collection for that note's scope only. Revocation must take effect for database reads/writes and realtime channel joins.

### Version history

- Add an append-only `workspace_note_versions` table containing note ID, revision, title, exact Markdown snapshot, actor ID, and timestamp. Apply the same owner/project read rules as the current note; the private owner or a current project `owner`/`editor` may restore. `commenter`/`viewer` cannot restore.
- Define one version as one successful server-side materialization/commit that changes title or Markdown, including a CAS save, rename rewrite, import, CRDT operation batch, or restore. Group realtime character operations until a debounced/explicit materialization boundary; never create a version per keystroke or per transport operation. Skip no-op commits.
- A narrowly scoped database trigger inserts the initial version and captures every real `title`/`markdown_content` change, including older clients' CAS updates. The trigger uses a fixed search path, records `auth.uid()` as actor, and is the only app write path to the append-only history table.
- In the same transaction, serialize against the note's current revision, increment it exactly once, write the materialized note, and append exactly one history row. Failed or rolled-back commits create neither a revision nor a history row. Folder moves and personal pins do not create content versions.
- Restoring a version writes its title/Markdown as a new current revision and appends a new history record; it never deletes or rewrites prior history.
- Do not prune history. This satisfies the requested unlimited retention but means storage grows with every saved snapshot. The UI must disclose that history is retained indefinitely; no automatic cleanup or permanent-delete feature is included. If the database rejects a write for capacity/availability reasons, roll back the note and version together, preserve the local draft, and show a retryable storage error; never delete old versions to make a save succeed.

### Markdown import and export

- Keep existing single-note `.md` export unchanged. Add multi-select `.md` import and ZIP import, plus selected/all-notes ZIP export that preserves folder paths and includes a versioned `manifest.json` (`format: varian-notes`, `schemaVersion: 1`, notes with original UUID, relative path, title, and optional folder path). Markdown source contains the link markers; the manifest maps source note IDs to archive paths. Never include owner IDs, access tokens, or credentials in the archive. Bulk export contains current note state, not the full revision history.
- Parse and validate the entire import before writing. Show a preview for title, folder, link resolution, project/private destination, and duplicate-title outcomes. Import is all-or-nothing; never silently replace an existing note. The user can rename or skip a duplicate before confirmation.
- Generate fresh note IDs for imported notes. Validate unique manifest IDs/paths and supported schema versions. For a Varian manifest, remap links among imported notes to those new IDs. Keep links to excluded/unavailable notes unresolved; do not title-fallback a valid but unknown identity marker. For standalone `.md` files, keep exact Markdown except for an explicit user-approved link remap. Imported history is not fabricated; each imported current note starts with one initial version.
- Reject absolute paths, `..` traversal, duplicate archive paths, unsupported entries, malformed manifests, and archives exceeding documented compressed/uncompressed size and file-count limits. Sanitize exported paths and filenames. Use `archive` and existing file-picker boundaries; do not add a dependency unless platform validation proves one is necessary.
- Bulk ZIP export is the multi-note download format because browsers do not reliably support multiple separate downloads. Import supports both ZIP and multiple individual files.

## Offline and real-time collaboration

### Shared Note CRDT

- Implement a Notes-specific Markdown text CRDT adapter using existing CRDT primitives (`CrdtDot`, version vectors, and `CrdtTextSequence`) and the existing Supabase Broadcast/Presence transport patterns. Do not reuse Canvas operation tables or Canvas node materialization.
- Persist per-note CRDT snapshots and idempotent operations in Notes-specific tables/RPCs. Every operation append and materialization RPC checks the caller's current owner/project role inside its database transaction, not only at channel join. Project membership removal blocks subsequent operations; previously accepted operations remain in canonical state and are not retroactively undone.
- A server-side materialization transaction serializes on the current note revision, accepts the operation batch, materializes `markdown_content`, increments the revision once, and appends exactly one history row together. Preserve the current Markdown string as the canonical read/export/index representation.
- Broadcast active note identity and cursor anchors based on CRDT atom IDs, not raw character offsets. Presence is ephemeral and contains only minimum user/note/cursor metadata. Do not broadcast note text to channels; broadcast operation identifiers/hints, then fetch operation payloads through membership-checked RPCs. On role change, clients leave affected channels; authorization is rechecked at every persisted operation/read boundary.
- Project `owner`/`editor` can publish edits; all current project members with read permission can receive updates and presence. Private notes remain owner-only. Channel authorization and every RPC must independently enforce these rules.
- CRDT operations merge concurrent inserts/deletes deterministically. If state is malformed, a checkpoint is unavailable, access is revoked, or replay cannot be safely rebased, preserve the local draft and show a conflict/recovery UI; never overwrite the server silently.

### Offline cache and replay

- Add account-scoped Drift tables for cached Notes metadata/content, CRDT state, pending operations, and last acknowledged version vector. Persist operations before showing them as safely queued.
- Encrypt cached note content and outbox payloads at rest with a random per-account data-encryption key (DEK). Protect the DEK in OS secure storage and add a user passphrase recovery envelope: derive a wrapping key from the passphrase with a versioned, salted KDF, encrypt the DEK with authenticated encryption, and store only the wrapped DEK/KDF metadata in an account-scoped RLS table. Never upload or log the passphrase or plaintext DEK. If secure key storage is unavailable on a platform, disable offline persistence there rather than silently storing private Markdown in plaintext.
- On first setup, require the user to create and confirm the recovery passphrase. On another device or after secure-storage loss, fetch the envelope only after authentication and require the passphrase to unlock the DEK. If the passphrase is forgotten while a device still has the DEK, allow the user to rotate the envelope after re-authentication. If both the passphrase and all local DEK copies are lost, unsynced encrypted drafts cannot be recovered; confirmed server notes remain intact. Warn the user before enabling offline editing.
- Offline access is limited to an account that has previously authenticated on that device. On account change/sign-out, clear decrypted in-memory state and isolate each account's cache. Before replay, revalidate the current project role; if access was revoked, keep the encrypted local draft but do not upload it.
- On reconnect, fetch the latest CRDT snapshot/vector, replay idempotent local operations, merge through the CRDT, then atomically persist the materialized Markdown and history version. Use bounded retries and explicit sync status. No network response may cause an automatic last-write-wins replacement.
- Compaction may remove acknowledged transport operations only after a CRDT snapshot contains the full sequence state and tombstones needed to merge stale offline operations. Unlimited user-visible history snapshots are separate and are never compacted.

## Implementation phases and acceptance criteria

1. **Release readiness and plan hygiene:** reconcile existing plan checkboxes with completed reports; add authenticated UI/integration coverage using an isolated test identity, never production note data. Verify workspace, rename, Trash/restore, export, and narrow/desktop layouts.
2. **Schema and organization:** add nullable project association, folders, per-user favorites, and access helpers. Existing notes stay private. Test project-role read/write/revocation, folder scope, account switching, and project deletion behavior under local PostgreSQL.
3. **History and portability:** add immutable version writes to all content mutation paths and restore; implement import preflight and ZIP/multi-file paths. Test exact Markdown/YAML/marker preservation, ID remapping, duplicate handling, archive traversal/limits, cancellation, atomicity, and history restore.
4. **Notes CRDT and real-time:** implement operation/snapshot contracts, note-specific CRDT adapter, cursor/presence UI, and membership-aware realtime transport. Test deterministic concurrent edits, duplicate delivery, late operations, revoked access, and stable Markdown materialization.
5. **Durable offline sync:** add encrypted account-scoped cache/outbox, replay, conflict fallback, and sync UI. Test process restart, offline create/edit/delete/restore, simultaneous remote edits, account changes, expired auth, membership revocation, and stale checkpoints.
6. **Final quality and rollout:** run formatting, focused Notes/local-Postgres integration tests, `flutter analyze`, full Flutter tests where environment permits, authenticated browser/device smoke tests, and security review. Produce migration source only; remote migration application/deployment requires separate explicit authorization.

## Security, compatibility, and rollout constraints

- Migrations are source-only until separately authorized. Use an expand/compatibility rollout: first add nullable fields, tables, indexes, RLS helpers, and history triggers without removing old columns or CAS paths; then deploy clients that understand project membership/history; then enable CRDT/offline workflows. Existing owner-only clients continue to read/write private notes, with database history triggers capturing changed content. Rollback disables new client paths and leaves additive data intact; do not drop or rewrite user data.
- No remote Supabase/Vercel migration or deployment is included. Remote schema changes require separate explicit authorization.
- Old notes remain private and readable as Markdown. Current routes, CAS behavior, Trash, stable markers, and single-note export remain compatible. New project-linked notes are intentionally unavailable to old clients that lack project-aware queries.
- Never trust client-supplied project roles, owner IDs, actor IDs, version vectors, or cursor data for authorization. Every database RPC and Realtime subscription validates the authenticated user and current project membership.
- Do not expose note contents in logs, errors, analytics, crash reports, or archive diagnostics. Validate ZIP inputs before decompression and cap resource use.
- Unlimited history and offline replicas create durable data-retention and storage-cost obligations. History must not be silently pruned; users must see the indefinite-retention behavior.

## Builder-check resolutions and agent design calls

The read-only builder check raised seven blockers; they are resolved as follows for user review:

- **Creator removal:** project membership is the only access rule for linked notes. Removing the creator does not delete or move the note; remaining project members keep access and the removed creator loses access. Project-owner relinking is transaction-authorized. When unlinking to a private note, ownership transfers to the acting project owner and immutable `created_by` preserves attribution.
- **Revocation race:** every operation append/read/materialization checks current membership inside the database transaction. Operations accepted before removal remain canonical; operations after removal are rejected. Broadcast carries operation identifiers/hints rather than note text; clients fetch payloads through authorized RPCs.
- **History/revisions:** one version per successful changed materialization transaction, not per character operation. The transaction increments one revision and inserts one version atomically; rollback writes neither. History is never pruned; storage failures preserve the draft and fail visibly.
- **Recovery key:** wrap the account DEK with a passphrase-derived key; store only a versioned encrypted envelope remotely and retain the unlocked DEK in platform secure storage. If the passphrase and all local key copies are lost, unsynced drafts are unrecoverable but confirmed server notes remain. Passphrase rotation requires re-authentication and a usable current key.
- **Archive manifest:** v1 uses `format: varian-notes`, `schemaVersion: 1`, and a `notes` list of original UUID, relative Markdown path, title, and optional folder path. The manifest contains no owner IDs. Unknown schema versions are rejected. Bulk export includes current content, not history; imported notes begin with one initial version.
- **Migration rollout:** additive expand/compatibility steps preserve old private-note CAS behavior. No remote migration or deployment is included without separate explicit authorization.
- **Unlimited history:** no retention limit or automatic pruning. On storage failure, the transaction fails and the draft remains recoverable locally.

Additional agent calls: folders are nested and single-parent; favorites are per-user; commenter/viewer roles are read-only for Notes; CRDT transport compaction may occur only after a full-state checkpoint; unsupported secure-storage platforms disable offline persistence; ZIP export is the bulk-download format while multi-file selection is import-only.

## Approval gate

This document is a draft. Do not change product code, schema, dependencies, or remote resources until the user approves this design. After approval, prepare a task-by-task implementation plan with dependencies and verification commands, then implement in bounded phases.
