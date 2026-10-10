import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/templates/domain/project_template.dart';

ProjectTemplate _template(
  String id,
  DateTime updatedAt, {
  ProjectTemplateScope scope = ProjectTemplateScope.personal,
}) => ProjectTemplate(
  id: id,
  name: id,
  description: 'Template $id',
  scope: scope,
  createdAt: updatedAt,
  updatedAt: updatedAt,
);

http.Response _jsonResponse(
  Object value, {
  int statusCode = 200,
  http.BaseRequest? request,
}) => http.Response(
  jsonEncode(value),
  statusCode,
  request: request,
  headers: {'content-type': 'application/json'},
);

Future<void> _authenticate(SupabaseClient client) async {
  final expiration =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;

  String encodePart(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  final token =
      '${encodePart({'alg': 'HS256'})}.${encodePart({'sub': 'template-user', 'exp': expiration})}.test-signature';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_at': expiration,
      'expires_in': 3600,
      'refresh_token': 'template-refresh',
      'user': {
        'id': 'template-user',
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

void main() {
  test('syncs local and remote templates through Supabase RPC', () async {
    final localOnly = _template(
      'personal:local-only',
      DateTime.utc(2026, 9, 13, 10),
    );
    final localNewer = _template(
      'personal:conflict',
      DateTime.utc(2026, 9, 13, 12),
    );
    final remoteOnly = _template(
      'team:remote-only',
      DateTime.utc(2026, 9, 13, 11),
      scope: ProjectTemplateScope.team,
    );
    final remoteOlder = _template(
      'personal:conflict',
      DateTime.utc(2026, 9, 13, 9),
    ).copyWith(name: 'Remote stale');
    final serverUpdatedAt = DateTime.utc(2026, 9, 13, 13);
    final requests = <http.Request>[];

    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/rpc/list_project_templates') {
          expect(jsonDecode(request.body), {'p_workspace_id': 'workspace-1'});
          return _jsonResponse([
            remoteOnly.toJson(),
            remoteOlder.toJson(),
          ], request: request);
        }
        if (request.url.path == '/rest/v1/rpc/upsert_project_template') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final templateJson = Map<String, dynamic>.from(
            body['p_template_json'] as Map,
          );
          final id = body['p_template_id'] as String;
          expect(body['p_workspace_id'], 'workspace-1');
          expect(body['p_scope'], 'personal');
          expect(templateJson['id'], id);
          return _jsonResponse(
            ProjectTemplate.fromJson(templateJson)
                .copyWith(
                  name: 'Server canonical $id',
                  updatedAt: serverUpdatedAt,
                )
                .toJson(),
            request: request,
          );
        }
        return _jsonResponse(
          {'error': 'unexpected RPC'},
          statusCode: 500,
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    await _authenticate(client);

    final result = await SupabaseSyncService(client).syncProjectTemplates(
      workspaceId: 'workspace-1',
      local: ProjectTemplateCatalog.withBuiltIns(
        custom: [localOnly, localNewer],
      ),
    );

    expect(result.uploaded.map((template) => template.id).toSet(), {
      'personal:local-only',
      'personal:conflict',
    });
    expect(result.failedUploads, isEmpty);
    expect(
      result.catalog.templates
          .firstWhere((template) => template.id == remoteOnly.id)
          .name,
      remoteOnly.name,
    );
    final canonical = result.catalog.templates.firstWhere(
      (template) => template.id == localNewer.id,
    );
    expect(canonical.name, 'Server canonical ${localNewer.id}');
    expect(canonical.updatedAt, serverUpdatedAt);
    expect(
      requests.where(
        (request) => request.url.path == '/rest/v1/rpc/list_project_templates',
      ),
      hasLength(1),
    );
    expect(
      requests.where(
        (request) => request.url.path == '/rest/v1/rpc/upsert_project_template',
      ),
      hasLength(2),
    );
  });
}
