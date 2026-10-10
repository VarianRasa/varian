import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/review/domain/review_workflow.dart';
import 'package:varian/features/review/presentation/review_workflow_dialog.dart';

import '../../test_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('review workflow fits compact viewport with close reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          const ReviewWorkflowDialog(
            projectId: 'compact-review-project',
            actorId: 'editor-1',
            canEditCanvas: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 296);
    expect(dialog.constraints!.maxHeight, 456);
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final done = tester.getRect(find.text('Done'));
    expect(done.left, greaterThanOrEqualTo(dialogRect.left));
    expect(done.right, lessThanOrEqualTo(dialogRect.right));
    expect(done.bottom, lessThanOrEqualTo(dialogRect.bottom));
    expect(tester.takeException(), isNull);
  });
  testWidgets('announces review workflow load errors', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ccs_review_workflow_review-project': '{invalid json',
    });

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          const ReviewWorkflowDialog(
            projectId: 'review-project',
            actorId: 'editor-1',
            canEditCanvas: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final error = find.text(
      'Review workflow unavailable: '
      'Review workflow is corrupt and could not be recovered.',
    );
    expect(error, findsOneWidget);
    expect(tester.getSemantics(error).flagsCollection.isLiveRegion, isTrue);
  });

  testWidgets(
    'editor can configure approval, checklist, walkthrough, and notes',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            const ReviewWorkflowDialog(
              projectId: 'review-project',
              actorId: 'editor-1',
              canEditCanvas: true,
              selectedNodeId: 'node-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final approval = find.byKey(const ValueKey('review-approval-state'));
      await tester.tap(approval);
      await tester.pumpAndSettle();
      await tester.tap(find.text('In review').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('review-checklist-input')),
        'Verify responsive export',
      );
      final addChecklist = find.byKey(const ValueKey('review-add-checklist'));
      await tester.ensureVisible(addChecklist);
      await tester.tap(addChecklist);
      await tester.pumpAndSettle();
      expect(find.text('Verify responsive export'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('review-step-title')),
        'Inspect hero frame',
      );
      await tester.enterText(
        find.byKey(const ValueKey('review-step-description')),
        'Check the primary call to action.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('review-step-node')),
        'node-1',
      );
      final saveStep = find.byKey(const ValueKey('review-save-step'));
      await tester.ensureVisible(saveStep);
      await tester.tap(saveStep);
      await tester.pumpAndSettle();
      expect(find.text('Inspect hero frame'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('review-speaker-notes')),
        'Explain the hierarchy.',
      );
      final saveNotes = find.byKey(const ValueKey('review-save-notes'));
      await tester.ensureVisible(saveNotes);
      await tester.tap(saveNotes);
      await tester.pumpAndSettle();

      final useSelectedNode = find.byKey(
        const ValueKey('review-use-selected-node'),
      );
      await tester.ensureVisible(useSelectedNode);
      await tester.tap(useSelectedNode);
      final applySpotlight = find.byKey(
        const ValueKey('review-apply-spotlight'),
      );
      await tester.ensureVisible(applySpotlight);
      await tester.tap(applySpotlight);
      await tester.pumpAndSettle();
      expect(find.text('Active on node-1.'), findsOneWidget);
    },
  );

  testWidgets(
    'reviewer-only dialog allows approval but hides editor controls',
    (tester) async {
      final storage = LocalStorageService();
      await storage.saveReviewWorkflow(
        ReviewWorkflow(
          projectId: 'review-project',
          reviewerIds: const ['reviewer-1'],
          updatedAt: DateTime.utc(2026, 9, 13),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            const ReviewWorkflowDialog(
              projectId: 'review-project',
              actorId: 'reviewer-1',
              canEditCanvas: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reviewer'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('review-save-reviewers')),
        findsOneWidget,
      );
      final saveReviewers = tester.widget<Widget>(
        find.byKey(const ValueKey('review-save-reviewers')),
      );
      expect(saveReviewers, isNotNull);
      expect(
        find.byKey(const ValueKey('review-add-checklist')),
        findsOneWidget,
      );
    },
  );
}
