# Notes Obsidian-Parity Task List

**Status:** Approved for implementation by the user's explicit request. Phase 0 contracts are recorded in the [spec](../docs/superpowers/specs/2026-10-21-notes-obsidian-parity-design.md) and [ADR](../docs/decisions/ADR-001-notes-templates-and-canvas-persistence.md). Local source, test, and additive migration changes are authorized; remote Supabase changes are not.

Tasks are sized for separate focused sessions. File lists are expected scope, not permission to modify unrelated worktree content. The user explicitly requested implementation; keep database changes local/source-only unless separately authorized. Obsidian evidence is static/package documentation only; no interactive UI behavior was captured.

## Phase 0: Decisions and contracts

### Task 0.1: Record decisions and complete technical contracts
- **Acceptance:** Record the confirmed Daily Notes timezone/scope; Supabase Templates, explicit private/project scope, management screen, and date/title/alias variables; typed JSON/revision Notes Canvas with project sharing, CRDT, and encrypted offline sync in v1; and the selected Properties/Markdown features. Complete the Phase 0 contracts for date uniqueness, template schema/RLS/variable escaping, board revision/CRDT/offline replay, link anchors, attachment/PDF safety, math/Mermaid rendering, and scope-aware template/board/asset export. Do not treat uncaptured Obsidian UI as verified behavior.
- **Verify:** Keep the spec, plan, checklist, and ADR consistent with the user's approved direction and explicit implementation request; verify Markdown links. No remote migration is run.
- **Files:** `docs/superpowers/specs/2026-10-21-notes-obsidian-parity-design.md`, `docs/superpowers/plans/2026-10-21-notes-obsidian-parity.md`, `tasks/notes-obsidian-parity-todo.md`, `docs/decisions/ADR-001-notes-templates-and-canvas-persistence.md`.
- **Dependencies:** None.

### Task 0.2: Preserve historical Notes plans
- **Acceptance:** Keep the untracked 2026-10-16 designs unchanged. Treat their shipped baseline items as historical; the current source audit found the prior Notes foundation (revision CAS, Library, Trash, Markdown export, folders, favorites, CRDT, encrypted offline sync) already present. New scope is governed by this approved spec.
- **Verify:** Read-only source/status review; do not rewrite or mark historical checklists complete without testing each legacy item.
- **Files:** New Notes parity plan/task list only.
- **Dependencies:** Task 0.1.

## Phase 1: Properties and links

### Task 1.1: Add lossless typed-property domain support
- **Acceptance:** Read and update approved YAML property types; preserve unknown keys, invalid YAML, comments, line endings, and all untouched Markdown bytes.
- **Verify:** Parser/unit tests for valid/invalid/nested frontmatter and exact round-trip.
- **Files:** `lib/features/notes/domain/note_markdown_metadata.dart`, new focused domain helper, `test/features/notes/note_markdown_properties_test.dart`, `pubspec.yaml`, and `pubspec.lock` for `yaml_edit` 2.2.4.
- **Dependencies:** Task 0.1.

### Task 1.2: Add Properties editor UI
- **Acceptance:** Users can add/edit/remove supported Properties; the UI reports malformed frontmatter and does not silently discard it.
- **Verify:** Widget tests for each field type, invalid input, unknown fields, narrow/desktop layout, autosave, and conflict recovery.
- **Files:** `lib/features/notes/presentation/notes_context_panel.dart`, `lib/features/notes/presentation/notes_editor.dart`, focused Notes widget tests.
- **Dependencies:** Task 1.1.

### Task 1.3: Add unresolved, heading/block links and linked mentions
- **Acceptance:** User can create a note from an unresolved `[[...]]` link; heading/block links navigate and round-trip with defined rename/duplicate-anchor behavior; backlinks include explicit links and unlinked mentions; ambiguous matches never auto-retarget; code examples are ignored.
- **Verify:** Parser/index/editor tests for aliases, stable markers, duplicate titles, rename behavior, code masks, and linked mentions.
- **Files:** `lib/features/notes/domain/workspace_note_links.dart`, `lib/features/notes/domain/workspace_notes_index.dart`, `lib/features/notes/presentation/notes_editor.dart`, `test/features/notes/workspace_note_links_test.dart`, `test/features/notes/workspace_notes_index_test.dart`.
- **Dependencies:** Task 0.1.

### Task 1.4: Add local/global graph navigation
- **Acceptance:** Graph can display a local neighborhood and global authorized scope, filter by approved metadata, and explain when the 500-node cap applies.
- **Verify:** Domain/widget tests for direction, focus, filters, isolated notes, scope isolation, and capped totals.
- **Files:** `lib/features/notes/domain/workspace_notes_index.dart`, `lib/features/notes/presentation/notes_graph_screen.dart`, `test/features/notes/workspace_notes_index_test.dart`, `test/features/notes/notes_graph_screen_test.dart`.
- **Dependencies:** Task 1.1, Task 1.3.

## Phase 2: Note workflows

### Task 2.1: Add idempotent Daily Notes
- **Acceptance:** One note is returned/created per local date using account/device timezone and active-project scope, with private fallback when no project is active; reopening does not create duplicates; account changes cannot expose a prior account's daily note.
- **Verify:** Date-boundary, timezone, duplicate/race, account-switch, and navigation tests.
- **Files:** New Notes daily-note domain/service, `lib/features/notes/data/workspace_note_repository.dart`, Notes provider/UI, focused tests, additive local migration only if required.
- **Dependencies:** Task 0.1.

### Task 2.2: Add Markdown Templates
- **Acceptance:** Users can manage Notes-specific Supabase template records with explicit private or project-shared scope; date/title/alias expansion is deterministic and template content is never executed; insertion preserves existing note content unless explicitly replaced.
- **Verify:** Unit/widget tests for variables, missing values, frontmatter, cursor insertion, and saved Markdown.
- **Files:** New Notes template model/service and repository, additive local Supabase migration/RLS source if no suitable table exists, `lib/features/notes/presentation/notes_editor.dart`, Notes library/workspace UI, focused domain/repository/widget tests. Do not apply migrations remotely.
- **Dependencies:** Task 0.1, Task 1.1.

### Task 2.3: Complete Bookmarks using existing pins
- **Acceptance:** Bookmark actions and navigation use the current per-user pin state; project members' pins remain isolated from each other.
- **Verify:** Provider/widget tests for create/remove/filter, project scope, account switch, and empty/loading/error states.
- **Files:** `lib/features/notes/presentation/notes_workspace_screen.dart`, `lib/features/notes/presentation/notes_organization_panel.dart`, existing pin providers/repository, focused tests.
- **Dependencies:** Task 0.1.

## Phase 3: Notes Canvas board

### Task 3.1: Implement board domain contract
- **Acceptance:** Encode the locked typed JSON board/card/edge schema, revision semantics, board-specific CRDT operations, encrypted offline replay contract, stable same-scope note references, project roles, and tombstone behavior. Project sharing, CRDT, and encrypted offline support are required for v1.
- **Verify:** Domain tests cover versioned JSON round-trip, stable note IDs, bounds, revision behavior, CRDT merge/idempotency, encrypted offline replay/recovery, and dangling/deleted note references.
- **Files:** Notes Canvas domain and repository contracts plus focused domain tests. Define migration/RLS changes here; implement local migration source and authorization tests in Task 3.2. Do not apply remotely.
- **Dependencies:** Task 0.1.

### Task 3.2: Implement Notes Canvas storage and board state
- **Acceptance:** Owner-private and project-shared boards persist in Supabase, reference Notes by stable ID, obey the matching authorization scope, and cannot delete or mutate referenced note bodies.
- **Verify:** Local migration/RLS and repository/provider tests for create/read/update, owner/project roles, stale revisions, CRDT replay, encrypted offline sync, access revocation, and account switching.
- **Files:** New `lib/features/notes/domain/` and `data/` board modules, Notes providers, local migration source, focused tests.
- **Dependencies:** Task 3.1.

### Task 3.3: Implement dedicated Notes Canvas UI
- **Acceptance:** Notes has a board route with note/text cards, connectors, pan/zoom, save status, and card-to-note navigation; Varian Canvas routes and documents remain unchanged.
- **Verify:** Widget tests for board lifecycle, placement, interaction, note opening, narrow layout, save/conflict/error states, and account/project isolation.
- **Files:** New `lib/features/notes/presentation/notes_canvas_screen.dart` and widgets, `lib/main.dart`, Notes route/widget tests.
- **Dependencies:** Task 3.2.

## Phase 4: Markdown and portability

### Task 4.1: Add selected Markdown rendering/editing features
- **Acceptance:** Implement callouts, interactive tasks, note/attachment/PDF embeds, inline/block math (`$...$`/`$$...$$`) with `flutter_math_fork` 0.7.4, and fenced Mermaid diagrams without losing source text or unrelated formatting. Heading/block links are covered by Task 1.3.
- **Verify:** Renderer/editor tests for source-preview fidelity, task updates, safe and authorized attachment/PDF access, math/Mermaid rendering, hostile input, and unsupported syntax preservation on supported targets.
- **Files:** Notes editor/rendering helper(s), `pubspec.yaml` and lockfile for `flutter_math_fork` 0.7.4, focused tests.
- **Dependencies:** Task 0.1, Task 1.1.

### Task 4.2: Verify Obsidian-style Markdown import/export round-trip
- **Acceptance:** Approved Properties, heading/block links, math/diagram source, and attachment/PDF references survive import/export. Legacy Markdown and v1 ZIP remain note-only; v2 note bundles include same-scope attachments; a separate explicit same-scope workspace bundle may include templates and board snapshots. Full preflight validates paths, signatures, IDs, and limits before writes; imports remap included IDs and leave excluded references unresolved.
- **Verify:** Import/export tests for exact source preservation, IDs/anchors, asset access, scope isolation, path traversal, size limits, and atomic failure.
- **Files:** `lib/features/notes/data/notes_import_service.dart`, `lib/features/notes/data/notes_export_service.dart`, import/export dialog/workspace UI, focused tests.
- **Dependencies:** Task 1.1, Task 1.3, Task 4.1.

## Phase 5: Verification

### Task 5.1: Run Notes regression and security checks
- **Acceptance:** Existing account checks, RLS contracts, revision conflicts, Trash/history, note CRDT collaboration, encrypted offline sync, import/export, tabs, and Varian Canvas behavior remain intact. New template private/project authorization and Notes Canvas revision/CRDT/encrypted-offline behavior pass their focused tests.
- **Verify:**
  - `dart format --output=none --set-exit-if-changed lib/features/notes test/features/notes lib/features/canvas test/features/canvas`
  - `flutter test --no-pub test/features/notes`
  - `flutter analyze`
  - Run local-only migration tests if schema changed; never target remote/shared/production Supabase.
- **Files:** All approved in-scope source/tests only.
- **Dependencies:** All approved implementation tasks.

### Task 5.2: Review final scope and worktree
- **Acceptance:** Only approved Notes files changed; no unrelated dirty/untracked user work is overwritten, staged, committed, or cleaned; no remote services are mutated.
- **Verify:** Inspect scoped `git diff` and `git status --short`; report exact commands and results.
- **Files:** None beyond approved implementation scope.
- **Dependencies:** Task 5.1.
