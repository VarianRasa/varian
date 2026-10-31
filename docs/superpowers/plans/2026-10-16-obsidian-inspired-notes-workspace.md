# Obsidian-Inspired Notes Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve Notes into an account-private, responsive knowledge workspace with stable wiki links, YAML properties, backlinks, full-account search, and a capped graph.

**Architecture:** Keep Markdown as canonical content. Add pure parsers and derived indexes in the Notes domain, put rename atomicity and owner checks in a versioned Postgres RPC migration, expose account-scoped operations through the existing repository/provider, and compose the current editor/library into responsive workspace and graph screens. Preserve current CAS save, draft recovery, Trash, export, route, and tab behavior.

**Tech Stack:** Flutter/Dart, Riverpod, GoRouter, Supabase/PostgreSQL, the existing `yaml` 3.1.4 lockfile package, Flutter Markdown.

**Spec:** `docs/superpowers/specs/2026-10-16-obsidian-inspired-notes-workspace-design.md`

## Global Constraints

- Markdown remains canonical; valid source markers use `[[title]]<!--varian-note-id:UUID-->` and `[[title|alias]]<!--varian-note-id:UUID-->`.
- A marker is valid only when exactly adjacent to `]]`, on the same line, outside inline/fenced code, and contains one canonical UUID; malformed, separated, or conflicting markers fall back to unique case-insensitive title resolution. A valid marker whose ID is not in the active collection remains unresolved and never falls back to a title, so Trash/missing targets cannot silently retarget.
- Search, backlinks, tags, and graph include all active Notes owned by the signed-in account; exclude Trash and other accounts. Graph renders at most 500 nodes and reports the total; search/backlinks are uncapped.
- Parse full YAML frontmatter without automatically rewriting Markdown; malformed YAML remains byte-for-byte intact, is reported, and remains searchable as raw Markdown.
- Rename through an owner-scoped, invoker-security RPC with a full active-note ID/revision snapshot, CAS checks, atomic target/source writes, stable row-lock order, and a shared per-owner transaction lock. Never silently overwrite drafts.
- Keep the migration source version-aligned with Supabase history. On 2026-10-16 the user explicitly authorized applying this Notes migration to the repository-matched `varian` project (`jnpxpylzzskaukgwhuzg`); Supabase recorded version `20261016105349`. Any further remote database changes still require explicit user authorization.
- Preserve `/notes`, `/notes/:noteId`, `/notes/trash`, account-bound note tabs, autosave, revision conflict recovery, Trash/restore, and Markdown export.
- The checkout is intentionally dirty. Preserve all existing modified/untracked content, do not stage or commit, and do not modify files outside this feature and its focused tests/spec/plan.

## Review Focus

- Malformed, duplicate, uppercase/noncanonical, separated, or code-fenced markers must not bind to another note; cover with `workspace_note_links_test.dart`.
- Duplicate titles, case-only title matches, stale text beside a valid ID, and rename-induced ambiguity must remain unresolved or surface explicit repair actions; cover in the domain/index and editor/provider tests.
- Any changed note between discovery and rename, including a new note or a source-note edit, must reject the whole RPC without partial writes; cover in repository/RPC contract tests and SQL contract checks.
- Invalid YAML, non-mapping YAML, nested properties, sequences, and scalar values must remain searchable without content mutation; cover in metadata parser tests.
- Account changes and Trash/restore during workspace navigation must never expose stale notes or keep deleted notes in search/backlinks/graph; cover in provider and widget tests.

---

### Task 1: Markdown metadata and wiki-link domain parsing

**Files:**
- Create: `lib/features/notes/domain/note_markdown_metadata.dart`
- Create: `lib/features/notes/domain/workspace_note_links.dart`
- Modify: `pubspec.yaml` (promote locked `yaml` 3.1.4 to a direct dependency without upgrading packages)
- Modify: `pubspec.lock` (change only `yaml` dependency classification to direct; retain all other package versions)
- Create: `test/features/notes/note_markdown_metadata_test.dart`
- Create: `test/features/notes/workspace_note_links_test.dart`

**Interfaces:**
- `NoteMarkdownMetadata parseNoteMarkdownMetadata(String markdown)` returns the exact frontmatter raw range/body, parsed YAML root/value or error, searchable flattened values, and merged body/frontmatter tags.
- `List<WorkspaceWikiLink> parseWorkspaceWikiLinks(String markdown)` returns source ranges, target title, optional alias, optional canonical target ID, and marker validity without changing source.
- `String renderWorkspaceMarkdown(String markdown, List<WorkspaceNote> notes)` hides valid ID comments and converts uniquely resolved wiki links to app-owned note URIs for preview; unresolved links remain visibly unresolved.

- [x] Write parser tests for closed/open/malformed YAML frontmatter, nested mappings/lists/scalars, non-map roots, invalid YAML preservation, CRLF byte preservation, tags in body/frontmatter, and ignored tags/links inside inline (including multiline) and fenced code.
- [x] Run `flutter test --no-pub test/features/notes/note_markdown_metadata_test.dart test/features/notes/workspace_note_links_test.dart` and confirm the missing APIs fail.
- [x] Implement the pure parsers with exact UTF-16 offsets compatible with Flutter `TextSelection`; enforce adjacent single canonical UUID markers and preserve Markdown bytes.
- [x] Add link-resolution tests for aliases, valid and malformed markers, duplicate IDs/markers, unique case-insensitive titles, duplicate titles, unresolved links, and source ranges; verify all focused tests pass.

### Task 2: Account-scoped Notes index and deterministic rename rewrites

**Files:**
- Create: `lib/features/notes/domain/workspace_notes_index.dart`
- Create: `test/features/notes/workspace_notes_index_test.dart`
- Modify: `test/features/notes/workspace_note_links_test.dart`

**Interfaces:**
- `WorkspaceNotesIndex(List<WorkspaceNote> activeNotes)` exposes `search(String query)`, `tags`, `backlinksFor(String noteId)`, and `graph({String? focusNoteId, Set<String> selectedTags = const {}, bool includeUnlinked = false, int limit = 500})`.
- `WorkspaceNoteRenamePlan planWorkspaceNoteRename({required List<WorkspaceNote> activeNotes, required String targetId, required String requestedTitle})` contains changed source Markdown and ambiguous legacy source IDs; it does not mutate input notes.
- RPC `rename_workspace_notes_with_links` accepts `p_target_id`, `p_expected_revision`, `p_title`, `p_snapshot: [{id, revision}]`, and `p_source_updates: [{id, revision, markdown_content}]`. The repository serializes only replacements returned by the validated rename planner.

- [x] Test search against title, raw Markdown, YAML values, and tags; test all results remain account-local and provide only active notes to the index.
- [x] Test complete backlinks, all graph edge types, isolated-note inclusion, filters, focus, and the 500-node visible limit with uncapped total count.
- [x] Test rename rewrites only valid marked target references and uniquely resolved legacy references, preserves aliases and unrelated bytes, detects ambiguous legacy references, and de-duplicates self-links.
- [x] Implement the index and deterministic rewrite planner; run the three focused domain test files.

### Task 3: Atomic owner-scoped rename RPC and repository contract

**Files:**
- Create: `supabase/migrations/20261016105349_rename_workspace_notes_with_links.sql` (applied version)
- Modify: `lib/features/notes/data/workspace_note_repository.dart`
- Create/modify: `test/features/notes/workspace_note_repository_test.dart`
- Create/modify: `test/supabase/workspace_notes_migration_test.dart`

**Interfaces:**
- `Future<List<WorkspaceNote>> renameWithLinks({required WorkspaceNote target, required String title, required List<WorkspaceNote> snapshot, required Map<String, String> markdownReplacements, required String expectedAccountId})` calls the RPC and returns all rows changed on success; callers classify stale snapshot/revision separately from unavailable rows without exposing cross-owner data.

- [ ] Add repository contract tests asserting caller-account checks happen before RPC, the RPC name and JSON payload include target ID/revision, the complete active-note ID/revision snapshot, and only validated replacement Markdown.
- [ ] Add SQL contract tests for `auth.uid()`, invoker execution, RLS-compatible owner scoping, no owner-ID input, stable lock ordering, shared transaction advisory lock, complete snapshot/revision validation, all-or-nothing updates, execute grants only to authenticated, and no remote side effects from test code.
- [ ] Implement the local migration with a fixed-path `SECURITY DEFINER` `BEFORE STATEMENT` write-lock trigger installed by the existing table owner, and an invoker RPC using the same per-account transaction lock; do not grant `TRIGGER` to app roles. Reject duplicate IDs, stale/missing/deleted rows, and invalid source sets generically.
- [ ] Implement repository RPC validation and result/error mapping. Run repository and migration contract tests. This migration was applied only after explicit user authorization to the matching `varian` project; no further remote operation is authorized by that approval.

### Task 4: Provider rename workflow and derived state

**Files:**
- Modify: `lib/features/notes/state/workspace_notes_provider.dart`
- Modify: `test/features/notes/workspace_notes_provider_test.dart`
- Use interfaces from Tasks 1–3.

- [ ] Add provider tests that rename submits the full active collection snapshot, refuses ambiguous rewrites, updates all returned rows together, refreshes after success, and preserves notes/drafts on conflict or network error.
- [ ] Verify account changes invalidate pending rename work and that trashed notes never enter derived search/backlink/graph collections.
- [ ] Implement provider orchestration and an explicit unavailable/conflict result suitable for UI `Retry`/`Reload`; keep current ordinary save CAS logic unchanged.
- [ ] Run provider, repository, parser, index, and migration contract tests.

### Task 5: Responsive workspace, link editing, and graph UI

**Files:**
- Create: `lib/features/notes/presentation/notes_workspace_screen.dart`
- Create: `lib/features/notes/presentation/notes_graph_screen.dart`
- Create/modify: `lib/features/notes/presentation/notes_context_panel.dart`
- Modify: `lib/features/notes/presentation/notes_editor.dart`
- Modify: `lib/features/notes/presentation/notes_library_screen.dart`
- Modify: `lib/features/notes/presentation/notes_route_screen.dart`
- Modify: `lib/main.dart`
- Create/modify: `test/features/notes/notes_workspace_screen_test.dart`, `test/features/notes/notes_graph_screen_test.dart`, and existing editor/library/route tests.

- [ ] Add widget tests for desktop three-column layout, narrow-screen panel navigation, search through YAML and tags, backlinks/outline/properties, graph totals/filter/cap, and static `/notes/graph` routing.
- [ ] Add editor tests for inline `[[` suggestions writing the selected ID marker, preview hiding markers and opening resolved targets, unresolved/ambiguous actions, YAML edit preservation, and exact export marker preservation.
- [ ] Add rename dialog tests for blocking ambiguous links, listing source notes, filtered `Resolve links` navigation, successful rename, and explicit conflict/network recovery with draft preservation.
- [ ] Implement workspace shell using existing AppTokens/Material 3 components and current responsive breakpoints. Preserve account-bound tab selection, `/notes`, `/notes/:noteId`, `/notes/trash`, and existing editor save/flush lifecycle.
- [ ] Implement account-scoped search/tags/backlinks/properties and graph over the complete active collection; visibly disclose total vs. max 500 rendered nodes.
- [ ] Run focused widget tests at narrow and desktop sizes and fix all layout overflow exceptions.

### Task 6: Final verification and review

**Files:**
- All in-scope files above; no unrelated files.

- [ ] Run `dart format --output=none --set-exit-if-changed lib/features/notes test/features/notes test/supabase/workspace_notes_migration_test.dart` and fix only in-scope formatting.
- [ ] Run `flutter test --no-pub test/features/notes test/features/canvas/open_document_tabs_test.dart test/supabase/workspace_notes_migration_test.dart`.
- [ ] Run `flutter analyze` and resolve findings caused by this work; report any pre-existing unrelated errors separately.
- [ ] Inspect `git diff --` and scoped `git status`; confirm no unrelated files changed, no staging/commit occurred, and local migration version matches the applied Supabase migration.
