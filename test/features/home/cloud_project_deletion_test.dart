import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/cloud_project_deletion.dart';

const _accountId = '223e4567-e89b-12d3-a456-426614174001';

String _encodePart(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<void> _authenticate(SupabaseClient client) async {
  final expiration =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  final token =
      '${_encodePart({'alg': 'HS256'})}.${_encodePart({'sub': _accountId, 'exp': expiration})}.signature';
  client.auth.stopAutoRefresh();
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_at': expiration,
      'expires_in': 3600,
      'refresh_token': 'fixture-refresh-token',
      'user': {
        'id': _accountId,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-01T00:00:00Z',
      },
    }),
  );
}

http.Response _response(http.Request request, Object? body) => http.Response(
  jsonEncode(body),
  200,
  request: request,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('requests cloud deletion through the Notes-aware RPC', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith(
          '/rpc/request_workspace_note_project_delete',
        )) {
          return _response(request, [
            {'status': 'pending', 'job_id': 'rehome-job-1'},
          ]);
        }
        return _response(request, []);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final service = SupabaseSyncService(client);
    addTearDown(service.dispose);

    final result = await service.deleteOwnedProject(
      'project-1',
      expectedUserId: _accountId,
    );

    expect(result.status, CloudProjectDeletionStatus.pending);
    expect(result.jobId, 'rehome-job-1');
    final request = requests.singleWhere(
      (item) =>
          item.url.path.endsWith('/rpc/request_workspace_note_project_delete'),
    );
    expect(jsonDecode(request.body), {'p_project_id': 'project-1'});
    expect(requests.any((item) => item.method == 'DELETE'), isFalse);
  });

  test('loads failed state and retries the durable deletion job', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith(
          '/workspace_note_attachment_rehome_jobs',
        )) {
          return _response(request, {
            'id': 'rehome-job-2',
            'job_kind': 'project_delete',
            'source_project_id': 'project-1',
            'requested_by': _accountId,
            'status': 'failed',
            'attempt_count': 8,
            'last_error_code': 'SOURCE_CLEANUP_FAILED',
          });
        }
        return _response(request, null);
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);
    final service = SupabaseSyncService(client);
    addTearDown(service.dispose);

    final status = await service.getOwnedProjectDeletionStatus(
      'project-1',
      expectedUserId: _accountId,
    );
    await service.retryOwnedProjectDeletion(
      jobId: 'rehome-job-2',
      expectedUserId: _accountId,
    );

    expect(status?.status, CloudProjectDeletionStatus.failed);
    expect(status?.attemptCount, 8);
    expect(status?.lastErrorCode, 'SOURCE_CLEANUP_FAILED');
    final retry = requests.singleWhere(
      (item) =>
          item.url.path.endsWith('/rpc/retry_workspace_note_attachment_rehome'),
    );
    expect(jsonDecode(retry.body), {'p_job_id': 'rehome-job-2'});
  });
}
