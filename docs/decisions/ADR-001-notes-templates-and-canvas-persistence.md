# ADR-001: Store Notes Templates and Canvas in Supabase

## Status

Accepted for implementation under the user's explicit request. This ADR authorizes local source, test, and additive migration-file changes only; it does not authorize remote migrations, deployments, or data changes.

## Date

2026-10-21

## Context

Varian Notes uses Supabase as its server source of truth and already supports private/project notes, project collaboration, note-body CRDT collaboration, and encrypted offline sync. The user selected Obsidian-inspired Notes features while explicitly retaining those storage and security boundaries.

The Obsidian investigation found bundled code and shipped sandbox documentation, but no interactive UI capture succeeded. Those findings inform feature vocabulary and syntax, not Varian's data model or runtime behavior. The existing `lib/features/templates/domain/project_template.dart` models Canvas/project templates made from nodes and edges; it is not a Notes Markdown-template model.

The user confirmed these high-level choices:

- Notes Templates use dedicated Supabase records, a Notes management screen, date/title/alias variables, and an explicit private or project-shared scope per template.
- Notes Canvas is separate from Varian Canvas and uses typed JSON state with revisions. Project sharing, CRDT collaboration, and encrypted offline sync are required in the first release.

## Decision

1. Persist Notes Templates as Notes-specific Supabase records. Store Markdown as inert content, expand only the approved date/title/alias variables, and never execute template or plugin code. Each record is either private to its owner or shared in an authorized project, selected explicitly by the user.
2. Persist Notes Canvas as a separate board record with versioned typed JSON state and revision metadata. Support owner-private and project-shared scopes; project-shared boards must obey existing membership and role rules. Board edits must integrate with CRDT collaboration and encrypted offline replay in the first release; note-body CRDT operations must not be assumed to work for board layouts.
3. Keep both models behind existing Notes domain/repository/provider seams. Implement the reviewed additive migration contracts locally. Do not apply migrations to remote services without separate authorization.

The concrete Phase 0 contracts are recorded in the [implementation spec](../superpowers/specs/2026-10-21-notes-obsidian-parity-design.md). They fix the initial record fields, RLS rules, CAS behavior, board JSON and operation semantics, encrypted replay, link anchors, attachment limits, renderer constraints, and export scope. Implementations must preserve those contracts unless new source evidence proves a conflict that changes an approved product decision; such a conflict returns to the user.

## Alternatives Considered

### Store Templates as files in a local vault

Not selected. Varian Notes remains Supabase-backed, account-scoped, and project-shareable; a local-vault storage model would create a second source of truth and conflict with encrypted offline sync.

### Reuse the existing Project/Canvas Template model

Not selected. That model stores diagram selections of Canvas nodes and edges. Notes Templates contain Markdown and have different scope, variable, and insertion semantics.

### Store each Canvas card and edge as independent normalized rows

Not selected for v1. The user selected a typed JSON board state with revisions. Revisit only if implementation evidence shows the JSON contract cannot satisfy the approved requirements.

### Defer board CRDT and encrypted offline support

Not selected. The user requires both for the first release. The implementation must define a board-specific operation/replay adapter and test it against the existing encrypted offline path.

## Consequences

- Template RLS must distinguish owner-private records from project-shared records and enforce membership/role checks in database boundaries.
- Template variable expansion must be deterministic and non-executable. Project/private scope must survive account changes, imports, and exports without leaking content.
- Canvas uses the schema version, revision CAS, operation idempotency, snapshot reconciliation, encrypted replay, recovery, and tombstone behavior fixed in the spec; those contracts require focused migration/domain tests.
- Notes cards reference stable note IDs. Board card deletion must not delete or mutate the note body.
- Additive migration source and local migration-contract tests are expected if new records are needed. No remote migration, deployment, or data mutation is included.

## Implementation Boundary

The user explicitly requested implementation after approving the product direction. Local source, tests, and additive migrations may proceed under this ADR. Apply no migration remotely, deploy no function, and mutate no shared/production data without separate authorization.

## Related Documents

- [Notes parity spec](../superpowers/specs/2026-10-21-notes-obsidian-parity-design.md)
- [Notes implementation plan](../superpowers/plans/2026-10-21-notes-obsidian-parity.md)
- [Notes task list](../../tasks/notes-obsidian-parity-todo.md)
