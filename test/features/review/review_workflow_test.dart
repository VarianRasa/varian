import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/review/domain/review_workflow.dart';
import 'package:varian/features/review/state/review_workflow_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('round trips review workflow and keeps ordered walkthrough', () {
    final workflow = ReviewWorkflow(
      projectId: 'review-project',
      approvalState: ReviewApprovalState.inReview,
      reviewerIds: const ['reviewer-1'],
      updatedBy: 'editor-1',
      updatedAt: DateTime.utc(2026, 9, 13, 8),
      spotlightNodeId: 'node-1',
      spotlightExpiresAt: DateTime.utc(2026, 9, 13, 9),
      handoffChecklist: [
        ReviewChecklistItem(
          id: 'check-1',
          label: 'Verify export',
          completed: true,
          completedBy: 'reviewer-1',
          completedAt: DateTime.utc(2026, 9, 13, 8, 30),
        ),
      ],
      walkthrough: const [
        ReviewWalkthroughStep(id: 'step-2', title: 'Second', order: 2),
        ReviewWalkthroughStep(id: 'step-1', title: 'First', order: 1),
      ],
      speakerNotes: const {'frame-1': 'Explain the hierarchy.'},
    );

    final restored = ReviewWorkflow.fromJson(workflow.toJson());

    expect(restored.projectId, workflow.projectId);
    expect(restored.approvalState, ReviewApprovalState.inReview);
    expect(restored.reviewerIds, ['reviewer-1']);
    expect(restored.handoffChecklist.single.completedBy, 'reviewer-1');
    expect(restored.orderedWalkthrough.map((step) => step.id), [
      'step-1',
      'step-2',
    ]);
    expect(restored.speakerNotes['frame-1'], 'Explain the hierarchy.');
    expect(restored.isReviewer('reviewer-1'), isTrue);
    expect(restored.canReview('reviewer-1', canEditCanvas: false), isTrue);
    expect(restored.canReview('guest', canEditCanvas: false), isFalse);
    expect(
      restored.isSpotlightActive(DateTime.utc(2026, 9, 13, 8, 30)),
      isTrue,
    );
    expect(
      restored.isSpotlightActive(DateTime.utc(2026, 9, 13, 9, 1)),
      isFalse,
    );
  });

  test('provider persists editor workflow actions', () async {
    final storage = LocalStorageService();
    final notifier = ReviewWorkflowNotifier(storage, 'review-project');
    addTearDown(notifier.dispose);

    await notifier.load();
    notifier.configure(actorId: 'editor-1', canEditCanvas: true);
    await notifier.setReviewers(const ['reviewer-1', 'reviewer-1']);
    await notifier.setApprovalState(ReviewApprovalState.inReview);
    await notifier.setSpotlight(
      'node-1',
      duration: const Duration(minutes: 15),
    );
    await notifier.addChecklistItem('Verify export');
    await notifier.upsertWalkthroughStep(
      title: 'Open frame',
      description: 'Start with the main frame.',
      nodeId: 'frame-1',
    );
    await notifier.setSpeakerNotes('frame-1', 'Explain the hierarchy.');

    final workflow = notifier.state.asData!.value;
    final restored = await storage.loadReviewWorkflow('review-project');

    expect(workflow.approvalState, ReviewApprovalState.inReview);
    expect(workflow.reviewerIds, ['reviewer-1']);
    expect(workflow.spotlightNodeId, 'node-1');
    expect(workflow.handoffChecklist.single.label, 'Verify export');
    expect(workflow.walkthrough.single.nodeId, 'frame-1');
    expect(workflow.speakerNotes['frame-1'], 'Explain the hierarchy.');
    expect(restored.toJson(), workflow.toJson());
  });

  test('reviewer can approve but cannot manage reviewer access', () async {
    final storage = LocalStorageService();
    await storage.saveReviewWorkflow(
      ReviewWorkflow(
        projectId: 'review-project',
        reviewerIds: const ['reviewer-1'],
        updatedAt: DateTime.utc(2026, 9, 13),
      ),
    );
    final notifier = ReviewWorkflowNotifier(storage, 'review-project');
    addTearDown(notifier.dispose);

    await notifier.load();
    notifier.configure(actorId: 'reviewer-1', canEditCanvas: false);
    await notifier.setApprovalState(ReviewApprovalState.approved);
    await expectLater(
      notifier.setReviewers(const ['reviewer-2']),
      throwsA(isA<StateError>()),
    );

    expect(
      notifier.state.asData!.value.approvalState,
      ReviewApprovalState.approved,
    );
    expect(notifier.state.asData!.value.reviewerIds, ['reviewer-1']);
  });
}
