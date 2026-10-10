# Two-way canvas collaboration regression

## Failure reproduced

The room could report live while local canvas edits never appeared on the other
client. Register conflict resolution compared actor IDs before counters. A
previous session with a higher-sorting actor ID could therefore prevent both a
new host and a new guest from replacing or deleting existing items.

## Synchronization rules

- Generate each new operation counter above every counter already observed in
  the session version vector, including restored snapshots.
- Compare register timestamps by counter first, then actor ID for concurrent
  ties. Retain the existing identity ordering for stored text sequences and lists.
- Apply the same timestamp rule to node/edge replacements, deletions, field
  registers, strokes, comment registers, and text formatting.
- Do not reapply an old field register over a newer whole-node replacement.
- Use specialized text/stroke operations only for isolated text/stroke edits.
  Combined geometry, style, name, or payload changes use the full node update.

The operation JSON shape and database schema are unchanged. Restart both clients
with the updated app; an old client still uses the broken merge rule. Existing
rooms and documents do not need to be deleted or recreated for this fix.

## Automated coverage

- `test/features/collaboration/crdt_engine_test.dart` checks alternating host/guest
  edits against an old snapshot, concurrent updates, reordered/duplicate delivery,
  and field-register precedence.
- `test/features/collaboration/collaboration_two_client_test.dart` connects two
  real Supabase SDK clients and Riverpod controllers to a loopback HTTP/WebSocket
  test backend. It checks shape properties, geometry, insertion, deletion,
  connectors, combined text changes, and Drawing Paper movement.

The wire test uses a local test backend, not the linked Supabase project; it does
not prove production RLS, network reliability, or a 24-hour session.

## Manual smoke test

1. Fully restart the desktop app and Chrome app from the updated source.
2. Have the guest join the host's existing room ID.
3. Alternate edits on the same shape: move, resize, change corners/color, delete,
   then undo. Check the actual canvas on both clients, not only the live badge.
4. Repeat with text plus resizing and with Drawing Paper movement.
