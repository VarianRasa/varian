# Spec: Obsidian-Inspired Notes for Varian

## Status

Approved for implementation by the user's explicit request. High-level product decisions are fixed; the Phase 0 contracts below are implementation constraints, not open product questions. The request authorizes local source and migration changes only. It does not authorize remote Supabase migrations, deployments, or data changes. This revision preserves the untracked 2026-10-16 Notes documents; they remain unchanged.

**ADR:** [Notes storage ADR](../../decisions/ADR-001-notes-templates-and-canvas-persistence.md)

## Objective

Evolve Varian's existing Notes into an Obsidian-inspired Markdown knowledge workspace. Preserve Varian's Supabase storage, project sharing, CRDT collaboration, and encrypted offline sync. This is a feature and workflow migration, not a move into a local-folder vault or a visual clone of Obsidian.

## User-approved decisions

- **Scope:** Obsidian-inspired core workflows: typed Properties, wikilinks/unresolved links, heading/block links, linked mentions, graph navigation, callouts, checklists, approved note/attachment/PDF embeds, math and diagrams, Daily Notes, Templates, Bookmarks, and Canvas. Initial property types are text, list, number, checkbox, date/time, tags, and aliases.
- **Storage:** Supabase remains the server source of truth. Preserve current project access, collaboration, encrypted offline sync, history, and Trash.
- **Attachments:** use `![[attachment:<uuid>]]`, cache offline bytes encrypted with the Notes key, and rehome metadata and bytes with a Note when its scope changes or its project is deleted.
- **Daily Notes:** use the account/device local timezone; use the active project scope, with private scope when no project is active.
- **Templates:** use dedicated Supabase records, a Notes management screen, and initial variables for date, title, and aliases. Each template may be private or project-shared; users select its scope.
- **Notes Canvas:** create a dedicated board separate from Varian Canvas. Use typed JSON board state with revisions; support project sharing, CRDT collaboration, and encrypted offline sync in the first release.
- **Gate:** The user has explicitly requested implementation. Local source, tests, and additive migration files may change after Phase 0 contract review. Remote Supabase changes remain separately unauthorized.

## Existing implementation baseline

The current Notes feature already provides Markdown source/preview editing, autosave and revision conflict recovery, note versions, Trash/restore, folders, favorites, search, tag filters, project scope, Markdown/ZIP/JSON import, ZIP and single-note export, YAML frontmatter parsing, wikilinks with stable note-ID markers, direct backlinks, and a graph capped at 500 visible notes. It also has project collaboration through a Notes CRDT path and encrypted offline storage/sync.

The main code boundaries are `lib/features/notes/domain/`, `data/`, `state/`, and `presentation/`; routing is in `lib/main.dart`. The existing pin preference is the starting point for Bookmarks. The Notes editor currently displays parsed frontmatter but does not provide an Obsidian-style typed property editor. Backlinks currently come from explicit wiki links; linked mentions are not present in the inspected implementation.

The existing Varian Canvas is a distinct feature with its own document and tab flow. The new Notes Canvas must not replace or silently change it. The untracked [workspace design](2026-10-16-obsidian-inspired-notes-workspace-design.md), [Notes maturity](2026-10-16-notes-maturity-design.md), and [Notes expansion](2026-10-16-notes-expansion-design.md) remain preserved historical plans; this approved spec is the implementation source of truth for the current scope.

## Scope and requirements

### 1. Note authoring and properties

- Keep Markdown as the canonical note body. Support editing YAML frontmatter as typed Properties for text, list, number, checkbox, date/date-time, tags, and aliases.
- Preserve unedited frontmatter values, unknown keys, comments, and invalid YAML. Report parse errors; never silently normalize or discard source content. Use `yaml_edit` 2.2.4 for key-level syntax-preserving updates, after validating with the existing `yaml` parser; this dependency is required for comment/whitespace preservation.
- Continue title/body/tag search and add searchable property values across notes the user may read. Offer scope filters without resolving links across private/project or cross-project boundaries.
- Support Obsidian-style callouts (including folding), interactive task lists, note/attachment/PDF embeds, inline math (`$...$`), block math (`$$...$$`), and fenced Mermaid diagrams. Preserve source on edits and when rendering unsupported syntax; do not execute plugins or arbitrary embedded scripts. The inspected docs show callout, MathJax, Mermaid, and note/image embed syntax, but do not establish interactive UI behavior. Follow the scoped attachment and safe rendering contracts below. Interactive task changes must save back to Markdown without losing unrelated content.

### 2. Links, backlinks, and graph

- Preserve `[[title]]`, `[[title|alias]]`, and Varian's stable note-ID markers. Keep valid IDs authoritative so duplicate titles or renames cannot silently retarget links.
- An unresolved link can be created as a new note through an explicit user action. Support heading and block links with stable parsing, navigation, and round-trip import/export; follow the rename and duplicate-anchor rules in the locked contract below.
- Backlinks include explicit linked notes and linked mentions. Ignore code examples and fenced code when indexing either.
- Provide global graph and local graph views, tag/property filters, isolated-node control, and a clear count when the existing 500-node render cap is reached.

### 3. Daily Notes, Templates, and Bookmarks

- Daily Notes uses the account/device local timezone and the active project scope, falling back to private scope when no project is active. It opens the existing note for that date or creates exactly one. The date key, timezone precedence, and atomic uniqueness contract must be deterministic and account-safe.
- Templates are dedicated Supabase records with Markdown content and a Notes management screen. Each record is explicitly private or project-shared. The first release expands date, title, and aliases as inert values; applying a template preserves existing content/frontmatter unless the user explicitly chooses to replace it. Template reads/writes must follow the selected owner/project scope and existing RLS rules.
- Bookmarks reuse current per-user pin/favorite data where its semantics fit. Do not create duplicate preference records for the same behavior.

### 4. Notes Canvas

- Add a dedicated board within Notes, with note cards linked by stable note IDs, movable text cards, and connectors. Selecting a note card opens the existing Notes editor; deleting a card does not delete its note.
- Store typed JSON board state with a revision in Supabase. Support both owner-private and project-shared board scopes, with project sharing required in the first release. Board collaboration uses CRDT and encrypted offline sync. Additive local migrations and repository contracts must preserve RLS, project roles, revision checks, and encryption boundaries.
- Keep Notes Canvas separate from Varian Canvas. Implement the board-specific CRDT operation/replay and revisioned JSON snapshot contracts below; do not assume note-body CRDT operations automatically cover board layouts.

### 5. Import/export and compatibility

- Keep current Markdown/ZIP/JSON import and Markdown/ZIP export. Extend preflight/round-trip behavior for typed frontmatter, heading/block links, template records where authorized, board references where supported, attachment/PDF assets, math, and Mermaid diagrams. Define whether project/private templates and boards are included in each export; never leak records across scopes.
- Reject unsafe archive paths and malformed manifests before writes. Do not silently replace existing notes or overwrite current data.
- Preserve existing note IDs and Varian link markers during export. For imported content, remap IDs only through an explicit, validated manifest mapping.

## Architecture and security boundaries

- `workspace_notes.markdown_content` remains canonical note text; Supabase remains authoritative for note records.
- Extend existing Notes domain/index/repository/provider seams. Reuse existing pin, folder, history, Trash, tab, and encrypted offline infrastructure instead of duplicating it.
- All reads, writes, link suggestions, backlinks, graph edges, and board references must obey current account/project scope. Enforce project authorization in database/RPC boundaries, not only in UI state.
- Preserve revision/CAS conflict handling, draft recovery, CRDT behavior, account-switch clearing, and authenticated tab identity. Never add last-write-wins behavior.
- Never log note content, frontmatter, keys, passphrases, or archive payloads. Do not weaken RLS, auth, membership checks, or encryption.
- Create migration source only. No remote Supabase migration, deployment, or data mutation is included without separate authorization.
- Do not add dependencies without an approved need. Do not execute Obsidian community plugins or introduce an arbitrary plugin runtime.

## Approved design decisions

1. Keep `workspace_notes` and Markdown as the canonical note store; do not emulate Obsidian's local vault storage.
2. Reuse the existing per-user pin preference for bookmarks.
3. Store Notes Canvas boards separately from Markdown notes and Varian Canvas documents. Use a typed JSON board state with revisions; support project sharing, board-specific CRDT collaboration, and encrypted offline sync in v1. Define snapshot, revision, operation, and replay contracts before schema work.
4. Store Notes templates as dedicated Supabase records with inert Markdown bodies, date/title/alias variables, and explicit private or project-shared scope. Keep this Notes-specific model separate from the existing Canvas/project-template feature in `lib/features/templates/domain/project_template.dart`; never execute template content.

## Testing strategy

- Add pure domain tests for YAML read/write preservation, all approved property types, wiki-link identity, unresolved links, linked mentions, aliases, heading/block links, and graph filtering/caps.
- Add repository/provider and local migration-contract tests for template private/project RLS, role changes, date-key uniqueness, CAS, board CRDT replay, encrypted offline sync, concurrent edits, imports, attachment/PDF access, and board reference authorization. Run local-only database tests where needed; never target shared/production services.
- Add renderer/editor tests for callouts, checklist edits, note/attachment/PDF embeds, MathJax-compatible inline/block math, Mermaid diagrams, source preservation, and unsafe/unsupported input.
- Add widget tests for desktop/narrow layouts, Properties, Daily Notes, Templates, Bookmarks, graph navigation, Canvas interactions, errors, retry, and account changes.
- Run the repository's documented checks: `dart format --output=none --set-exit-if-changed lib test tool`, `flutter analyze`, focused `flutter test --no-pub test/features/notes`, and `python tool/check_markdown_links.py` for changed Markdown docs. Run full Flutter tests if focused checks pass and environment permits.

## Success criteria

- User can edit typed Properties and frontmatter round-trips without corrupting unknown or invalid source.
- Wiki links, unresolved-link creation, backlinks/linked mentions, and graph navigation resolve only within authorized scope.
- Daily Notes are idempotent by local date and the approved project/private scope. Templates support private and project-shared records, expand date/title/aliases deterministically, and never execute content. Bookmarks reuse existing per-user preferences.
- Notes Canvas is separate from Varian Canvas, persists typed JSON state with revisions, supports project sharing, CRDT collaboration, and encrypted offline sync, and references notes without duplicating or deleting their content.
- Heading/block links, attachment/PDF embeds, inline/block math, and Mermaid diagrams round-trip safely; imports/exports do not cross private/project scopes.
- Existing private/shared notes, history, Trash, imports/exports, CRDT collaboration, encrypted offline sync, and account-switch safety continue to work.
- Focused tests, formatting, Flutter analysis, and Markdown link checks pass. No unrelated worktree content is changed and no remote resource is touched.

## Phase 0 implementation contracts

The user has confirmed the product scope and high-level data choices. The contracts below are now locked implementation constraints, not unanswered product questions:

| Area | Confirmed decision | Locked contract |
|---|---|---|
| Daily Notes | Account/device local timezone; active project scope, private fallback | Device-local `YYYY-MM-DD`, selected Notes scope, partial unique keys, atomic insert-or-return RPC, account-generation fencing |
| Templates | Dedicated Supabase records; manager screen; date/title/alias variables; per-record private or project-shared scope | Notes-specific schema, existing project RLS roles, revision CAS, inert `{{date}}`/`{{title}}`/`{{aliases}}` expansion, same-scope bundles |
| Notes Canvas | Typed JSON state plus revisions; project sharing, CRDT collaboration, encrypted offline sync in v1 | Versioned bounded board JSON, unique operation IDs/counters, additive move deltas, text CRDT, CAS snapshots, encrypted account-scoped replay |
| Markdown | Heading/block links; note/attachment/PDF embeds; inline/block math; Mermaid diagrams | Deterministic anchor rules, 25 MiB scoped attachments, internal-ID-only embeds, local sanitized Mermaid and Math rendering, bounded scope-aware archives |

Use Obsidian's documented reference syntax where compatible: `[[note#heading]]`, `[[note#^block-id]]`, `![[note]]`, `$...$`, `$$...$$`, and fenced `mermaid` blocks. The shipped docs identify MathJax and Mermaid; they do not establish Varian renderer behavior. Any change to the confirmed scope or access model returns to the user for approval.

### Locked implementation contracts

**Daily Notes.** No persisted account timezone is present in the current schema. Capture the device-local civil date at the time the user opens Daily Notes, serialize the key as `YYYY-MM-DD`, and never derive it from UTC or locale-formatted text. In the Notes workspace, the currently selected scope is the active scope: a selected project ID is project scope; no selection is private scope. A private daily note is unique by `(owner_user_id, daily_note_date)`; a project daily note is unique by `(project_id, daily_note_date)`. Enforce both with partial unique indexes and use an authenticated atomic get-or-create RPC that inserts on conflict without updating existing content, then returns the existing row. Private reads/writes remain owner-only; project reads and edits follow the existing Notes member/read and owner/editor/write rules. Capture the expected account and scope before the request, reject stale results after account/generation changes, and clear active editor state on account switch. Different devices may derive different civil dates while in different timezones; uniqueness remains per stored date and scope.

**Templates.** Add a Notes-specific `workspace_note_templates` record with UUID ID, immutable creator/owner ID, nullable project ID, title, Markdown content, revision, and timestamps. A null project ID means private; a project ID means shared in that project. Private access is owner-only. Shared reads require current project membership; writes/deletes require the existing project owner/editor permission. Keep the creator immutable. Project deletion follows the existing Notes rehome policy, moving shared records to the project owner's private scope. Start at revision 1; updates use compare-and-swap on `(id, expected_revision)` and increment exactly once. A zero-row update is a conflict, never last-write-wins. Template tokens are exactly `{{date}}`, `{{title}}`, and `{{aliases}}`; expand once, as inert text, with ISO date, YAML-safe scalar/list serialization in frontmatter, and Markdown-escaped literal values in the body. Unknown tokens remain unchanged. Applying inserts at the editor selection by default; replacing current content requires an explicit user action. Normal note revision/CRDT save and conflict recovery remain authoritative.

**Notes Canvas.** Store boards separately from `workspace_notes` and Varian Canvas. Version-1 board JSON has `schema_version: 1`, `cards`, and `edges`. Each card has a stable UUID and one discriminant (`note` with stable `note_id`, or `text` with Markdown); both have finite bounded position/size values. Edges have stable UUIDs and card endpoint IDs. Cap a board at 500 cards, 2,000 edges, 100 KiB per text card, and 5 MiB serialized state. A board row holds private/project scope, owner/creator, current state, and a monotonically increasing materialized revision. Every snapshot write uses expected-revision CAS; operation append sequence is separate from the snapshot revision.

Use a board-specific operation stream with unique `(board_id, op_id)` and `(board_id, replica_id, replica_counter)` keys, causal dependencies, and server sequence numbers. Version 1 operations cover card/edge creation and tombstoning, card movement as additive deltas (so concurrent moves commute), and text-card insert/delete operations using the existing sequence-CRDT semantics without treating a board as a note. Tombstoned cards are not rendered; their operations and inbound edges are retained, and undo creates a new card ID. Appends are idempotent; materialization conflicts refetch the snapshot/delta, merge unapplied operations, and retry without dropping queued edits. Board snapshots, outbox entries, and checkpoints use the existing account-scoped AES-GCM Notes key/AAD path, with board-specific encrypted local records. Replay rechecks account, project scope, and current edit permission; denied project queues pause and retain ciphertext for recovery, not plaintext replay. A known offline limitation remains: server revocation cannot erase a previously downloaded encrypted cache while the device is disconnected; after reconnect, denied boards are removed from active UI and no queued writes replay. A note card may reference only a readable note in the same private-owner or project scope; references do not cascade-delete notes. Trashed, deleted, or no-longer-readable targets render as unavailable while retaining the stable ID. Project deletion follows existing Notes rehome behavior.

**Links and anchors.** Keep stable note-ID markers authoritative. Title-only links resolve only when exactly one readable note with that title or alias exists in the same private-owner/project scope; ambiguous or inaccessible targets stay unresolved and never auto-retarget. Heading fragments use normalized lowercase slugs with punctuation removed and spaces changed to hyphens; duplicate slugs receive document-order suffixes `-1`, `-2`, etc. A heading rename changes its slug and leaves old links unresolved; do not silently rewrite text. Explicit `^block-id` anchors are case-sensitive and must be unique within a note; duplicate or missing block IDs remain unresolved. Ignore code spans, fenced code, frontmatter, link destinations, and existing wikilinks while indexing linked mentions.

**Attachments, PDFs, rendering, and export.** Add scoped attachment metadata and a private `workspace-note-assets` Storage bucket rather than broadening the project-only `assets` bucket. Private paths bind to the owner; project paths bind to the project and use existing member/read and owner/editor/write rules. Resolve embeds by stable attachment ID in the note's scope only; reject external URLs, local paths, traversal, and arbitrary bucket paths. Allow PNG/JPEG/GIF/WebP and PDF only, verify file signatures before rendering, and cap each file at 25 MiB. Resolve only `![[attachment:<uuid>]]` references to metadata in the note's exact scope. Open PDFs from authorized bytes through the existing `pdfrx` viewer; do not persist signed URLs in Notes or Markdown. Cache offline bytes only as AES-GCM ciphertext using the Notes key, with account-, attachment-, and scope-bound AAD; recheck account and current access before reads or replay.

Scope changes and project deletion use a durable server-side rehome queue because PostgreSQL cannot atomically move Storage objects. An idempotent worker copies each object from its project-bound path to the owner's private path, validates the allowed signature and size, and verifies the copied bytes before changing the metadata pointer. It deletes the source only after the pointer switch. A scope change or project deletion stays pending until every copy and source cleanup succeeds; failures retain recoverable state and retry, never delete the only verified copy. The queue and object state are private, server-validated, and cannot accept arbitrary bucket paths. A project must remain available while its Notes rehome is pending.

Existing ZIP preflight ceilings remain: 25 MiB compressed, 100 MiB expanded, 100 files, and 10 MiB per Markdown file. The legacy Markdown and v1 ZIP exports remain note-only. A versioned v2 note bundle includes attachment assets only from its selected scope, with an explicit ID/path manifest; import validates every entry, signature, mapping, and limit before any write. Templates and board snapshots are included only in a separate explicit same-scope Notes workspace bundle. A bundle has one private-owner or project scope; it never mixes private/project records or cross-project references. Workspace bundles contain board snapshots, not operation logs, presence, history, sync state, signed URLs, keys, or credentials. Imports generate fresh IDs and remap included note, attachment, template, board, and link references; references to excluded records remain unresolved. Mermaid uses the bundled local renderer with strict security and `MermaidSvgSanitizer`. Math uses `flutter_math_fork` 0.7.4 for local pure-Dart/Flutter rendering, with no remote script or WebView. Markdown preview disables raw HTML and remote/local-path images, handles only approved internal note/attachment IDs, and preserves unsupported or malformed source verbatim. Render/parse failures show source, not a lossy rewrite. The math dependency is needed by the approved scope and must be validated on every supported Flutter target before release.

## REA evidence and limitations

- The local Obsidian `obsidian.asar` inventory was complete with 397 entries and no integrity contradictions: `ev_8b641c7742406f954c0039acff9f3e5ee62cf3a648783b688d5e7fb5681636eb`.
- Scoped static analysis of Obsidian's `app.js` confirmed bundled core-plugin references, but the semantic graph was partial and capped: `ev_bb27159afb1e6da5255df03f964fb8fa390c95b9530f6774a5de1345ac1b8f07`.
- A separate leanrea CLI pass copied and extracted the archive with cached `@electron/asar` 4.2.0. The packaged `package.json` reports `obsidian-dev` version `1.14.4`; the inspected source archive SHA-256 was `146ef8470d8cbb4a6db209bdc19bf2bad13350444186c0fd93c31087b142b92f`.
  - Static `app.js` markers include Daily Notes (`getDailyNote` at byte 1,652,068; plugin declaration at 3,442,670), Templates (`resolveTemplateFile` at 1,674,135; plugin declaration at 3,777,752), Canvas creation (`actionNewCanvas` at 1,438,884), graph plugin registration (2,726,801), typed metadata editor/frontmatter save code (1,860,093), checklist editing (1,964,385), and Bookmarks handling (1,562,946). These markers establish bundled code paths, not that each UI flow was exercised.
  - Shipped sandbox docs describe unresolved wikilink creation, backlinks, linked mentions, and local graph navigation (`sandbox/Guides/Link notes.md:23-46`); callout syntax/folding (`sandbox/Formatting/Callout.md:8-54`); note embeds (`sandbox/Formatting/Embeds.md:1-7`); MathJax-style `$...$`/`$$...$$` (`sandbox/Formatting/Math.md:1-13`); and Mermaid fenced diagrams (`sandbox/Formatting/Diagram.md:1-17`). The inspected Formatting docs include image examples (`Images.md:1-16`) but no PDF example; PDF support is based on the user's release-scope decision, not claimed as an observed Obsidian behavior. Documentation is reference material, not runtime evidence.
- Two REA interactive Electron scenario attempts timed out before capturing the window. In the follow-up run with the isolated profile and empty test-vault paths, REA's `electron.launch` waited 60 seconds after adding `--inspect=0`. The shipped `Obsidian.exe` has `EnableNodeCliInspectArguments` disabled (`ev_ea7feb5b238145a7fbebddd26124fab672428495ffcba0bc7b50c3fe0358c1e3`), so Obsidian does not honor that Inspector launch flag. Chromium logged a separate DevTools CDP address, but REA returned no window capture; the process and port were closed on follow-up. No interactive UI behavior is confirmed by this investigation.
