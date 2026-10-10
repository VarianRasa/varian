import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/account_scoped_local_storage.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/features/auth/state/auth_recovery.dart';

void main() {
  test(
    'clears account-scoped collaboration, profile, and return state',
    () async {
      final created = DateTime(2026, 9, 19);
      final roomProject = LocalProjectMetadata(
        id: 'project-1',
        name: 'Local project',
        createdAt: created,
        updatedAt: created,
        collaborationRoomCode: '123456',
        collaborationRole: 'editor',
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([roomProject.toJson()]),
        'ccs_collab_queue_project-1': jsonEncode([]),
        'ccs_collaboration_room_project-1': jsonEncode({
          'id': 'room-1',
          'projectId': 'project-1',
          'projectName': 'Local project',
          'roomCode': '123456',
        }),
        'cfg_user_name': 'Previous account',
        'auth_return_path': '/meeting/room?projectId=project-1',
      });

      await clearAccountScopedAuthState();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ccs_collaboration_room_project-1'), isNull);
      expect(prefs.getString('ccs_collab_queue_project-1'), isNull);
      final projects = await LocalStorageService().getProjects();
      expect(projects.single.id, 'project-1');
      expect(projects.single.collaborationRoomCode, isNull);
      expect(projects.single.collaborationRole, isNull);
      expect(
        await LocalStorageService().requiresAccountScopedCollaborationRejoin(
          'project-1',
        ),
        isTrue,
      );
      expect(prefs.getString('cfg_user_name'), isNull);
      expect(prefs.getString('auth_return_path'), isNull);
      await LocalStorageService().clearAccountScopedCollaborationRejoin(
        'project-1',
      );
      expect(
        await LocalStorageService().requiresAccountScopedCollaborationRejoin(
          'project-1',
        ),
        isFalse,
      );
    },
  );

  test('account-scoped queues rotate ownership before loading', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService();

    final previousGeneration = await storage
        .accountScopedCollaborationGeneration(accountId: 'fixture-a');
    await storage.saveAccountScopedCollaborationQueue(
      'project-a',
      const [],
      generation: previousGeneration,
      accountId: 'fixture-a',
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        'ccs_collab_queue_project-a',
      ),
      '[]',
    );

    final replacementGeneration = await storage
        .accountScopedCollaborationGeneration(accountId: 'fixture-b');
    expect(replacementGeneration, greaterThan(previousGeneration));
    expect(
      (await SharedPreferences.getInstance()).getString(
        'ccs_collab_queue_project-a',
      ),
      isNull,
    );
    expect(
      await storage.loadAccountScopedCollaborationQueue(
        'project-a',
        generation: replacementGeneration,
        accountId: 'fixture-b',
      ),
      isEmpty,
    );
  });

  test(
    'fenced cleanup clears the outgoing return path after sign-out',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_return_path': '/project/previous-account',
        'auth_return_path_owner': 'fixture-a',
      });

      await clearAccountScopedAuthState(expectedAccountId: 'fixture-a');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_return_path'), isNull);
      expect(prefs.getString('auth_return_path_owner'), isNull);
    },
  );

  test(
    'account-scoped cleanup preserves a replacement ownerless return path',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_return_path': '/project/replacement',
      });

      await clearAccountScopedAuthState(expectedAccountId: 'fixture-a');

      final prefs = await SharedPreferences.getInstance();
      final rawPath = prefs.getString('auth_return_path')!;
      final decodedPath = rawPath.startsWith('{')
          ? (jsonDecode(rawPath) as Map<String, dynamic>)['path'] as String?
          : rawPath;
      expect(
        AuthCallbackParser.safeLocalPath(decodedPath),
        '/project/replacement',
      );
    },
  );

  test(
    'return-path cleanup cannot erase a concurrent replacement OAuth path',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_return_path': '/project/previous-account',
        'auth_return_path_owner': 'fixture-a',
      });

      await Future.wait([
        AuthReturnPathStore.clear(expectedOwner: 'fixture-a'),
        AuthReturnPathStore.save('/project/replacement'),
      ]);

      final prefs = await SharedPreferences.getInstance();
      final rawPath = prefs.getString('auth_return_path')!;
      final decodedPath = rawPath.startsWith('{')
          ? (jsonDecode(rawPath) as Map<String, dynamic>)['path'] as String?
          : rawPath;
      expect(
        AuthCallbackParser.safeLocalPath(decodedPath),
        '/project/replacement',
      );
      expect(prefs.getString('auth_return_path_owner'), isNull);
    },
  );

  test(
    'owner-fenced cleanup preserves a replacement save invoked first',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_return_path': '/project/previous-account',
        'auth_return_path_owner': 'fixture-a',
      });

      final replacement = AuthReturnPathStore.save('/project/replacement');
      final cleanup = AuthReturnPathStore.clear(expectedOwner: 'fixture-a');
      await Future.wait([replacement, cleanup]);

      final prefs = await SharedPreferences.getInstance();
      final rawPath = prefs.getString('auth_return_path')!;
      final decodedPath = rawPath.startsWith('{')
          ? (jsonDecode(rawPath) as Map<String, dynamic>)['path'] as String?
          : rawPath;
      expect(
        AuthCallbackParser.safeLocalPath(decodedPath),
        '/project/replacement',
      );
      expect(prefs.getString('auth_return_path_owner'), isNull);
    },
  );

  test(
    'account-scoped cleanup does not clear replacement account metadata',
    () async {
      final created = DateTime(2026, 9, 19);
      final previous = LocalProjectMetadata(
        id: 'previous-project',
        name: 'Previous project',
        createdAt: created,
        updatedAt: created,
        collaborationRoomCode: '123456',
        collaborationRole: 'editor',
        collaborationAccountId: 'fixture-a',
      );
      final replacement = LocalProjectMetadata(
        id: 'replacement-project',
        name: 'Replacement project',
        createdAt: created,
        updatedAt: created,
        collaborationRoomCode: '654321',
        collaborationRole: 'owner',
        collaborationAccountId: 'fixture-b',
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([
          previous.toJson(),
          replacement.toJson(),
        ]),
        'ccs_collaboration_room_previous-project': jsonEncode({
          'projectId': 'previous-project',
          'roomCode': '123456',
          'accountId': 'fixture-a',
        }),
        'ccs_collaboration_room_replacement-project': jsonEncode({
          'projectId': 'replacement-project',
          'roomCode': '654321',
          'accountId': 'fixture-b',
        }),
      });

      await clearAccountScopedAuthState(expectedAccountId: 'fixture-a');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('ccs_collaboration_room_previous-project'),
        isNull,
      );
      expect(
        prefs.getString('ccs_collaboration_room_replacement-project'),
        isNotNull,
      );
      final projects = await LocalStorageService().getProjects();
      expect(
        projects
            .singleWhere((project) => project.id == 'previous-project')
            .collaborationRoomCode,
        isNull,
      );
      expect(
        projects
            .singleWhere((project) => project.id == 'replacement-project')
            .collaborationRoomCode,
        '654321',
      );
    },
  );

  test(
    'late account cleanup preserves replacement queues, profile, and room cache',
    () async {
      final created = DateTime(2026, 9, 19);
      final previous = LocalProjectMetadata(
        id: 'previous-project',
        name: 'Previous project',
        createdAt: created,
        updatedAt: created,
        collaborationRoomCode: '123456',
        collaborationRole: 'editor',
        collaborationAccountId: 'fixture-a',
      );
      final replacement = LocalProjectMetadata(
        id: 'replacement-project',
        name: 'Replacement project',
        createdAt: created,
        updatedAt: created,
        collaborationRoomCode: '654321',
        collaborationRole: 'owner',
        collaborationAccountId: 'fixture-b',
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([
          previous.toJson(),
          replacement.toJson(),
        ]),
        'ccs_collab_queue_replacement-project': jsonEncode([]),
        'ccs_collab_queue_replacement-project_generation': 7,
        'ccs_account_scoped_generation': 7,
        'ccs_account_scoped_owner': 'fixture-b',
        'ccs_collaboration_room_previous-project': jsonEncode({
          'projectId': 'previous-project',
          'roomCode': '123456',
          'accountId': 'fixture-a',
        }),
        'ccs_collaboration_room_replacement-project': jsonEncode({
          'projectId': 'replacement-project',
          'roomCode': '654321',
          'accountId': 'fixture-b',
        }),
        'cfg_user_name': 'Replacement profile',
        'cfg_user_name_owner': 'fixture-b',
      });

      await clearAccountScopedAuthState(expectedAccountId: 'fixture-a');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ccs_collab_queue_replacement-project'), '[]');
      expect(
        prefs.getInt('ccs_collab_queue_replacement-project_generation'),
        7,
      );
      expect(
        prefs.getString('ccs_collaboration_room_replacement-project'),
        isNotNull,
      );
      expect(prefs.getString('cfg_user_name'), 'Replacement profile');
      expect(prefs.getString('cfg_user_name_owner'), 'fixture-b');
      final projects = await LocalStorageService().getProjects();
      expect(
        projects
            .singleWhere((project) => project.id == 'replacement-project')
            .collaborationRoomCode,
        '654321',
      );
    },
  );
}
