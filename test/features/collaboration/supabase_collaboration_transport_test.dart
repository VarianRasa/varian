import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/collaboration/data/supabase_collaboration_transport.dart';
import 'package:varian/features/collaboration/domain/crdt_primitives.dart';

void main() {
  test('uses a mutable payload for room-disabled broadcasts', () {
    final payload = roomDisabledBroadcastPayload();

    payload['reason'] = 'test';

    expect(payload, {'reason': 'test'});
  });

  test('unwraps the Realtime broadcast envelope', () {
    final operation = <String, dynamic>{
      'projectId': 'project-a',
      'opId': 'actor-a:1',
      'dot': {'actorId': 'actor-a', 'counter': 1},
    };

    expect(
      extractCrdtOperationPayload({
        'event': 'crdt_operation',
        'payload': operation,
      }),
      equals(operation),
    );
  });

  test('ignores payloads without an operation dot', () {
    expect(
      extractCrdtOperationPayload({'event': 'crdt_operation', 'payload': null}),
      isNull,
    );
  });

  test('unwraps cursor broadcast payloads', () {
    expect(
      extractCollaborationPresencePayload({
        'event': 'cursor_update',
        'payload': {'userId': 'client-guest', 'x': 12.0, 'y': 24.0},
      }),
      equals({'userId': 'client-guest', 'x': 12.0, 'y': 24.0}),
    );
  });

  test('unwraps collaboration control broadcast payloads', () {
    final control = <String, dynamic>{
      'eventId': 'event-1',
      'projectId': 'project-a',
      'actorId': 'client-host',
      'targetUserId': 'client-guest',
      'controlType': 'screen_share_request',
      'payload': {'requestId': 'request-1'},
    };

    expect(
      extractCollaborationControlPayload({
        'event': 'collaboration_control',
        'payload': control,
      }),
      equals(control),
    );
  });

  test('keeps another client session from the same account remote', () {
    final operation = CrdtOperation.fromJson({
      'projectId': 'project-a',
      'opId': 'client-guest:1',
      'dot': {'actorId': 'client-guest', 'counter': 1},
      'dependencies': const {},
      'kind': 'nodeDelete',
      'targetId': 'node-a',
      'value': const {},
    });

    expect(isLocalCrdtOperation(operation, 'client-host'), isFalse);
    expect(isLocalCrdtOperation(operation, 'client-guest'), isTrue);
  });

  test('accepts a delta document and operation for the requested project', () {
    final operation = CrdtOperation.create(
      projectId: 'project-a',
      dot: const CrdtDot(actorId: 'actor-a', counter: 1),
      dependencies: CrdtVersionVector(),
      kind: CrdtOperationKind.nodeDelete,
      targetId: 'node-a',
    );
    final delta = decodeCrdtDeltaResponse(
      [
        {
          'snapshot': {
            'version': {'actor-a': 1},
            'state': {
              'document': CanvasDocument(
                projectId: 'project-a',
                updatedAt: DateTime.utc(2026, 1, 2),
              ).toJson(),
              'crdt': {'nodes': {}},
            },
          },
          'operation': operation.toJson(),
        },
      ],
      projectId: 'project-a',
      version: CrdtVersionVector(),
    );

    expect(delta.document?.projectId, 'project-a');
    expect(delta.version.values, {'actor-a': 1});
    expect(delta.operations.single.projectId, 'project-a');
  });

  test('rejects a delta document from another project', () {
    expect(
      () => decodeCrdtDeltaResponse(
        [
          {
            'snapshot': {
              'state': {
                'document': CanvasDocument(
                  projectId: 'project-b',
                  updatedAt: DateTime.utc(2026, 1, 2),
                ).toJson(),
              },
            },
          },
        ],
        projectId: 'project-a',
        version: CrdtVersionVector(),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('project mismatch'),
        ),
      ),
    );
  });

  test('rejects a delta operation from another project', () {
    final operation = CrdtOperation.create(
      projectId: 'project-b',
      dot: const CrdtDot(actorId: 'actor-b', counter: 1),
      dependencies: CrdtVersionVector(),
      kind: CrdtOperationKind.nodeDelete,
      targetId: 'node-b',
    );

    expect(
      () => decodeCrdtDeltaResponse(
        [
          {'operation': operation.toJson()},
        ],
        projectId: 'project-a',
        version: CrdtVersionVector(),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('project mismatch'),
        ),
      ),
    );
  });
}
