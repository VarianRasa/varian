import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/domain/workspace_note_template.dart';
import 'package:varian/features/notes/presentation/notes_templates_screen.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

import '../../test_app.dart';

late final SupabaseClient _templateTestClient;

class _FakeWorkspaceNotesNotifier extends WorkspaceNotesNotifier {
  _FakeWorkspaceNotesNotifier() : super(null, null) {
    state = const WorkspaceNotesState(accountId: 'owner-a');
  }
}

class _FakeTemplateRepository extends WorkspaceNoteRepository {
  _FakeTemplateRepository(SupabaseClient client) : super(client);

  final templates = <WorkspaceNoteTemplate>[];
  final requestedScopes = <String?>[];
  int _nextId = 0;

  @override
  Future<List<WorkspaceNoteTemplate>> listTemplates({
    String? projectId,
    String? expectedAccountId,
  }) async {
    requestedScopes.add(projectId);
    return templates
        .where((template) => template.projectId == projectId)
        .toList(growable: false);
  }

  @override
  Future<WorkspaceNoteTemplate> createTemplate({
    required String title,
    required String markdownContent,
    String? projectId,
    required String expectedAccountId,
  }) async {
    final now = DateTime.utc(2026, 10, 21);
    final template = WorkspaceNoteTemplate(
      id: 'template-${++_nextId}',
      ownerUserId: expectedAccountId,
      projectId: projectId,
      title: title.trim(),
      markdownContent: markdownContent,
      createdAt: now,
      updatedAt: now,
      createdBy: expectedAccountId,
    );
    templates.add(template);
    return template;
  }

  @override
  Future<WorkspaceNoteTemplate> updateTemplate(
    WorkspaceNoteTemplate template, {
    required String title,
    required String markdownContent,
    required String expectedAccountId,
  }) async {
    final updated = template.copyWith(
      title: title.trim(),
      markdownContent: markdownContent,
      revision: template.revision + 1,
      updatedAt: DateTime.utc(2026, 10, 22),
    );
    templates[templates.indexWhere((item) => item.id == template.id)] = updated;
    return updated;
  }

  @override
  Future<void> deleteTemplate({
    required WorkspaceNoteTemplate template,
    required String expectedAccountId,
  }) async {
    templates.removeWhere((item) => item.id == template.id);
  }
}

Widget _screen(_FakeTemplateRepository repository, {String? projectId}) =>
    ProviderScope(
      overrides: [
        workspaceNotesProvider.overrideWith(
          (ref) => _FakeWorkspaceNotesNotifier(),
        ),
        workspaceNoteRepositoryProvider.overrideWithValue(repository),
      ],
      child: testApp(NotesTemplatesScreen(projectId: projectId)),
    );

void main() {
  setUpAll(() {
    _templateTestClient = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
    );
    _templateTestClient.auth.stopAutoRefresh();
  });
  tearDownAll(() => _templateTestClient.dispose());

  testWidgets('private manager creates templates only in private scope', (
    tester,
  ) async {
    final repository = _FakeTemplateRepository(_templateTestClient);
    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();
    expect(
      find.text('No templates in this scope. Create one to get started.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Create template'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Meeting notes');
    await tester.enterText(find.byType(TextField).at(1), '# {{title}}');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.templates.single.title, 'Meeting notes');
    expect(repository.templates.single.projectId, isNull);
    expect(repository.templates.single.markdownContent, '# {{title}}');
    expect(repository.requestedScopes, [null]);
    expect(find.text('Meeting notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deletes a fetched template from a fixed-length list', (
    tester,
  ) async {
    final repository = _FakeTemplateRepository(_templateTestClient);
    final now = DateTime.utc(2026, 10, 21);
    repository.templates.add(
      WorkspaceNoteTemplate(
        id: 'existing-template',
        ownerUserId: 'owner-a',
        title: 'Existing template',
        markdownContent: 'Body',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete Existing template'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.templates, isEmpty);
    expect(
      find.text('No templates in this scope. Create one to get started.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared manager lists and creates in the selected project', (
    tester,
  ) async {
    final repository = _FakeTemplateRepository(_templateTestClient);
    await tester.pumpWidget(_screen(repository, projectId: 'project-1'));
    await tester.pumpAndSettle();

    expect(find.text('Shared project (project-1)'), findsOneWidget);
    expect(repository.requestedScopes, ['project-1']);
    await tester.tap(find.byTooltip('Create template'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Shared agenda');
    await tester.enterText(find.byType(TextField).at(1), 'Agenda');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.templates.single.projectId, 'project-1');
    expect(repository.templates.single.createdBy, 'owner-a');
    expect(repository.requestedScopes, ['project-1']);
    expect(find.text('Shared agenda'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
