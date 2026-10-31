import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261021140000_workspace_notes_canvas.sql',
  ).readAsStringSync().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  test('creates a versioned, revisioned board independent of note rows', () {
    expect(
      migration,
      contains('create table public.workspace_note_canvas_boards'),
    );
    expect(migration, contains('state_json jsonb not null'));
    expect(migration, contains('crdt_snapshot_json jsonb not null'));
    expect(migration, contains('revision integer not null default 1'));
    expect(migration, contains('snapshot_server_sequence bigint not null'));
    expect(
      migration,
      contains('workspace_note_canvas_state_valid(state_json)'),
    );
    expect(migration, contains('octet_length(state_json::text) <= 5242880'));
    expect(migration, contains('unique (board_id, op_id)'));
    expect(
      migration,
      contains('unique (board_id, replica_id, replica_counter)'),
    );
    expect(
      migration,
      contains('server_sequence bigint generated always as identity'),
    );
  });

  test('enforces read/edit scope and same-scope readable note references', () {
    expect(migration, contains('enable row level security'));
    expect(
      migration,
      contains('public.workspace_note_can_read(owner_user_id, project_id)'),
    );
    expect(
      migration,
      contains(
        'public.workspace_note_can_edit(v_board.owner_user_id, v_board.project_id)',
      ),
    );
    expect(
      migration,
      contains('n.project_id is not distinct from p_project_id'),
    );
    expect(migration, contains('n.deleted_at is null'));
    expect(
      migration,
      contains('workspace_note_canvas_realtime_topic_can_read'),
    );
    expect(
      migration,
      contains('grant select on public.workspace_note_canvas_boards'),
    );
  });

  test('keeps board state, CRDT snapshot, and version vector aligned', () {
    expect(
      migration,
      contains(
        'create or replace function public.workspace_note_canvas_snapshot_valid',
      ),
    );
    expect(
      migration,
      contains("p_snapshot->'materialized_state' is distinct from p_state"),
    );
    expect(
      migration,
      contains(
        "p_snapshot->'version_vector' is distinct from p_version_vector",
      ),
    );
    expect(migration, contains('workspace_note_canvas_snapshot_consistent'));
    expect(
      migration,
      contains('p_version_vector is distinct from v_expected_vector'),
    );
  });

  test('requires causal dependencies and existing operation targets', () {
    expect(migration, contains('v_counter <> v_known_counter + 1'));
    expect(migration, contains('workspace_note_canvas_dependency_unavailable'));
    expect(
      migration,
      contains('workspace_note_canvas_operation_targets_valid'),
    );
    expect(migration, contains('workspace_note_canvas_target_unavailable'));
    expect(migration, contains("operation_json->>'type' = 'text_insert'"));
    expect(
      migration,
      contains('unique (board_id, replica_id, replica_counter)'),
    );
  });

  test('uses append, delta, and snapshot compare-and-swap RPCs', () {
    expect(migration, contains('append_workspace_note_canvas_operation'));
    expect(migration, contains('get_workspace_note_canvas_delta'));
    expect(migration, contains('materialize_workspace_note_canvas'));
    expect(migration, contains('create_workspace_note_canvas_board'));
    expect(migration, contains('v_board.revision <> p_expected_revision'));
    expect(migration, contains('on conflict (board_id, op_id) do nothing'));
    expect(migration, contains('p_snapshot_server_sequence > v_last_sequence'));
    expect(
      migration,
      contains(
        'create or replace function public.rehome_workspace_notes_before_project_delete()',
      ),
    );
    expect(migration, contains('update public.workspace_note_canvas_boards'));
    expect(migration, contains('owner_user_id = old.owner_id'));
  });
}
