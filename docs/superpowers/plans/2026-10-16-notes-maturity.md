# Notes Maturity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make private Markdown Notes safe against stale writes, easy to find and edit, recoverable from deletion, and portable through single-note export.

**Architecture:** Keep Supabase as the account-scoped source of truth and Markdown as the canonical note format. Use revision compare-and-swap and soft deletion in the existing `WorkspaceNoteRepository`; build Library, editor improvements, Trash, and export on the existing Riverpod/provider, router, tab, responsive, and `ExportFileSaver` seams. Add source migrations only, never apply them to shared or production services.

**Tech Stack:** Flutter/Dart, Riverpod, Supabase/PostgREST, `flutter_markdown`, existing `ExportFileSaver` and `AppResponsive`.

**Spec:** `docs/superpowers/specs/2026-10-16-notes-maturity-design.md`

## Global Constraints

- Preserve per-account ownership, authentication checks, and owner-only RLS.
- Keep Markdown as the stored and exported source; add no editor dependency or Delta conversion.
- Do not expose note content in logs, errors, or diagnostics.
- Do not apply migrations or modify shared/production Supabase resources.
- Preserve unrelated changes. Notes implementation and migrations are already untracked; review each target and edit only requested scope.
- Do not commit unless explicitly asked.

## Review Focus

- Account changes while note load/save requests are delayed must not reveal or persist another account's data; pin in Tasks 1 and 2.
- A second writer between conflict detection and explicit local-draft recovery must cause another conflict, never a silent overwrite; pin in Task 1.
- Concurrent deletion/restore and stale editor saves must not resurrect or overwrite a note unexpectedly; pin in Task 4.
- Markdown toolbar operations must preserve selected text/caret and native undo/redo while persisting exact source; pin in Task 3.
- Export cancellation or file failure must not mutate cloud content or leak note content into errors; pin in Task 5.

---

### Task 1: Revision-safe saves and conflict recovery

**Files:**
- Create: `supabase/migrations/<timestamp>_add_workspace_note_revision.sql`
- Modify: `lib/features/notes/domain/workspace_note.dart`
- Modify: `lib/features/notes/data/workspace_note_repository.dart`
- Modify: `lib/features/notes/state/workspace_notes_provider.dart`
- Modify: `lib/features/notes/presentation/notes_editor.dart`
- Test: `test/features/notes/workspace_note_repository_test.dart`
- Test: `test/features/notes/workspace_notes_provider_test.dart`
- Test: `test/features/notes/notes_editor_test.dart`

**Interfaces:**
- `WorkspaceNote` gains a required integer `revision`; update all constructor call sites and JSON fixtures, while database backfill handles existing persisted rows.
- Repository save requires the loaded revision and returns a typed success/conflict/unavailable outcome or throws a typed domain exception. Before Task 4 adds soft deletion, distinguish an absent row from a stale live row; Task 4 extends this classification so a soft-deleted row is unavailable.
- A conflict carries the latest remote note. Provider preserves the typed outcome without leaking raw PostgREST details to UI.
- Editor retains base, local draft, and remote note until explicit reload or local-draft recovery.

- [ ] **Step 1: Add failing repository CAS tests** for matching revision success and increment, stale live revision conflict with current remote row, missing row unavailable, owner scoping, and malformed response handling. Soft-deleted-row classification is added and tested in Task 4 after `deleted_at` exists.
- [ ] **Step 2: Run** `flutter test --no-pub test/features/notes/workspace_note_repository_test.dart`; expect the new cases to fail before implementation.
- [ ] **Step 3: Add migration and model field.** Backfill existing rows to revision 1, set default/not-null, keep RLS/privileges unchanged, and include revision in every selected projection.
- [ ] **Step 4: Implement conditional repository save** filtered by note ID, owner ID, and loaded revision, writing revision + 1. On zero rows, perform a fresh owner-scoped read and classify an absent row as unavailable and a live changed revision as conflict. When Task 4 adds `deleted_at`, extend this check to classify soft-deleted rows as unavailable.
- [ ] **Step 5: Run repository tests** and require all CAS, account-owner, and classification cases to pass.
- [ ] **Step 6: Add provider/editor tests** for keeping local/base/remote versions, explicit reload, explicit local recovery with newest remote revision, a second conflict after a race, delayed account switch during save, failed save then retry success, and immediate navigation during pending save.
- [ ] **Step 7: Implement conflict state and UI.** Do not retry stale updates automatically. Keep local content until an explicit user choice; local recovery must CAS against the fetched remote revision and remain conflict-safe if another writer changes it again.
- [ ] **Step 8: Run** `flutter test --no-pub test/features/notes/workspace_note_repository_test.dart test/features/notes/workspace_notes_provider_test.dart test/features/notes/notes_editor_test.dart` and require all pass.

### Task 2: Notes Library

**Files:**
- Create: `lib/features/notes/presentation/notes_library_screen.dart`
- Modify: `lib/features/notes/state/workspace_notes_provider.dart` only if search/list state needs a provider boundary
- Modify: `lib/main.dart` for the authenticated `/notes` route (add `/notes/trash` only in Task 4; do not duplicate it)
- Modify: `lib/features/canvas/presentation/widgets/canvas_editor_surface.dart` to route existing saved-note entry points to the Library
- Test: `test/features/notes/notes_library_screen_test.dart` (create)
- Test: `test/features/notes/workspace_notes_provider_test.dart`

**Interfaces:**
- Library uses owner-scoped active notes already supplied by `workspaceNotesProvider`; search can remain local over the loaded list.
- Query matches title and Markdown body case-insensitively; visible order remains `updatedAt` descending; excerpt is bounded and derived without modifying stored Markdown.

- [ ] **Step 1: Add failing widget tests** for title/body matches, ordering, excerpt, loading, first-use empty, error with retry, and no-results state.
- [ ] **Step 2: Run** `flutter test --no-pub test/features/notes/notes_library_screen_test.dart`; expect the new cases to fail before implementation.
- [ ] **Step 3: Implement the Library screen** with accessible search, note open/create actions, bounded plain-text excerpts, and distinct states. Do not add tags, pins, or folders.
- [ ] **Step 4: Add authenticated `/notes` route** without changing `/notes/:noteId`; link existing saved-note chooser/create flows to the Library while preserving direct note URLs.
- [ ] **Step 5: Run Library and route tests** and require all state and navigation cases to pass.

### Task 3: Responsive Markdown editing and toolbar

**Files:**
- Modify: `lib/features/notes/presentation/notes_editor.dart`
- Create: `lib/features/notes/presentation/markdown_editing_actions.dart` only if actions warrant a focused pure helper
- Test: `test/features/notes/notes_editor_test.dart`

**Interfaces:**
- Use `AppResponsive.isNarrow(context)` and existing Markdown preview; wide layout keeps split source/preview, narrow layout shows one pane with a source/preview toggle.
- Toolbar actions edit the existing `TextEditingController` value and preserve selection/caret. Markdown remains the sole persisted representation.

- [ ] **Step 1: Add failing widget tests** for width-dependent split/single-pane behavior and source/preview toggle.
- [ ] **Step 2: Add failing selection tests** for bold, italic, heading/list or other small agreed toolbar actions, caret placement, and exact saved Markdown; also assert native undo/redo can restore prior source.
- [ ] **Step 3: Implement responsive layout** using the existing breakpoint helper and accessible toggle labels.
- [ ] **Step 4: Implement compact toolbar actions** against the current text selection; avoid replacing text editing with a rich-text document model.
- [ ] **Step 5: Run** `flutter test --no-pub test/features/notes/notes_editor_test.dart` and require all existing autosave/account tests plus new layout/selection/undo-redo tests to pass.

### Task 4: Trash and restore

**Files:**
- Create: `supabase/migrations/<timestamp>_add_workspace_note_trash.sql`
- Create: `lib/features/notes/presentation/notes_trash_screen.dart`
- Modify: `lib/features/notes/domain/workspace_note.dart`
- Modify: `lib/features/notes/data/workspace_note_repository.dart`
- Modify: `lib/features/notes/state/workspace_notes_provider.dart`
- Modify: `lib/features/notes/presentation/notes_library_screen.dart`
- Modify: `lib/features/notes/presentation/notes_editor.dart` for the note delete action
- Modify: `lib/features/canvas/state/open_document_tabs_provider.dart`
- Modify: `lib/main.dart`
- Test: `test/features/notes/workspace_note_repository_test.dart`
- Test: `test/features/notes/workspace_notes_provider_test.dart`
- Test: `test/features/notes/notes_trash_screen_test.dart` (create)
- Test: `test/features/canvas/open_document_tabs_test.dart` (create; no existing open-note-tab test file was found)

**Interfaces:**
- Add nullable `deletedAt`; active list/get/open exclude deleted notes; Trash list includes only deleted notes; restore clears deletion timestamp.
- Repository delete/restore are owner- and revision-scoped. Extend save's zero-row reread to return unavailable for a soft-deleted note, and add that regression test. No permanent-delete method or UI is added.
- On successful deletion, close the owner-scoped open-note tab and clear it if it is the active note.

- [ ] **Step 1: Locate existing tab tests** and add failing tests for removing a deleted note's tab and clearing active selection without changing other accounts' tabs.
- [ ] **Step 2: Add failing repository/provider tests** for active-vs-trash filtering, soft-delete CAS, restore, deleted note unavailable to open/save, and stale editor save racing deletion.
- [ ] **Step 3: Add failing Trash UI tests** for loading, empty, error/retry, restoring a note, and returning it to the active Library.
- [ ] **Step 4: Add migration** for nullable `deleted_at` and appropriate owner/deleted/update index; preserve RLS. Do not add permanent deletion.
- [ ] **Step 5: Implement repository/provider lifecycle methods** with owner and revision checks; ensure restore updates `updated_at` and revision.
- [ ] **Step 6: Implement Trash route/screen and deletion action**; successful delete removes/clears only the matching account's open tab.
- [ ] **Step 7: Run focused Notes and open-tabs tests** and require race, ownership, and lifecycle cases to pass.

### Task 5: Single-note Markdown export

**Files:**
- Modify: `lib/features/notes/presentation/notes_editor.dart`
- Test: `test/features/notes/notes_editor_test.dart`
- Reuse: `lib/features/export/data/export_file_saver.dart`

**Interfaces:**
- Add optional `ExportFileSaver? exportFileSaver` injection to `NotesEditor` for isolated tests; default to `ExportFileSaver()`.
- `ExportFileSaver.save` accepts UTF-8 Markdown bytes, `text/markdown` MIME type, and a sanitized title-derived `.md` file name.
- Export operates on the current editor snapshot without changing cloud state. Cancellation has no error banner; thrown failures use a sanitized retryable message.

- [ ] **Step 1: Add failing tests** for exact exported bytes, safe `.md` filename, canceled save, failed save, and unchanged note/save count.
- [ ] **Step 2: Implement export action** with the existing save boundary and no new package.
- [ ] **Step 3: Run** `flutter test --no-pub test/features/notes/notes_editor_test.dart` and require the export cases and existing editor behavior to pass.

### Task 6: Cross-feature verification

**Files:** all Notes files changed above; no unrelated files.

- [ ] Run `dart format --output=none --set-exit-if-changed lib/features/notes test/features/notes test/features/canvas/open_document_tabs_test.dart`.
- [ ] Run all Notes and touched open-tab tests with `flutter test --no-pub ...`.
- [ ] Run `flutter analyze` and resolve all introduced diagnostics.
- [ ] Run `flutter test --no-pub --coverage` if environment permits; report any pre-existing/unrelated failures without altering unrelated work.
- [ ] Review `git status --short` and the complete diff, ensuring no unrelated edits, generated files, remote operations, or secrets were introduced.
