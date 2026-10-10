import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/home/presentation/widgets/project_card.dart';

void main() {
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        home: AppThemeScope(data: AppTheme.darkTheme, child: child),
      ),
    );
  }

  final project = LocalProjectMetadata(
    id: 'project-1',
    name: 'Untitled Doc',
    createdAt: DateTime(2026, 8, 23),
    updatedAt: DateTime(2026, 8, 23, 14, 23),
  );

  testWidgets('uses Mix popover for project actions', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 320,
          height: 320,
          child: ProjectCard(
            project: project,
            onTap: () {},
            onDelete: () => deleted = true,
            onRename: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate((widget) => widget is PopupMenuButton),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Project actions'));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('shows Adopt to cloud for an eligible local project', (
    tester,
  ) async {
    var adopted = false;
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 320,
          height: 320,
          child: ProjectCard(
            project: project,
            onTap: () {},
            onDelete: () {},
            onRename: (_) {},
            onAdopt: () => adopted = true,
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Project actions'));
    await tester.pumpAndSettle();

    expect(find.text('Adopt to cloud'), findsOneWidget);
    await tester.tap(find.text('Adopt to cloud'));
    await tester.pumpAndSettle();
    expect(adopted, isTrue);
  });

  Future<void> expectAdoptionActionHidden(
    WidgetTester tester,
    LocalProjectMetadata ineligibleProject,
  ) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 320,
          height: 320,
          child: ProjectCard(
            project: ineligibleProject,
            onTap: () {},
            onDelete: () {},
            onRename: (_) {},
            onAdopt: null,
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Project actions'));
    await tester.pumpAndSettle();

    expect(find.text('Adopt to cloud'), findsNothing);
  }

  testWidgets('hides Adopt to cloud for a trashed project', (tester) async {
    await expectAdoptionActionHidden(
      tester,
      project.copyWith(status: ProjectStatus.trashed),
    );
  });

  testWidgets('hides Adopt to cloud for a collaboration project', (
    tester,
  ) async {
    await expectAdoptionActionHidden(
      tester,
      project.copyWith(collaborationRoomCode: 'room-1'),
    );
  });

  testWidgets('rename menu opens the existing Mix dialog', (tester) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 320,
          height: 320,
          child: ProjectCard(
            project: project,
            onTap: () {},
            onDelete: () {},
            onRename: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Rename document'), findsOneWidget);
  });
}
