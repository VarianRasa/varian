# Obsidian-Inspired Notes Workspace Design

## Status

Approved for implementation on 2026-10-16. The design uses official Obsidian Help documentation and current Varian Notes source. Obsidian was not installed locally, so no REA reverse-engineering evidence is available.

## Intent

Evolve Notes from a flat list and single-note Markdown editor into a private, connected knowledge workspace. Prioritize links and navigation, with organization and authoring controls close at hand. This is an Obsidian-inspired workflow, not a visual clone or a claim of feature parity.

## Goals

1. Provide a responsive Notes workspace with a navigable note library, full-account search, editor, and contextual panels.
2. Support standard wiki links (`[[Note title]]` and `[[Note title|alias]]`), inline suggestions, unresolved-link handling, stable target identity, and backlinks.
3. Derive tags from Markdown and expose note properties from full YAML frontmatter, keeping Markdown as canonical note content.
4. Provide a graph view of links among active Notes owned by the signed-in user, with a clear 500-node rendering cap and filtering.
5. Preserve per-account privacy, RLS, revision-based conflict protection, autosave, Trash/restore, export, and note-tab behavior.
6. Add focused parser, provider, repository/RPC contract, and widget tests; do not change unrelated project files.

## Decisions from the user

- Keep standard `[[title]]`/`[[title|alias]]` syntax and make selected links stable across renames through CAS-protected reference updates.
- Use a full YAML parser for frontmatter properties.
- Search, backlinks, and graph cover all active Notes belonging to the signed-in account; graph rendering may be bounded.
- Review this final design before implementation.

## Design

### Workspace and navigation

The `/notes` route becomes the workspace entry point. On desktop it uses a left navigation/library, central editor, and optional right contextual panel for outline, properties, backlinks, or graph. The left side provides search, create, recent notes, tag filters, and Trash navigation. On narrow screens, panels collapse behind explicit navigation/toggles. Existing `/notes/:noteId` and `/notes/trash` URLs remain compatible. Opening a note selects its existing account-bound tab; the active route reflects the selected note, and existing save/flush behavior remains in force.

### Wiki links, stable identity, and renames

New links inserted from the suggestion picker use readable Obsidian syntax plus a Varian identity marker, for example `[[Systems thinking]]<!--varian-note-id:UUID-->`. An alias uses `[[Systems thinking|Systems]]<!--varian-note-id:UUID-->`. A marker is valid only when it is exactly adjacent to the closing `]]`, on the same line, outside inline/fenced code, and contains one canonical UUID. A malformed, separated, or conflicting multiple marker is ignored; the link falls back to unique case-insensitive title resolution and remains unresolved if ambiguous. Repeating the same valid target marker on separate link occurrences is allowed.

The source editor exposes and permits editing of the HTML comment because Markdown remains canonical. Preview hides valid markers. The existing `.md` export preserves them exactly; no import workflow is added in this milestone. If a valid marker remains but the link text is changed, the ID is authoritative: preview identifies the actual target and flags the stale text, with actions to update the label or remove the marker and resolve by title. Removing or pasting without a marker falls back to title resolution. Duplicate note titles remain allowed; choosing a result in the suggestion picker writes the selected target ID. A deleted target is unavailable while in Trash; restoring it makes marked links resolve again.

On rename, the client scans the signed-in account's active Notes. It updates marked references to the target and upgrades unmarked references only when the old title uniquely resolves to that target. If any unmarked references are ambiguous, the rename is blocked until the user resolves or removes them. The dialog lists the affected source-note titles and a `Resolve links` action opens the library filtered to those notes. This prevents a formerly ambiguous `[[title]]` from silently resolving to a different note after a rename. Trashed Notes are not rewritten; their marked links resolve by ID after restore, while their raw label may remain old until edited.

A new owner-scoped Postgres RPC performs the target rename and active-source rewrites in one transaction. Input includes the target ID/revision, requested title, the full active-note ID/revision snapshot used for link discovery, and one proposed Markdown replacement plus expected revision for each changed source. Zero changed sources is valid. The target may also be a source for a self-link; it is de-duplicated and updated once. Duplicate source IDs, stale snapshots, stale revisions, missing rows, or deleted rows reject the whole operation.

The RPC derives the caller from `auth.uid()` and accepts no owner ID. It runs as an invoker under existing RLS, locks target/source rows in stable ID order, verifies every affected row belongs to the caller and is active, checks the full note snapshot and expected revisions, then applies only the supplied title/body fields. It does not grant more authority than existing owner-scoped note updates. Client code constructs body replacements solely by changing marked-link target labels and preserving aliases/other text; tests verify this transformation. A per-owner transaction lock shared by note writes and the rename RPC closes the discovery-to-write race; this briefly serializes writes for that account during rename. Any failed check rolls back the transaction. The client keeps drafts, refreshes the note collection, and offers explicit retry or reload; no automatic overwrite occurs. Add only a local migration source, never apply it remotely in this task.

### Properties, tags, search, and graph

A full YAML parser reads frontmatter without rewriting it automatically. Parsed YAML mappings, sequences, and scalars appear in the properties panel and contribute searchable values. Invalid YAML remains byte-for-byte intact, is shown as a parse error, is not silently discarded, and remains searchable as raw Markdown. The existing `yaml` package in the lockfile is promoted to a direct dependency without upgrading unrelated packages. Hashtag parsing ignores fenced and inline code. Tags from frontmatter and body are merged for filtering.

The account-scoped provider supplies the full active note collection for search, link resolution, backlinks, tags, and graph construction. Deleted notes are excluded from these views and remain accessible through Trash. The graph includes isolated notes and active links, renders at most 500 nodes at once, and displays the total plus an explicit filter/focus action when capped. Search and backlinks remain complete and uncapped.

### Errors and recovery

- A stale snapshot/revision or CAS conflict rolls back the whole rename. Preserve all drafts, show a generic conflict banner, refresh current notes, and offer `Reload` or explicit `Retry`; never merge or overwrite silently.
- A missing, deleted, or no-longer-owned note returns the same unavailable message without disclosing another account's data.
- Network failures keep the rename draft and show `Retry`.
- Malformed markers and unresolved/ambiguous links are surfaced as unresolved; they are not auto-guessed. Ambiguous legacy references block rename and can be repaired through the filtered library action.

### Existing editor and safety behavior

Retain Markdown as canonical content and keep current source/preview, autosave, conflict recovery, export, and soft-delete flows. Do not weaken account checks, RLS, or revision CAS. Do not log note content or frontmatter. Keep existing note-tab identity and account-switch clearing.

## Constraints and rollout

- Supabase remains the source of truth; this does not create local filesystem vaults or offline-first synchronization.
- A local migration source is required for the owner-scoped transactional rename RPC and per-owner write lock. Do not apply it to any remote/shared/production project as part of this task.
- Preserve all unrelated modified and untracked checkout content. Do not stage or commit.

## Success criteria

- Desktop and narrow-screen layouts provide note navigation, editing, and contextual panels without breaking current editor behavior.
- Link parsing covers aliases, ID markers, unresolved/malformed/duplicate targets, code contexts, source edits, export, and rename updates with deterministic tests.
- Rename updates are atomic, owner-scoped, revision-protected, and limited by the client transformation to marked-link rewrites; failures leave all affected rows unchanged and preserve editor drafts.
- Search, backlinks, tags, and graph cover all active Notes for the current account and exclude Trash and other accounts; graph cap is explicit.
- Full YAML frontmatter is displayed and searchable without mutating stored content; invalid frontmatter is preserved and clearly reported.
- Existing revision conflict, account-switch, Trash/restore, export, routing, and tab tests remain green.
- Focused Notes tests, Dart formatting, and Flutter analysis pass. No unrelated diff or remote database change is introduced.
