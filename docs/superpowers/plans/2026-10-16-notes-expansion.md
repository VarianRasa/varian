# Notes Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Do not run parallel writers on shared Notes files or migrations.

**Goal:** Extend Notes with project-aware folders and favorites, import/export, unlimited content history, encrypted offline sync, and real-time collaboration while preserving existing private notes and Markdown behavior.

**Architecture:** Keep `workspace_notes.markdown_content` as the materialized canonical Markdown. Add additive project/folder/history/CRDT/key-envelope schema; enforce access in RLS and transaction-checked RPCs. Build a Notes-specific CRDT adapter over existing primitives, and persist encrypted account-scoped cache/outbox data through Drift. Implement the schema and organization/history/portability before realtime collaboration, then offline replay.

**Tech Stack:** Flutter/Dart, Riverpod, Supabase/PostgreSQL, Drift, `file_picker`, `archive`, `flutter_secure_storage`, `pointycastle`, `crypto`, and the existing CRDT primitives.

**Spec:** `docs/superpowers/specs/2026-10-16-notes-expansion-design.md`

## Global Constraints

- Preserve all existing modified and untracked checkout content; do not stage, commit, reset, clean, or overwrite unrelated work.
- Do not apply migrations, create remote users, or mutate Supabase/Vercel resources without separate explicit authorization. Test only against `127.0.0.1` and a uniquely named disposable database.
- Existing notes remain private by default. `project_id IS NULL` uses owner-only RLS; linked notes use current Canvas project membership. A removed project member loses access, but the note remains for the other members.
- Keep Markdown and stable wiki-link markers canonical. Preserve CAS, Trash, account switching, existing routes, and single-note `.md` export.
- Only project `owner`/`editor` may edit linked Notes; `commenter`/`viewer` are read-only. Check membership in every database read/write RPC, not only when joining Realtime.
- A changed content materialization writes exactly one version and increments revision exactly once in the same transaction. History has no retention limit and must never be pruned automatically.
- Never persist the passphrase or plaintext data-encryption key remotely. Never log note content, passphrases, keys, or access tokens.
- Add no package unless an existing dependency cannot meet a verified platform requirement.

## Review Focus

1. **Project membership revoked during an open note:** the user loses read/write access immediately at RPC boundaries; the note remains visible to current members. Cover repository/RPC and live-session tests in Tasks 2, 3, 11, and 13.
2. **Concurrent CRDT operations and duplicate delivery:** merged text is deterministic, materialized once, and produces one revision/history row per committed content change. Cover Tasks 10–13.
3. **Offline edits after account switch, key loss, or project revocation:** isolate encrypted caches; replay only after current membership validation; preserve pending drafts on failure. Cover Tasks 14–16.
4. **Malformed or hostile import archives:** reject traversal, duplicate paths/IDs, unsupported manifest versions, and expansion-limit violations before any writes. Cover Tasks 7–9.
5. **Legacy app writes during additive rollout:** old private-note CAS writes still work and the history trigger records changes; no old-client write can bypass project RLS. Cover Tasks 2 and 5.

---

## Phase 0: Baseline and test harness

### Task 1: Reconcile Notes plan status and add disposable local DB harness

**Files:**
- Modify: `docs/superpowers/plans/2026-10-16-notes-maturity.md`
- Modify: `docs/superpowers/plans/2026-10-16-obsidian-inspired-notes-workspace.md`
- Create: `tool/notes_local_integration.ps1`
- Create: `test/supabase/notes_expansion_migration_test.dart`

**Interfaces:**
- The PowerShell harness accepts no remote URL. It requires host `127.0.0.1`, database name prefix `notes_test_`, uses `PGPASSFILE`, creates a unique disposable database, applies local migrations, runs SQL assertions, then drops only that database and only the global `anon`/`authenticated` roles it created (never roles that existed before the run).
- The existing migration contract test remains side-effect-free and validates source text only.

- [ ] Update old plan checkboxes only where task reports and tests prove completion. Leave new expansion tasks in this plan.
- [ ] Add a guard test for the local harness name/host checks and verify refusal for non-loopback hosts or non-prefixed databases.
- [ ] Run the focused migration-contract test and a harness dry-run that prints the selected local target without connecting or creating a database.

## Phase 1: Project access, folders, favorites

### Task 2: Add additive project-aware Notes schema and RLS

**Files:**
- Create: `supabase/migrations/20261016120000_notes_project_folders_favorites.sql`
- Test: `test/supabase/notes_expansion_migration_test.dart`
- Test: `tool/notes_local_integration.ps1`

**Interfaces:**
- Add nullable `workspace_notes.project_id`, `workspace_notes.folder_id`, and immutable `created_by`; backfill `created_by` from `owner_user_id` and keep existing notes private.
- Add `public.workspace_note_folders(id, owner_user_id, project_id, parent_folder_id, name, sort_order, created_at, updated_at)` with one parent and sibling-name uniqueness.
- Add `public.workspace_note_preferences(user_id, note_id, pinned_at)` for per-user favorites, with RLS requiring `user_id = auth.uid()` and current note-read access.
- Project-linked access uses existing `project_role`, `can_read_project`, and `can_edit_project`; private access stays owner-only. The migration adds safe fixed-search-path helper functions and indexes, and replaces the rename RPC/write lock so its snapshot and updates are scoped to the same private owner or project.

- [ ] Write failing SQL-contract tests for private owner access, project member read, owner/editor writes, commenter/viewer read-only access, removed member denial, and same-project folder constraints.
- [ ] Add the additive migration and a project-delete trigger that transfers linked notes/folders to the project owner's private scope while preserving `created_by`; reject project deletion if the project has no owner and linked Notes cannot be safely rehomed.
- [ ] Run the local PostgreSQL harness with synthetic `auth.uid()`, projects, and all four membership roles. Assert old private notes remain private and a removed creator cannot read a linked note while remaining members still can.

### Task 3: Extend Notes models and repository for project/folder access

**Files:**
- Modify: `lib/features/notes/domain/workspace_note.dart`
- Create: `lib/features/notes/domain/workspace_note_folder.dart`
- Modify: `lib/features/notes/data/workspace_note_repository.dart`
- Modify: `lib/features/notes/state/workspace_notes_provider.dart`
- Modify: `lib/features/notes/domain/workspace_notes_index.dart`
- Modify: `lib/features/notes/domain/workspace_note_links.dart`
- Test: `test/features/notes/workspace_note_repository_test.dart`
- Test: `test/features/notes/workspace_notes_provider_test.dart`
- Test: `test/features/notes/workspace_notes_index_test.dart`
- Test: `test/features/notes/workspace_note_links_test.dart`

**Interfaces:**
- `WorkspaceNote` gains nullable `projectId`, `folderId`, and non-null `createdBy` with backward-compatible JSON parsing for existing fixtures.
- `WorkspaceNoteFolder` exposes `id`, `ownerUserId`, nullable `projectId`/`parentFolderId`, `name`, `sortOrder`, `createdAt`, and `updatedAt`.
- `notesShareLinkScope(source, target)` is true only when both notes are private to the same owner or both are linked to the same project. Search lists all notes the caller may read, but suggestions, backlinks, resolution, and rename planning use this scope predicate.
- Repository methods: `listFolders({String? projectId})`, `createFolder(...)`, `moveNoteToFolder(...)`, `moveFolder(...)`, `deleteFolder(...)`, `setPinned({required String noteId, required bool pinned})`, `listPinnedNotes()`, and `setNoteProject(...)` with ownership/role checks.

- [x] Add failing tests for legacy note decoding, project/private query filtering, folder scope validation, account switch invalidation, pin isolation by user, project-owner-only relinking, cross-project/private link resolution denial, and rename snapshots limited to one scope.
- [x] Implement model/repository/provider changes with all scope checks at the repository boundary and errors mapped to typed domain results.
- [x] Run repository and provider test files plus migration contract tests.

### Task 4: Add folder and favorites UI

**Files:**
- Modify: `lib/features/notes/presentation/notes_workspace_screen.dart`
- Modify: `lib/features/notes/presentation/notes_library_screen.dart`
- Create: `lib/features/notes/presentation/notes_folder_dialog.dart`
- Create: `lib/features/notes/presentation/notes_organization_panel.dart`
- Test: `test/features/notes/notes_workspace_screen_test.dart`
- Test: `test/features/notes/notes_library_screen_test.dart`

**Interfaces:**
- Provide accessible folder create/rename/move/delete actions, pinned-note filtering, and private/project scope indication.
- Deleting a folder moves its notes and child folders to the parent or root; it never deletes note content.

- [x] Add widget tests for nested navigation, moving a note, deleting a non-empty folder, personal pin isolation, folder loading/empty/error states, and narrow-screen behavior.
- [x] Implement the UI using existing responsive and Material 3 patterns; do not add unrelated library features.
- [x] Run focused workspace/library tests at 320, 390, 768, 1024, and 1440px widths.

## Phase 2: Unlimited history

### Task 5: Add append-only note history with atomic capture

**Files:**
- Create: `supabase/migrations/20261016120100_workspace_note_history.sql`
- Test: `test/supabase/notes_expansion_migration_test.dart`
- Test: `tool/notes_local_integration.ps1`

**Interfaces:**
- Add `public.workspace_note_versions(id, note_id, revision, title, markdown_content, actor_id, created_at)` with per-note revision uniqueness, RLS matching note access, and no app-role direct write grant.
- Add a narrowly scoped fixed-search-path trigger that inserts the initial version and records real title/Markdown changes, including legacy CAS updates.

- [x] Add failing SQL/source-contract tests for initial version, changed-content version, no-op skip, transaction rollback, append-only privileges, project role access, revision invariants, and unlimited retention (no pruning routine/policy).
- [x] Implement trigger/RLS/grants and ensure the trigger sees the caller via `auth.uid()` while running with the required owner privileges.
- [x] Run the disposable local PostgreSQL harness. Assert each successful changed save adds exactly one version and a rolled-back write adds none.

### Task 6: Add history repository and restore flow

**Files:**
- Create: `lib/features/notes/domain/workspace_note_version.dart`
- Modify: `lib/features/notes/data/workspace_note_repository.dart`
- Modify: `lib/features/notes/state/workspace_notes_provider.dart`
- Create: `lib/features/notes/presentation/notes_history_panel.dart`
- Modify: `lib/features/notes/presentation/notes_editor.dart`
- Test: `test/features/notes/workspace_note_repository_test.dart`
- Test: `test/features/notes/workspace_notes_provider_test.dart`
- Test: `test/features/notes/notes_editor_test.dart`

**Interfaces:**
- `WorkspaceNoteVersion` holds ID, note ID, revision, title, exact Markdown, actor ID, and timestamp.
- Repository methods: `listNoteVersions(String noteId)` and `restoreNoteVersion({required String noteId, required String versionId, required int expectedRevision})`.
- Restore requires the current private owner or project owner/editor, creates a new revision and history row, and never mutates prior snapshots.

- [x] Add failing tests for history ordering, owner/project read rules, commenter/viewer restore denial, stale restore conflict, exact Markdown preservation, and restore-as-new-version behavior.
- [x] Implement repository/provider and history UI with an indefinite-retention notice and explicit restore confirmation.
- [x] Run focused repository/provider/editor tests. Passed: 73 tests across the three suites.
- [ ] Rerun local SQL history tests. Not run in this session because `PGPASSFILE` was not configured; Task 5's prior loopback harness passed history capture/RLS/rollback/privilege assertions.

## Phase 3: Markdown portability

### Task 7: Implement manifest and import preflight parser

**Files:**
- Create: `lib/features/notes/domain/note_archive_manifest.dart`
- Create: `lib/features/notes/data/notes_import_service.dart`
- Test: `test/features/notes/note_archive_manifest_test.dart`
- Test: `test/features/notes/notes_import_service_test.dart`

**Interfaces:**
- `NoteArchiveManifest.parse(Uint8List bytes)` validates `format == 'varian-notes'`, `schemaVersion == 1`, unique source UUIDs and paths, and title/folder fields.
- `NotesImportService.prepare({required List<PlatformFile> files, required List<WorkspaceNote> existingNotes})` returns an immutable preview with new IDs, remapped internal links, duplicate outcomes, and typed validation errors. It does not write to Supabase.

- [x] Add failing tests for supported/unsupported manifest versions, malformed JSON, duplicate IDs/paths, title collisions, fresh ID generation, internal marker remapping, unknown marker preservation, and exact Markdown bytes.
- [x] Implement parser/preflight; enforce 100 Markdown files, 25 MiB selected input, 1 MiB manifest, and 10 MiB per Markdown file. The 100 MiB expanded ZIP limit is enforced during Task 8 decoding.
- [x] Run `flutter test --no-pub test/features/notes/note_archive_manifest_test.dart test/features/notes/notes_import_service_test.dart` (8 tests passed).

### Task 8: Implement multi-file and ZIP import

**Files:**
- Create: `supabase/migrations/20261016120150_notes_import_rpc.sql`
- Modify: `lib/features/notes/data/notes_import_service.dart`
- Create: `lib/features/notes/presentation/notes_import_dialog.dart`
- Modify: `lib/features/notes/presentation/notes_workspace_screen.dart`
- Modify: `lib/features/notes/data/workspace_note_repository.dart`
- Test: `test/features/notes/notes_import_service_test.dart`
- Test: `test/features/notes/notes_workspace_screen_test.dart`
- Test: `test/supabase/notes_expansion_migration_test.dart`
- Test: `tool/notes_local_integration.ps1`

**Interfaces:**
- `NotesImportService.decodeSelection(...)` supports both multiple `.md` files and ZIP; all validation completes before writes.
- Repository `importNotes(...)` calls `public.import_workspace_notes_batch(p_notes jsonb, p_folders jsonb, p_project_id text)`; the security-invoker RPC validates destination access and creates accepted notes/folders atomically or creates none. Existing notes are never overwritten.

- [ ] Add failing tests for ZIP traversal, absolute paths, duplicate archive entries, oversized expansion, malformed Markdown entries, cancellation, duplicate rename/skip choices, project/private destination, and all-or-nothing failure.
- [ ] Implement preview and confirmed import using `file_picker`/`archive`; preserve original Markdown except manifest-owned ID remaps.
- [ ] Run focused importer/widget tests and local PostgreSQL transaction tests.

### Task 9: Implement multi-note ZIP export

**Files:**
- Create: `lib/features/notes/data/notes_export_service.dart`
- Modify: `lib/features/notes/presentation/notes_workspace_screen.dart`
- Reuse: `lib/features/export/data/export_file_saver.dart`
- Test: `test/features/notes/notes_export_service_test.dart`
- Test: `test/features/notes/notes_workspace_screen_test.dart`

**Interfaces:**
- `NotesExportService.exportZip(List<WorkspaceNote> notes, List<WorkspaceNoteFolder> folders)` returns ZIP bytes containing sanitized `.md` paths and v1 manifest; export includes current content only, not history.

- [ ] Add failing tests for exact Markdown/YAML/marker bytes, stable folder paths, safe filenames, no user IDs/secrets/history, empty selection, and cancellation/failure without cloud mutation.
- [ ] Implement ZIP generation and save through `ExportFileSaver`.
- [ ] Run focused export/editor/workspace tests.

## Phase 4: Real-time project collaboration

### Task 10: Add Notes-specific Markdown CRDT domain engine

**Files:**
- Create: `lib/features/notes/domain/note_crdt_document.dart`
- Create: `lib/features/notes/domain/note_crdt_operation.dart`
- Reuse: `lib/features/collaboration/domain/crdt_primitives.dart`
- Reuse: `lib/features/collaboration/domain/crdt_text_sequence.dart`
- Test: `test/features/notes/note_crdt_document_test.dart`

**Interfaces:**
- `NoteCrdtDocument.fromMarkdown(...)`, `applyLocalEdit(...)`, `applyRemoteOperation(...)`, `visibleMarkdown`, `versionVector`, and `snapshotState()` manage one Markdown sequence without Canvas nodes.
- Operation IDs are idempotent and contain note ID, per-device replica ID, counter, dependencies, and sequence edits. The server derives/stores `auth_user_id = auth.uid()` separately; replica IDs identify causal streams only and never grant access.

- [ ] Add failing tests for deterministic concurrent inserts/deletes, Unicode offsets, duplicate delivery, out-of-order/causal operations, stale atom anchors, tombstone snapshots, and exact materialized Markdown.
- [ ] Implement the Notes adapter over existing sequence primitives without modifying Canvas behavior.
- [ ] Run CRDT domain tests and existing collaboration CRDT tests.

### Task 11: Add Notes CRDT tables and transaction-checked RPCs

**Files:**
- Create: `supabase/migrations/20261016120200_notes_crdt_collaboration.sql`
- Test: `test/supabase/notes_expansion_migration_test.dart`
- Test: `tool/notes_local_integration.ps1`

**Interfaces:**
- Add note-specific snapshot and operation tables plus `create_workspace_note_from_sync`, `append_workspace_note_crdt_operation`, `get_workspace_note_crdt_delta`, and `materialize_workspace_note_crdt` RPCs.
- `create_workspace_note_from_sync` seeds an offline-created note and its CRDT state in one transaction after validating owner/project role. Every RPC validates current note/project permission inside its transaction. Accepted operations are idempotent; materialization serializes on revision, updates Markdown, and creates one history entry atomically.

- [ ] Add failing SQL assertions for owner/project roles, removed-member denial, operation idempotency, version-vector delta reads, stale revisions, concurrent lock serialization, transaction rollback, and no text in Realtime payloads.
- [ ] Implement narrowly scoped RPCs, fixed search paths, RLS, grants, and full-state checkpoints that preserve CRDT tombstones.
- [ ] Run local PostgreSQL smoke tests only; never call Supabase tools or a remote URL.

### Task 12: Add Notes Realtime transport and cursor presence

**Files:**
- Create: `lib/features/notes/data/notes_collaboration_transport.dart`
- Create: `lib/features/notes/state/notes_collaboration_provider.dart`
- Test: `test/features/notes/notes_collaboration_transport_test.dart`
- Test: `test/features/notes/notes_collaboration_provider_test.dart`

**Interfaces:**
- `NotesCollaborationTransport.join(noteId, projectId)`/`leave()` manages private Notes topics, operation hints, connection state, and ephemeral cursor presence.
- Broadcast events contain operation IDs only. Operation contents are read through Task 11's authorized RPCs. Presence cursor positions use CRDT atom anchors.

- [ ] Add failing tests for membership denied at join, reconnect, duplicate hints, role revocation, no Markdown in payloads, cursor anchor transformation, and cleanup on account/note switch.
- [ ] Implement channel lifecycle using existing Supabase Realtime patterns; don't change Canvas payload contracts.
- [ ] Run Notes collaboration tests and existing Canvas collaboration transport tests.

### Task 13: Bind collaborative state to the Notes editor

**Files:**
- Modify: `lib/features/notes/presentation/notes_editor.dart`
- Modify: `lib/features/notes/state/workspace_notes_provider.dart`
- Create: `lib/features/notes/presentation/notes_collaborator_cursors.dart`
- Test: `test/features/notes/notes_editor_test.dart`
- Test: `test/features/notes/notes_workspace_screen_test.dart`

**Interfaces:**
- Editor applies local text deltas to `NoteCrdtDocument` for both private and project-linked notes, receives remote materialized Markdown without resetting unrelated selection, and displays peer cursors/presence only for project-linked notes.
- Private notes sync CRDT operations owner-only without joining a collaboration/presence channel; project-linked notes use the same CRDT with project-member authorization.

- [ ] Add failing widget tests for two collaborators, cursor updates, local typing during remote changes, membership removal, read-only roles, and clean private-note fallback.
- [ ] Implement feature gating by note scope and preserve drafts on channel/RPC failure.
- [ ] Run focused editor/provider/workspace tests.

## Phase 5: Encrypted offline sync

### Task 14: Add recovery envelope and encrypted local Note storage

**Files:**
- Create: `lib/features/notes/data/notes_key_manager.dart`
- Create: `lib/features/notes/data/notes_local_database.dart`
- Create: `lib/features/notes/data/notes_local_store.dart`
- Reuse: `lib/data/local/durable/durable_database_connection.dart`
- Create: `supabase/migrations/20261016120300_notes_offline_key_envelopes.sql`
- Test: `test/features/notes/notes_key_manager_test.dart`
- Test: `test/features/notes/notes_local_store_test.dart`
- Test: `test/supabase/notes_expansion_migration_test.dart`

**Interfaces:**
- `NotesKeyManager.createEnvelope`, `unlockEnvelope`, and `rotateEnvelope` wrap a random per-account DEK using a versioned salted KDF and authenticated encryption. The passphrase and plaintext key never leave the device.
- `NotesLocalStore` encrypts note content and outbox payloads before persistence; all queries include account ID. Platforms without secure storage disable offline persistence.

- [ ] Add failing tests for round-trip, wrong passphrase, tampered envelope, account isolation, key rotation, missing secure storage, and no plaintext note content in the local database.
- [ ] Add the key-envelope table with owner-only RLS and no plaintext secret column. Implement key recovery and warn if both the passphrase and local key are unavailable.
- [ ] Run crypto/store tests and local SQL RLS tests; do not print keys or passphrases.

### Task 15: Add durable offline outbox and replay

**Files:**
- Create: `lib/features/notes/data/notes_sync_repository.dart`
- Modify: `lib/features/notes/state/workspace_notes_provider.dart`
- Modify: `lib/features/notes/data/notes_local_store.dart`
- Test: `test/features/notes/notes_sync_repository_test.dart`
- Test: `test/features/notes/workspace_notes_provider_test.dart`

**Interfaces:**
- `NotesSyncRepository.enqueue`, `syncAccount`, `pauseForRevokedMembership`, and `resumeAfterAuthentication` persist idempotent operations and vector checkpoints.
- Replay fetches current server state and membership before publishing; CRDT performs deterministic merge. Unmergeable, expired-auth, revoked, or key-locked drafts stay encrypted and are surfaced for recovery.

- [ ] Add failing tests for offline create/edit/delete/restore, process restart, outbox retry/idempotency, two-device concurrency, account switch, revoked project access, expired auth, missing recovery passphrase, and server storage failure.
- [ ] Implement bounded replay with one account worker at a time, generation fencing on account change, and explicit per-note sync state.
- [ ] Run focused sync/provider tests and local Postgres RPC tests with delayed/reordered operations.

### Task 16: Add offline/recovery UI and operational disclosure

**Files:**
- Modify: `lib/features/notes/presentation/notes_workspace_screen.dart`
- Modify: `lib/features/notes/presentation/notes_editor.dart`
- Create: `lib/features/notes/presentation/notes_recovery_dialog.dart`
- Test: `test/features/notes/notes_workspace_screen_test.dart`
- Test: `test/features/notes/notes_editor_test.dart`

**Interfaces:**
- Show online/offline/queued/conflict/access-revoked states, first-use passphrase setup, passphrase unlock, and explicit draft recovery.
- Explain unlimited history retention and storage growth. Never silently discard pending edits or old versions.

- [ ] Add failing widget tests for recovery setup, wrong passphrase, locked cache, sync pause, membership revocation, retry, manual conflict recovery, and indefinite-history notice.
- [ ] Implement accessible states and keep private note drafts usable without exposing project-only notes to removed users.
- [ ] Run focused UI tests at narrow and desktop sizes.

## Phase 6: End-to-end verification and review

### Task 17: Run integration, browser, and final quality gates

**Files:**
- Create: `integration_test/notes_workspace_test.dart`
- Modify: `test/features/notes/notes_workspace_screen_test.dart`
- Modify: `test/supabase/notes_expansion_migration_test.dart`
- Modify: `docs/superpowers/sdd/2026-10-16-obsidian-inspired-notes-workspace/progress.md`
- Modify: `docs/superpowers/sdd/2026-10-16-obsidian-inspired-notes-workspace/task-3-report.md`
- Modify: `docs/superpowers/sdd/2026-10-16-obsidian-inspired-notes-workspace/task-5-report.md`

- [ ] Run the disposable local PostgreSQL harness against `127.0.0.1`; verify project RLS, folder/favorite operations, history, import transaction, CRDT replay, membership revocation, and cleanup.
- [ ] Run an authenticated UI smoke test with an isolated test identity or local auth harness, never a real user account or production notes. If no safe test identity is available, report that gate as blocked instead of claiming it passed.
- [ ] Run `dart format --output=none --set-exit-if-changed lib test tool`.
- [ ] Run `flutter analyze`.
- [ ] Run `flutter test --no-pub --coverage`; report any unrelated failures without modifying unrelated files.
- [ ] Review scoped diffs for auth/RLS leaks, remote calls, secrets, generated artifacts, and dirty-checkout preservation. No staging or commit.
- [ ] Update progress/report docs with exact test outcomes and state clearly that remote migrations remain unapplied until separately authorized.

## Execution notes

- Execute tasks sequentially because schema/RLS contracts are shared across repository, CRDT, history, and offline paths. Review each migration and local test result before building the next dependent layer.
- If any required API behavior or platform security property cannot be verified from the installed package versions, stop at that task and ask before adding dependencies or weakening the design.
- Do not remove the test database or local user data except the exact disposable database created by Task 1's harness.
