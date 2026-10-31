# Notes Maturity Design

## Intent

Bring private Markdown Notes from a usable editor to a reliable, discoverable, recoverable feature. The current Notes foundation already provides account-scoped cloud records, RLS, a standalone `/notes/:noteId` route, Markdown editing and preview, delayed saves, retry, and account-change protections. This work closes the roadmap gaps without replacing Markdown storage or weakening privacy boundaries.

## Why now

The current repository save updates by note ID and owner but has no revision precondition, so two devices can silently overwrite one another. Notes are discoverable mainly through title-only dialogs. The editor always uses a side-by-side source/preview layout, which is unsuitable for narrow screens. Deleted-note recovery and single-note Markdown export are absent.

## Goals

1. Detect stale writes across devices and preserve the local draft until the user chooses how to recover.
2. Prove account changes, delayed requests, failed-save retry, and immediate navigation do not leak or lose state unexpectedly.
3. Provide a Notes Library with title/body search, newest-first ordering, readable excerpts, and loading, error, empty, and no-results states.
4. Improve authoring while preserving Markdown as the canonical stored/exported format: retain split source/preview on desktop; on narrow screens use a single pane with source/preview toggle; add a compact Markdown toolbar and common keyboard shortcuts without replacing the text editing model.
5. Add soft-delete and restore, including removal of deleted notes from open-note tabs, without enabling permanent deletion.
6. Export one note as a `.md` file using the repository's existing export-saving mechanism.

## Non-goals

- Offline editing or queued synchronization.
- Bulk import/export, permanent deletion, folders, collaboration/sharing, attachments, internal links/backlinks, or expanded tagging/pinning.
- End-to-end encryption. Existing account privacy and RLS must remain unchanged; they are not an E2EE promise.
- Storing rich-text Delta as the source of truth or adding a new editor dependency.
- Applying migrations to any shared or production Supabase environment.

## Design

### Concurrent editing and recovery

Add a monotonically increasing integer revision to `workspace_notes`, initialized for existing and newly created rows. Include revision in the `WorkspaceNote` model and all selects. The repository save API must require the revision the editor loaded and update only when ID, owner, and revision match. A successful save advances the revision exactly once. If the conditional update returns no row, the repository performs a fresh owner-scoped read: no row or a deleted row is unavailable; a live row with a different revision is a conflict. The returned conflict includes the latest remote version so the editor can compare it with its base and draft. Migration SQL must preserve the current owner-only RLS and privilege model.

The editor retains its base version and local draft when a conflict occurs. It presents explicit reload and compare/recovery choices; it must not silently retry the stale write. The comparison makes the remote version and local draft distinguishable. If the user explicitly chooses to keep the local draft, the editor uses the fetched remote revision as its new compare-and-swap precondition; any further concurrent edit returns another conflict instead of overwriting silently. If the user leaves while a save is pending, the existing flush behavior remains; test that pending and failed work do not appear in a different account's state.

### Notes Library

Add an account-scoped Library route reachable from existing Notes entry points. It uses the current Notes provider/repository and owner-scoped data, searches loaded note titles and Markdown bodies case-insensitively, orders by `updated_at` descending, and displays a title, modified time, and a bounded plain-text excerpt. Deleted notes never appear in the active library. Render distinct loading, first-use empty, request error with retry, and query-with-no-results states. Do not add tags, pinning, or folders in this change.

### Markdown authoring

Keep Markdown text as canonical data and retain the existing preview implementation. On wide layouts keep the editable source and preview side by side. On narrow layouts show only the selected source or preview pane, controlled by an accessible toggle. Add toolbar actions for common Markdown wrappers/blocks and keyboard shortcuts only where selection and caret behavior can be tested. Editing, selection, undo/redo, and autosave must continue to operate on the Markdown text; no lossy conversion to Delta is allowed. Inline syntax-highlight/live-render editing is not part of this increment unless an implementation can preserve native text editing and pass fidelity/selection tests without introducing a new source-of-truth format.

### Trash and restore

Add a nullable deletion timestamp and account-scoped Trash queries. Normal list/get/open paths exclude deleted rows; trash lists only deleted rows; restore clears the deletion timestamp and updates ordering metadata. There is no permanent-delete action. When a note is deleted, remove its open tab and clear it if active for the same owner. Existing account-scoped tab persistence must not expose one account's Notes to another.

### Markdown export

Add a single-note export action from the editor and write the title/body as a `.md` file through the existing `ExportFileSaver` contract. Sanitize the filename using the existing export helper. Export the stored Markdown without rendering or conversion. Cancellation is not an error; failed writes show a safe retryable message and must not alter cloud content.

## Constraints and compatibility

- Preserve private per-account access and current RLS/authorization checks.
- Do not log or expose note content in errors, analytics, or diagnostics.
- Keep Markdown portable and avoid new dependencies unless a documented platform gap requires one and the user approves it.
- Migrations are source artifacts only in this task. No remote database operations are authorized.
- Preserve unrelated local modifications and untracked files. The Notes feature files and current migration are already untracked in this workspace; inspect each target before editing and keep edits narrowly scoped.

## Success criteria

- A stale revision cannot overwrite a newer server version; the stale draft remains available until the user chooses reload or explicit recovery.
- Delayed account-switch requests and pending saves never reveal or insert the previous account's note into the new account's state.
- Library search and every loading/error/empty/no-result state have focused tests.
- Desktop split view and mobile single-pane toggle have widget coverage; Markdown editing preserves selection, caret, undo/redo, and saved source.
- Soft delete and restore are revision-safe and account-scoped; deleted notes disappear from open tabs and active listings and can be restored from Trash.
- Export produces the exact Markdown content and a safe `.md` filename; cancel/failure do not modify the note.
- Focused Notes tests, Dart formatting, and Flutter analysis pass. Broader test suite runs if focused checks pass and environment permits.
