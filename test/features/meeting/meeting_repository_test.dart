import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/meeting/data/meeting_repository.dart';
import 'package:varian/features/meeting/domain/meeting_errors.dart';
import 'package:varian/features/meeting/domain/meeting_models.dart';

const projectId = 'project-1';
const meetingId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

Map<String, dynamic> sessionRow({
  String id = meetingId,
  String project = projectId,
  String status = 'active',
  String room = 'meeting-room',
}) => {
  'id': id,
  'project_id': project,
  'provider': 'livekit',
  'provider_room_name': room,
  'status': status,
  'created_by': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'created_at': '2026-09-16T00:00:00.000Z',
  'max_participants': 8,
  if (status == 'ended') 'ended_at': '2026-09-16T01:00:00.000Z',
  if (status == 'ended') 'ended_reason': 'host_ended',
};

MeetingRepository repository({
  Future<Object?> Function(String, Map<String, dynamic>)? rpc,
  Future<MeetingFunctionResponse> Function(String, Map<String, dynamic>)?
  invoke,
  Stream<Map<String, dynamic>> Function(String)? rows,
  String? currentUserId,
  MeetingParticipantRemover? removeParticipant,
}) => MeetingRepository(
  null,
  rpc: rpc,
  invoke: invoke,
  rows: rows,
  currentUserId: currentUserId,
  removeParticipant: removeParticipant,
);

void main() {
  test(
    'createMeeting calls the exact RPC and normalizes a single-item list',
    () async {
      String? name;
      Map<String, dynamic>? params;
      final repo = repository(
        rpc: (rpcName, rpcParams) async {
          name = rpcName;
          params = rpcParams;
          return [sessionRow()];
        },
      );

      final session = await repo.createMeeting(projectId: projectId);

      expect(name, 'create_meeting_session');
      expect(params, {'p_project_id': projectId, 'p_max_participants': 8});
      expect(session.id, meetingId);
      expect(session.projectId, projectId);
    },
  );

  test('join and end use exact RPC params and reject foreign rows', () async {
    final calls = <List<Object?>>[];
    final repo = repository(
      rpc: (name, params) async {
        calls.add([name, params]);
        if (name == 'join_meeting_session') {
          return sessionRow(id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
        }
        return sessionRow(status: 'ended');
      },
    );

    await expectLater(
      repo.joinMeeting(meetingId: meetingId),
      throwsA(
        isA<MeetingRepositoryException>().having(
          (error) => error.code,
          'code',
          MeetingErrorCode.unavailable,
        ),
      ),
    );
    final ended = await repo.endMeeting(meetingId: meetingId);

    expect(calls.first, [
      'join_meeting_session',
      {'p_meeting_id': meetingId},
    ]);
    expect(calls.last, [
      'end_meeting_session',
      {'p_meeting_id': meetingId, 'p_reason': 'host_ended'},
    ]);
    expect(ended.isEnded, isTrue);
  });

  test(
    'accepts uppercase meeting UUID requests against canonical rows',
    () async {
      final uppercaseId = meetingId.toUpperCase();
      String? requestedId;
      final repo = repository(
        rpc: (name, params) async {
          requestedId = params['p_meeting_id'] as String?;
          return sessionRow();
        },
      );

      final session = await repo.joinMeeting(meetingId: uppercaseId);

      expect(requestedId, uppercaseId);
      expect(session.id, meetingId);
    },
  );

  test(
    'requestToken sends only meetingId and validates exact token fields',
    () async {
      String? name;
      Map<String, dynamic>? body;
      final repo = repository(
        invoke: (functionName, functionBody) async {
          name = functionName;
          body = functionBody;
          return const MeetingFunctionResponse(
            status: 200,
            data: {
              'token': 'jwt-token',
              'serverUrl': 'wss://video.example',
              'expiresAt': '2099-09-16T01:00:00.000Z',
              'identity': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
            },
          );
        },
      );

      final token = await repo.requestToken(meetingId: meetingId);

      expect(name, 'meeting-token');
      expect(body, {'meetingId': meetingId});
      final captured = <String>[];
      await token.use<void>(({
        required String serverUrl,
        required String token,
      }) async {
        captured
          ..add(token)
          ..add(serverUrl);
      });
      expect(captured, ['jwt-token', 'wss://video.example']);
      expect(token.identity, 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
    },
  );

  test('removeParticipant accepts true and false provider outcomes', () async {
    const identity = 'EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE';
    for (final removed in [true, false]) {
      var invoked = false;
      final repo = repository(
        invoke: (name, body) async {
          invoked = true;
          expect(name, 'meeting-remove-participant');
          expect(body, {'meetingId': meetingId, 'identity': identity});
          return MeetingFunctionResponse(
            status: 200,
            data: {'removed': removed},
          );
        },
      );

      await repo.removeParticipant(meetingId: meetingId, identity: identity);
      expect(invoked, isTrue);
    }
  });

  test(
    'removeParticipant rejects malformed provider outcomes as unavailable',
    () async {
      for (final data in [
        <String, dynamic>{},
        <String, dynamic>{'removed': 'true'},
        <String, dynamic>{'removed': null},
        const <dynamic>[],
      ]) {
        final repo = repository(
          invoke: (_, _) async =>
              MeetingFunctionResponse(status: 200, data: data),
        );

        await expectLater(
          repo.removeParticipant(
            meetingId: meetingId,
            identity: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          ),
          throwsA(
            isA<MeetingRepositoryException>().having(
              (error) => error.code,
              'code',
              MeetingErrorCode.providerUnavailable,
            ),
          ),
        );
      }
    },
  );

  test(
    'removeParticipant rejects identities outside the UUID v1-v5 shape',
    () async {
      var invoked = false;
      final repo = repository(
        invoke: (_, _) async {
          invoked = true;
          return const MeetingFunctionResponse(
            status: 200,
            data: {'removed': true},
          );
        },
      );

      for (final identity in [
        '',
        'not-a-uuid',
        'eeeeeeee-eeee-6eee-8eee-eeeeeeeeeeee',
        'eeeeeeee-eeee-4eee-eeee-eeeeeeeeeeee',
        'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee',
      ]) {
        await expectLater(
          repo.removeParticipant(meetingId: meetingId, identity: identity),
          throwsA(
            isA<MeetingRepositoryException>().having(
              (error) => error.code,
              'code',
              MeetingErrorCode.unavailable,
            ),
          ),
        );
      }
      expect(invoked, isFalse);
    },
  );

  test('removeParticipant preserves injected remover behavior', () async {
    String? calledMeetingId;
    String? calledIdentity;
    final repo = repository(
      invoke: (_, _) async => throw StateError('must not invoke function'),
      removeParticipant: (meeting, identity) async {
        calledMeetingId = meeting;
        calledIdentity = identity;
      },
    );

    await repo.removeParticipant(
      meetingId: meetingId,
      identity: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    );
    expect(calledMeetingId, meetingId);
    expect(calledIdentity, 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
  });

  test(
    'maps structured function errors without exposing provider details',
    () async {
      for (final entry in {
        'authorization_error': MeetingErrorCode.authorizationError,
        'capacity_full': MeetingErrorCode.capacityFull,
        'provider_unavailable': MeetingErrorCode.providerUnavailable,
        'ended': MeetingErrorCode.ended,
        'removed': MeetingErrorCode.removed,
        'unexpected': MeetingErrorCode.providerUnavailable,
      }.entries) {
        final repo = repository(
          invoke: (_, _) async => MeetingFunctionResponse(
            status: 503,
            data: {
              'error': {
                'code': entry.key,
                'message': 'secret LiveKit provider details',
              },
            },
          ),
        );

        try {
          await repo.requestToken(meetingId: meetingId);
          fail('requestToken unexpectedly succeeded for ${entry.key}');
        } on MeetingRepositoryException catch (error) {
          expect(error.code, entry.value);
          expect(error.toString(), isNot(contains('LiveKit')));
        }
      }
    },
  );

  test('maps empty function error responses by HTTP status', () async {
    for (final entry in {
      401: MeetingErrorCode.authorizationError,
      403: MeetingErrorCode.authorizationError,
      409: MeetingErrorCode.capacityFull,
      410: MeetingErrorCode.ended,
      503: MeetingErrorCode.providerUnavailable,
    }.entries) {
      final repo = repository(
        invoke: (_, _) async => MeetingFunctionResponse(status: entry.key),
      );
      await expectLater(
        repo.requestToken(meetingId: meetingId),
        throwsA(
          isA<MeetingRepositoryException>().having(
            (error) => error.code,
            'code',
            entry.value,
          ),
        ),
      );
    }
  });

  test(
    'maps statusless function transport errors to providerUnavailable',
    () async {
      final repo = repository(
        invoke: (_, _) async => throw StateError('raw provider secret'),
      );

      try {
        await repo.requestToken(meetingId: meetingId);
        fail('requestToken unexpectedly succeeded');
      } on MeetingRepositoryException catch (error) {
        expect(error.code, MeetingErrorCode.providerUnavailable);
        expect(error.toString(), isNot(contains('raw provider secret')));
      }
    },
  );

  test(
    'rejects malformed, expired, and identity-mismatched token payloads',
    () async {
      for (final data in [
        {'token': 'jwt-token'},
        {
          'token': 'jwt-token',
          'serverUrl': 'wss://video.example',
          'expiresAt': '2000-01-01T00:00:00.000Z',
          'identity': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        },
        {
          'token': 'jwt-token',
          'serverUrl': 'wss://video.example',
          'expiresAt': '2099-09-16T01:00:00.000Z',
          'identity': 'not-a-uuid',
        },
        {
          'token': 'jwt-token',
          'serverUrl': 'wss://video.example',
          'expiresAt': '2099-09-16T01:00:00.000Z',
          'identity': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        },
      ]) {
        final repo = repository(
          currentUserId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          invoke: (_, _) async =>
              MeetingFunctionResponse(status: 200, data: data),
        );
        await expectLater(
          repo.requestToken(meetingId: meetingId),
          throwsA(
            isA<MeetingRepositoryException>().having(
              (error) => error.code,
              'code',
              MeetingErrorCode.unavailable,
            ),
          ),
        );
      }
    },
  );

  test(
    'rejects malformed session payloads with stable unavailable errors',
    () async {
      final malformedSession = repository(
        rpc: (_, _) async => {'id': meetingId},
      );
      await expectLater(
        malformedSession.createMeeting(projectId: projectId),
        throwsA(
          isA<MeetingRepositoryException>().having(
            (error) => error.code,
            'code',
            MeetingErrorCode.unavailable,
          ),
        ),
      );
    },
  );

  test(
    'null client fails closed without retaining or exposing credentials',
    () async {
      final repo = MeetingRepository(null);

      await expectLater(
        repo.joinMeeting(meetingId: meetingId),
        throwsA(
          isA<MeetingRepositoryException>().having(
            (error) => error.code,
            'code',
            MeetingErrorCode.unavailable,
          ),
        ),
      );
    },
  );

  test(
    'watchMeeting filters invalid/unrelated rows and closes after one terminal event',
    () async {
      final source = StreamController<Map<String, dynamic>>();
      final repo = repository(rows: (_) => source.stream);
      final received = <MeetingSession>[];
      final done = Completer<void>();
      final subscription = repo
          .watchMeeting(meetingId)
          .listen(
            received.add,
            onError: (Object error, StackTrace stack) => fail('$error'),
            onDone: done.complete,
          );

      source.add(sessionRow(id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'));
      source.add({'id': meetingId});
      source.add(sessionRow());
      source.add(sessionRow(status: 'ended'));
      source.add(sessionRow(status: 'active'));
      await done.future.timeout(const Duration(seconds: 1));

      expect(received.map((session) => session.id), [meetingId, meetingId]);
      expect(received.last.isEnded, isTrue);
      await subscription.cancel();
      await source.close();
    },
  );

  test('forwards one stable realtime provider error before closing', () async {
    final source = StreamController<Map<String, dynamic>>();
    final repo = repository(rows: (_) => source.stream);
    final errors = <Object>[];
    final done = Completer<void>();
    final subscription = repo
        .watchMeeting(meetingId)
        .listen(
          (_) {},
          onError: (Object error, StackTrace stack) => errors.add(error),
          onDone: done.complete,
        );

    source.addError(StateError('raw provider secret'));
    await done.future.timeout(const Duration(seconds: 1));

    expect(errors, hasLength(1));
    expect(errors.single, isA<MeetingRepositoryException>());
    expect(
      (errors.single as MeetingRepositoryException).code,
      MeetingErrorCode.providerUnavailable,
    );
    await subscription.cancel();
    await source.close();
  });

  test('dispose closes active meeting streams', () async {
    final source = StreamController<Map<String, dynamic>>();
    final repo = repository(rows: (_) => source.stream);
    final done = Completer<void>();
    final subscription = repo
        .watchMeeting(meetingId)
        .listen((_) {}, onDone: done.complete);

    await repo.dispose();
    await done.future.timeout(const Duration(seconds: 1));
    expect(subscription.isPaused, isFalse);
    await subscription.cancel();
    await source.close();
  });
}
