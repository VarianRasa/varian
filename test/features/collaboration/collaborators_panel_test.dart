import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/features/collaboration/state/collaboration_session_provider.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/collaboration/presentation/widgets/collaborators_panel.dart';
import '../../test_app.dart';

void main() {
  testWidgets('collaborators dialog fits a compact viewport and closes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(const CollaboratorsPanel(projectId: 'compact-panel')),
      ),
    );
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    final dialogRect = tester.getRect(dialog);
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(420));
    expect(find.text('COLLABORATORS'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(dialog, findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('collaborator actions reflow within a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const projectId = 'compact-collaborators';
    const members = {
      'member-a': CanvasMember(
        projectId: projectId,
        userId: 'member-a',
        role: 'editor',
        displayName: 'Avery Local',
        online: true,
      ),
    };
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(collaborationSessionProvider(projectId).notifier)
        .state = const CollaborationSessionState(
      projectId: projectId,
      role: CollaborationRole.owner,
      members: members,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const CollaboratorsPanel(projectId: projectId)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Avery Local'), findsOneWidget);
    expect(find.byType(UiSelect<String>), findsOneWidget);
    expect(find.byTooltip('Remove member'), findsOneWidget);
    expect(find.byTooltip('Request viewport follow'), findsOneWidget);
    expect(find.byTooltip('Request screen tracking'), findsOneWidget);
    final rowSurface = find.byWidgetPredicate(
      (widget) =>
          widget is UiSurface &&
          widget.padding == const EdgeInsets.all(AppSpacing.sm) &&
          widget.borderRadius == BorderRadius.circular(AppRadius.panel),
    );
    final rowRect = tester.getRect(rowSurface);
    expect(rowRect.left, greaterThanOrEqualTo(0));
    expect(rowRect.right, lessThanOrEqualTo(320));
    final dropdownRect = tester.getRect(find.byType(UiSelect<String>));
    expect(dropdownRect.left, greaterThanOrEqualTo(rowRect.left));
    expect(dropdownRect.right, lessThanOrEqualTo(rowRect.right));
    expect(dropdownRect.width, 130);
    expect(
      dropdownRect.height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    for (final tooltip in [
      'Remove member',
      'Request viewport follow',
      'Request screen tracking',
    ]) {
      final rect = tester.getRect(find.byTooltip(tooltip));
      expect(rect.left, greaterThanOrEqualTo(rowRect.left));
      expect(rect.right, lessThanOrEqualTo(rowRect.right));
      expect(rect.width, AppControlSize.minimumHitTarget);
      expect(rect.height, AppControlSize.minimumHitTarget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders local collaborator role and removal controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const projectId = 'local-collaborators';
    const members = {
      'member-a': CanvasMember(
        projectId: projectId,
        userId: 'member-a',
        role: 'editor',
        displayName: 'Avery Local',
        online: true,
      ),
    };
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(collaborationSessionProvider(projectId).notifier)
        .state = const CollaborationSessionState(
      projectId: projectId,
      role: CollaborationRole.owner,
      members: members,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const CollaboratorsPanel(projectId: projectId)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Avery Local'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.byType(UiSelect<String>), findsOneWidget);
    expect(find.byTooltip('Remove member'), findsOneWidget);
    final rowSurface = find.byWidgetPredicate(
      (widget) =>
          widget is UiSurface &&
          widget.padding == const EdgeInsets.all(AppSpacing.sm) &&
          widget.borderRadius == BorderRadius.circular(AppRadius.panel),
    );
    final rowRect = tester.getRect(rowSurface);
    expect(rowRect.left, greaterThanOrEqualTo(0));
    expect(rowRect.right, lessThanOrEqualTo(420));
    expect(rowRect.top, greaterThanOrEqualTo(0));
    expect(rowRect.bottom, lessThanOrEqualTo(700));
    final avatar = tester.getSize(find.byType(CircleAvatar));
    expect(avatar, const Size(34, 34));
    final roleControl = find.byType(UiSelect<String>);
    final roleRect = tester.getRect(roleControl);
    expect(roleRect.width, 130);
    expect(roleRect.right, lessThanOrEqualTo(rowRect.right));
    final removeRect = tester.getRect(find.byTooltip('Remove member'));
    expect(removeRect.right, lessThanOrEqualTo(rowRect.right));
    expect(tester.takeException(), isNull);
  });
}
