# Implementation Plan: Obsidian-Inspired Notes for Varian

**Status:** Approved for implementation by the user's explicit request. Phase 0 contracts are recorded in the spec and ADR. Local source, tests, and migration files may change; remote Supabase migrations, deployments, and data changes remain separately unauthorized.

**Spec:** [2026-10-21 Notes parity spec](../specs/2026-10-21-notes-obsidian-parity-design.md)  
**ADR:** [Notes storage ADR](../../decisions/ADR-001-notes-templates-and-canvas-persistence.md)  
**Task list:** [Notes parity tasks](../../../tasks/notes-obsidian-parity-todo.md)

## Goal

Extend Varian's existing Markdown Notes to cover the agreed Obsidian core workflows without replacing Supabase, project sharing, Notes CRDT collaboration, encrypted offline sync, version history, or current account/security rules.

## Current-state baseline

The current Notes source already has folders, favorites, search/tag filters, Markdown import/export, YAML metadata parsing, wiki links with stable IDs, direct backlinks, a 500-visible-node graph, Trash/history, CRDT collaboration, and encrypted offline sync. The 2026-10-16 workspace, maturity, and expansion plans are untracked and may contain completed/stale items. Reconcile each task against the current source and focused tests before implementing. Do not update or overwrite those user-owned files as part of this plan.

Varian Canvas is a separate drawing/document feature. The approved Notes Canvas direction is a separate Notes board, not a replacement or extension to that feature. No existing Supabase migration for a Notes Canvas board was found.

The leanrea pass found static code markers and shipped guide documentation for Obsidian's Daily Notes, Templates, metadata editor, Bookmarks, graph, Canvas, wikilinks, backlinks/linked mentions, callouts, checklists, embeds, MathJax-style math, and Mermaid diagrams. It did not capture the UI. Use those findings as feature and syntax references only; do not copy Obsidian's local-vault storage model or infer Varian's Supabase, CRDT, encryption, or offline contracts from Obsidian.

Varian already lists `flutter_markdown_plus` and a Mermaid asset in `pubspec.yaml`; `lib/features/mermaid/` contains a Mermaid renderer. `lib/features/templates/domain/project_template.dart` models Canvas/project templates made from nodes and edges, not Notes Markdown templates. Phase 0 must verify whether existing rendering can be safely reused and whether any dependency is actually needed.

## Architecture approach

- Keep `workspace_notes.markdown_content` as canonical note text and Supabase as the server source of truth.
- Extend the existing Notes domain/index/repository/provider/editor boundaries. Preserve stable note IDs and owner/project scopes.
- Reuse existing favorites as Bookmarks where semantics match; do not add duplicate preference storage.
- Add Daily Notes using account/device local timezone and active-project/private-fallback scope. Store Notes Templates as dedicated Supabase records with explicit private or project-shared access, a management screen, and date/title/alias variables. Keep Notes Markdown templates separate from `lib/features/templates` project/Canvas templates.
- Store Notes Canvas as a separate typed JSON board state with revisions and stable note-ID references. Support project sharing, board-specific CRDT collaboration, and encrypted offline sync in v1; define revision, replay, authorization, and recovery semantics before creating migrations or UI.
- Keep migrations local/source-only. Remote Supabase operations require separate explicit authorization.

## Dependency order and phases

### Phase 0: Review and lock contracts

1. Preserve the user's confirmed Daily Notes scope/timezone, dedicated Supabase Templates with private/project scope and date/title/alias variables, typed JSON/revision Notes Canvas with project sharing, CRDT/encrypted-offline support, and selected Properties/Markdown scope. These are approved decisions, not questions to reopen.
2. Inspect current tests, migrations, RLS, repository contracts, and Notes flows. Reconcile older Notes plans only in this new plan; do not edit the untracked 2026-10-16 documents.
3. Apply the locked contracts in the spec: device-local `YYYY-MM-DD` and scoped atomic Daily Note uniqueness; template owner/project RLS, CAS revisions, inert tokens; versioned board JSON, op-ID/counter idempotency, additive movement, CRDT text edits, encrypted board replay and revocation handling; stable heading/block anchor behavior; scoped attachment storage and 25 MiB limit; existing local Mermaid renderer and sanitized SVG; local math renderer; and scope-bounded export/import. Math rendering uses `flutter_math_fork` 0.7.4, selected for local pure-Dart/Flutter rendering without remote script or WebView.

**Checkpoint:** Phase 0 contracts are recorded in the spec and ADR and verified against current implementation evidence. The user's explicit implementation request has been received, so local source and migration work may proceed. Remote Supabase changes remain unauthorized.

### Phase 1: Note semantics and navigation

1. Add typed Properties read/write using `yaml_edit` 2.2.4 with the existing YAML parser, preserving comments, unknown/invalid YAML, line endings, and exact Markdown outside the edited field.
2. Complete link handling for unresolved-note creation, linked mentions, and the approved heading/block link syntax with round-trip-safe rename and ambiguity rules.
3. Extend search, backlinks, and local/global graph while retaining project/private boundaries and the explicit 500-node render cap.

**Checkpoint:** Domain tests prove parser preservation, deterministic resolution, authorized-scope isolation, and graph totals/caps before UI integration.

### Phase 2: Daily Notes, Templates, and Bookmarks

1. Implement idempotent date-keyed Daily Notes using account/device local timezone and active-project/private-fallback scope.
2. Implement Notes-specific Supabase Template records with explicit private/project scope, a management screen, date/title/alias variables, and inert Markdown insertion. Keep them separate from Canvas/project templates.
3. Expose Bookmarks through existing per-user pin state and update navigation without duplicating records.

**Checkpoint:** Repeated opens for one local date/scope return the same note; private and project-shared templates pass RLS tests and expand approved variables deterministically; bookmarks remain private per user.

### Phase 3: Dedicated Notes Canvas

1. Implement and test the locked board contract separately from Varian Canvas: typed JSON state, private/project access, snapshot CAS, board-specific CRDT operations, encrypted offline replay/recovery, and dangling-note references.
2. Add the additive local migration and repository/provider tests. Verify all database reads/writes enforce existing owner/project authorization.
3. Build the Notes Canvas UI for board create/open, note-card placement, text cards, connectors, drag/pan/zoom, and note opening.

**Checkpoint:** Board state survives reload, references existing Notes by stable ID, cannot delete note content through card deletion, and passes project/private authorization, revision-conflict, CRDT collaboration, and encrypted offline replay tests.

### Phase 4: Markdown rendering and portability

1. Implement the approved callouts, interactive tasks, note/attachment/PDF embeds, heading/block links, `$...$`/`$$...$$` math using `flutter_math_fork` 0.7.4, and fenced Mermaid diagrams with source-preservation and renderer-safety tests. Audit `flutter_markdown_plus` and the existing Mermaid renderer before wiring the renderers; validate the selected math package across supported targets.
2. Extend Markdown/ZIP/JSON import/export round-trip for approved Properties, heading/block links, attachments/PDFs, and scope-authorized template/board references. Validate archives completely before any write.

**Checkpoint:** Existing content round-trips without silent loss; unsafe/unsupported imports fail before data changes.

### Phase 5: Verification and release readiness

1. Run focused domain, repository, provider, widget, local migration, and account/project authorization tests.
2. Run formatting, `flutter analyze`, Notes tests, and relevant tab/Canvas regression tests.
3. Inspect the complete scoped diff and git status. Preserve all existing changes, do not stage or commit, and do not run remote migrations/deployments.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Frontmatter edits rewrite unrelated YAML or Markdown | Data loss | Preserve raw source; edit one property at a time; add round-trip and malformed-YAML tests. |
| Template scope or RLS leaks private/project content | Privacy breach | Use explicit per-record scope and enforce owner/project membership in repository and database policies; test role changes and account switching. |
| Link resolution crosses private/project boundaries | Privacy breach | Use the existing scope predicate at parser/index/repository boundaries; test private, same-project, and cross-project cases. |
| Daily Notes duplicate around timezone/day boundaries | Duplicate or missing daily note | Define timezone precedence/date key and enforce idempotent server-side creation. |
| Board revision, CRDT, and offline replay disagree | Lost updates or offline corruption | Define board-specific snapshot, operation, encryption, and recovery contract before schema; do not reuse note-body CRDT operations without an adapter. |
| Math, Mermaid, attachment, or PDF rendering processes unsafe content | Script execution, malformed UI, or data exposure | Reuse vetted local rendering where possible, sanitize output, constrain asset resolution, preserve unsupported source, and test hostile input. |
| ZIP assets/links are incomplete or hostile | Broken notes or path traversal | Preflight paths, sizes, manifest, links, and assets before writes; cap archive expansion. |
| Existing in-progress changes are overwritten | Loss of user work | Keep all new documents named specifically; never edit the generic `tasks/plan.md` or `tasks/todo.md`; inspect scoped status before each edit. |

## Approved decisions and Phase 0 contracts

The user has selected the high-level product scope and storage approach. The spec and accepted ADR record these decisions; do not replace them with implementation defaults:

| Area | Approved decision | Phase 0 contract work |
|---|---|---|
| Daily Notes | Account/device local timezone; active project scope, private fallback | Timezone precedence, date key, atomic uniqueness, and account-switch behavior |
| Templates | Dedicated Supabase records; management screen; date/title/alias variables; explicit private or project-shared scope | Record schema, RLS/role rules, variable formatting/escaping, insertion, and revision conflicts |
| Notes Canvas | Typed JSON state with revisions; owner-private/project-shared scopes, project sharing, CRDT collaboration, encrypted offline sync in v1 | Snapshot/revision semantics, board CRDT, offline encryption/replay/recovery, authorization, and dangling-note behavior |
| Properties and Markdown | Text/list/number/checkbox/date-time/tags/aliases; heading/block links; note/attachment/PDF embeds; MathJax-style math; Mermaid diagrams | Parser/renderer fidelity, asset limits/resolution, dependency reuse, sanitization, and import/export contracts |

The spec now records the detailed Phase 0 contracts; this plan and the ADR follow those constraints. If implementation evidence requires changing an approved product or access decision, stop and ask the user before changing scope.

## Verification commands

Use the repository's documented commands and narrow scope first:

```powershell
dart format --output=none --set-exit-if-changed lib/features/notes test/features/notes lib/features/canvas test/features/canvas
flutter test --no-pub test/features/notes
flutter analyze
python tool/check_markdown_links.py docs/superpowers/specs/2026-10-21-notes-obsidian-parity-design.md
python tool/check_markdown_links.py docs/superpowers/plans/2026-10-21-notes-obsidian-parity.md
python tool/check_markdown_links.py tasks/notes-obsidian-parity-todo.md
python tool/check_markdown_links.py docs/decisions/ADR-001-notes-templates-and-canvas-persistence.md
```

Add focused Canvas/board tests and local-only Supabase migration checks in their implementation phases. Do not run any remote database or deployment command.
