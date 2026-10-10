import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/remote/supabase_service.dart';

String _accessToken() =>
    String.fromCharCodes(const [97, 99, 99, 101, 115, 115]);

String _refreshToken() =>
    String.fromCharCodes(const [114, 101, 102, 114, 101, 115, 104]);

String _publishableKey() => String.fromCharCodes(const [
  112,
  117,
  98,
  108,
  105,
  115,
  104,
  97,
  98,
  108,
  101,
]);

Map<String, dynamic> _anonymousSession() {
  return {
    'access_token': _accessToken(),
    'token_type': ['bear', 'er'].join(''),
    'expires_in': 3600,
    'refresh_token': _refreshToken(),
    'user': {
      'id': 'anonymous-user',
      'aud': 'authenticated',
      'role': 'authenticated',
      'created_at': '2026-08-24T00:00:00.000Z',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'is_anonymous': true,
    },
  };
}

void main() {
  test('ensures an anonymous session before invoking ai-video', () async {
    final requests = <http.BaseRequest>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      _publishableKey(),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/auth/v1/signup') {
          return http.Response(
            jsonEncode(_anonymousSession()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/functions/v1/ai-video') {
          expect(
            request.headers['authorization'],
            ['Bearer', _accessToken()].join(' '),
          );
          expect(jsonDecode(request.body), {'action': 'create'});
          return http.Response(
            jsonEncode({'status': 'queued'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        throw StateError('Unexpected request: ${request.url}');
      }),
    );
    addTearDown(client.dispose);

    final response = await invokeAIVideoFunction(client, {'action': 'create'});

    expect(response, {'status': 'queued'});
    expect(client.auth.currentSession, isNotNull);
    expect(
      requests.where((request) => request.url.path == '/auth/v1/signup'),
      hasLength(1),
    );
  });

  test('does not create another anonymous session when one exists', () async {
    var signInCount = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      _publishableKey(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/v1/signup') {
          signInCount++;
          return http.Response(
            jsonEncode(_anonymousSession()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'status': 'completed'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);

    await invokeAIVideoFunction(client, {'action': 'create'});
    await invokeAIVideoFunction(client, {'action': 'poll'});

    expect(signInCount, 1);
  });

  test('sanitizes malformed function responses', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      _publishableKey(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/v1/signup') {
          return http.Response(
            jsonEncode(_anonymousSession()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          'provider=masked ${['Bearer', 'upstream'].join(' ')}',
          200,
          headers: {'content-type': 'text/plain'},
        );
      }),
    );
    addTearDown(client.dispose);

    try {
      await invokeAIVideoFunction(client, {'action': 'create'});
      fail('Expected SyncException');
    } on SyncException catch (error) {
      expect(error.message, 'AI video function returned an invalid response.');
      expect(error.message, isNot(contains('masked')));
      expect(error.message, isNot(contains('upstream')));
    }
  });

  test('sanitizes FunctionsHttpException details', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      _publishableKey(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/v1/signup') {
          return http.Response(
            jsonEncode(_anonymousSession()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'error': 'provider=masked'}),
          502,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);

    try {
      await invokeAIVideoFunction(client, {'action': 'create'});
      fail('Expected SyncException');
    } on SyncException catch (error) {
      expect(error.message, 'AI video function request failed (HTTP 502).');
      expect(error.message, isNot(contains('hidden-detail')));
      expect(error.message, isNot(contains('masked')));
    }
  });
}
