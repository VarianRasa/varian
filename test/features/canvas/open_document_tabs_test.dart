import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/data/remote/supabase_service.dart';

String _part(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Future<void> _auth(
  SupabaseClient client, {
  String accountId = 'owner-a',
}) async {
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  client.auth.stopAutoRefresh();
  await client.auth.recoverSession(
    jsonEncode({
      'access_token':
          '${_part({'alg': 'HS256'})}.${_part({'sub': accountId, 'exp': exp})}.signature',
      'token_type': 'bearer',
      'expires_at': exp,
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'user': {
        'id': accountId,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-01T00:00:00Z',
      },
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'closing a deleted note only affects its signed-in owner tabs',
    () async {
      SharedPreferences.setMockInitialValues({});
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
      );
      addTearDown(client.dispose);
      await _auth(client);
      final tabs = OpenNoteTabsNotifier(client);
      addTearDown(tabs.dispose);
      await tabs.setAccount('owner-a');
      final note = WorkspaceNote(
        id: 'n1',
        ownerUserId: 'owner-a',
        title: 'A',
        markdownContent: '',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      await tabs.openTab(OpenDocumentTab.note(note));
      await tabs.closeDeletedNote('n1', 'owner-b');
      expect(tabs.state, hasLength(1));
      await tabs.closeDeletedNote('n1', 'owner-a');
      expect(tabs.state, isEmpty);
    },
  );

  test('shared project note tabs are scoped to the viewing account', () async {
    SharedPreferences.setMockInitialValues({});
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
    );
    addTearDown(client.dispose);
    await _auth(client, accountId: 'owner-a');
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWith((ref) => client)],
    );
    addTearDown(container.dispose);
    final tabs = container.read(openNoteTabsProvider.notifier);
    await tabs.setAccount('owner-a');
    final projectNote = WorkspaceNote(
      id: 'shared-note',
      ownerUserId: 'owner-b',
      projectId: 'project-1',
      title: 'Shared note',
      markdownContent: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    await container
        .read(activeDocumentTabControllerProvider)
        .select(OpenDocumentTab.note(projectNote));

    final active = container.read(activeDocumentTabProvider)!;
    expect(active.documentId, 'shared-note');
    expect(active.ownerAccountId, 'owner-a');
    expect(active.noteProjectId, 'project-1');
    expect(tabs.state.single.ownerAccountId, 'owner-a');
  });

  test(
    'auth transition clears previous account note but preserves same account and Canvas selections',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
      );
      addTearDown(client.dispose);
      await _auth(client);
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWith((ref) => client)],
      );
      addTearDown(container.dispose);
      container.read(openNoteTabsProvider);

      const ownerANote = OpenDocumentTab(
        documentId: 'n1',
        name: 'A',
        type: OpenDocumentTabType.note,
        ownerAccountId: 'owner-a',
      );
      container.read(activeDocumentTabProvider.notifier).state = ownerANote;
      await _auth(client, accountId: 'owner-b');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(activeDocumentTabProvider), isNull);

      const ownerBNote = OpenDocumentTab(
        documentId: 'n2',
        name: 'B',
        type: OpenDocumentTabType.note,
        ownerAccountId: 'owner-b',
      );
      container.read(activeDocumentTabProvider.notifier).state = ownerBNote;
      await _auth(client, accountId: 'owner-b');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(activeDocumentTabProvider), ownerBNote);

      const canvas = OpenDocumentTab(documentId: 'canvas-1', name: 'Canvas');
      container.read(activeDocumentTabProvider.notifier).state = canvas;
      await _auth(client, accountId: 'owner-a');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(activeDocumentTabProvider), canvas);
    },
  );

  test(
    'retryable auth stream errors preserve the active note selection',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
      );
      addTearDown(client.dispose);
      await _auth(client);
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWith((ref) => client)],
      );
      addTearDown(container.dispose);
      container.read(openNoteTabsProvider);
      const noteTab = OpenDocumentTab(
        documentId: 'n1',
        name: 'A',
        type: OpenDocumentTabType.note,
        ownerAccountId: 'owner-a',
      );
      container.read(activeDocumentTabProvider.notifier).state = noteTab;

      // Surface the same retryable error event emitted by GoTrue's refresh path.
      // ignore: invalid_use_of_internal_member
      client.auth.notifyException(
        AuthRetryableFetchException(message: 'Network unavailable.'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(container.read(activeDocumentTabProvider), noteTab);
    },
  );

  test('active note selection clears only for matching tab identity', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const selected = OpenDocumentTab(
      documentId: 'n1',
      name: 'A',
      type: OpenDocumentTabType.note,
      ownerAccountId: 'owner-a',
    );
    const otherOwner = OpenDocumentTab(
      documentId: 'n1',
      name: 'A',
      type: OpenDocumentTabType.note,
      ownerAccountId: 'owner-b',
    );
    container.read(activeDocumentTabProvider.notifier).state = selected;
    container
        .read(activeDocumentTabControllerProvider)
        .clearIfActive(otherOwner);
    expect(container.read(activeDocumentTabProvider), selected);
    container.read(activeDocumentTabControllerProvider).clearIfActive(selected);
    expect(container.read(activeDocumentTabProvider), isNull);
  });
}
