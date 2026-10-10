import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/ai_canvas_actions.dart';
import 'package:varian/features/ai/domain/ai_canvas_transaction.dart';
import 'package:varian/features/ai/presentation/ai_canvas_transaction_review.dart';
import 'package:varian/features/ai/state/ai_canvas_transaction_provider.dart';
import 'package:varian/features/ai/state/ai_provider.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/ai/presentation/ai_panel.dart';
import '../../test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('preview plans a mutation without changing the canvas', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final nodes = container.read(documentNodesProvider.notifier);
    nodes.addNode(_rectangle('a', 0, 0));
    nodes.addNode(_rectangle('b', 300, 0));
    final notifier = container.read(
      aiCanvasTransactionProvider('project-1').notifier,
    );

    final entry = await notifier.previewAction(
      AICanvasAction.tidyNodes(selectionIds: const ['a', 'b']),
    );

    expect(entry, isNotNull);
    expect(entry!.phase, AICanvasTransactionPhase.preview);
    expect(entry.preview?.plannedNodes, hasLength(2));
    expect(container.read(documentNodesProvider).map((node) => node.x), [
      0,
      300,
    ]);
  });

  test('apply and undo keep one AI transaction in editor history', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final nodes = container.read(documentNodesProvider.notifier);
    nodes.addNode(_rectangle('a', 0, 0));
    nodes.addNode(_rectangle('b', 300, 0));
    final notifier = container.read(
      aiCanvasTransactionProvider('project-2').notifier,
    );
    final entry = await notifier.previewAction(
      AICanvasAction.tidyNodes(
        selectionIds: const ['a', 'b'],
        strategy: 'vertical',
        gap: 20,
      ),
    );

    final result = await notifier.apply(entry!.id);
    expect(result?.isSuccess, isTrue);
    expect(
      notifier.state.entries.first.phase,
      AICanvasTransactionPhase.applied,
    );
    expect(container.read(documentNodesProvider).last.y, greaterThan(0));

    expect(await notifier.undo(entry.id), isTrue);
    expect(notifier.state.entries.first.phase, AICanvasTransactionPhase.undone);
    expect(container.read(documentNodesProvider).map((node) => node.x), [
      0,
      300,
    ]);
  });

  test('stale previews are rejected and remain non-destructive', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final nodes = container.read(documentNodesProvider.notifier);
    nodes.addNode(_rectangle('a', 0, 0));
    nodes.addNode(_rectangle('b', 300, 0));
    final notifier = container.read(
      aiCanvasTransactionProvider('project-3').notifier,
    );
    final entry = await notifier.previewAction(
      AICanvasAction.tidyNodes(selectionIds: const ['a', 'b']),
    );
    nodes.updateTransientNode(_rectangle('a', 20, 0));

    final result = await notifier.apply(entry!.id);

    expect(result?.status, AICanvasActionStatus.rejected);
    expect(
      notifier.state.entries.first.phase,
      AICanvasTransactionPhase.rejected,
    );
    expect(container.read(documentNodesProvider).first.x, 20);
  });

  test('transaction history strips generated runtime URLs', () async {
    final now = DateTime.utc(2026, 9, 23);
    final job = AIJob(
      id: 'job-runtime-history',
      projectId: 'project-history',
      capability: AICapability.textToImage,
      prompt: 'generated',
      resultAssetUrl: 'https://cdn.example.test/out.png?token=secret',
      resultImageUrls: const ['blob:https://example.test/runtime'],
      createdAt: now,
      updatedAt: now,
    );
    final action = AICanvasAction.placeGeneratedOutput(job: job);
    final entry = AICanvasTransactionEntry(
      id: 'tx-runtime-history',
      projectId: 'project-history',
      action: action,
      createdAt: now,
      updatedAt: now,
    );
    final encoded = entry.toJson().toString();

    expect(encoded, isNot(contains('token=secret')));
    expect(encoded, isNot(contains('blob:')));
    expect(encoded, isNot(contains('out.png')));
  });

  test(
    'transaction history persists action state and can be reloaded',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final nodes = container.read(documentNodesProvider.notifier);
      nodes.addNode(_rectangle('a', 0, 0));
      nodes.addNode(_rectangle('b', 100, 0));
      final notifier = container.read(
        aiCanvasTransactionProvider('project-4').notifier,
      );
      final entry = await notifier.previewAction(
        AICanvasAction.groupNodes(selectionIds: const ['a', 'b']),
      );
      await notifier.reject(entry!.id);

      final restored = await LocalStorageService().loadAICanvasTransactions(
        'project-4',
      );

      expect(restored, hasLength(1));
      expect(restored.single.action.type, AICanvasActionType.groupNodes);
      expect(restored.single.phase, AICanvasTransactionPhase.rejected);
    },
  );

  testWidgets('review card keeps mutation actions inside a compact surface', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var applied = 0;
    final now = DateTime.utc(2026, 9, 13);
    final action = AICanvasAction.groupNodes(selectionIds: const ['a', 'b']);
    final entry = AICanvasTransactionEntry(
      id: 'tx-1',
      projectId: 'project-5',
      action: action,
      preview: AICanvasActionPreview(
        action: action,
        status: AICanvasActionStatus.confirmationRequired,
        text: 'Group selected nodes.',
        documentFingerprint: 'fingerprint',
      ),
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      testApp(
        SizedBox(
          width: 288,
          child: AICanvasTransactionCard(
            entry: entry,
            onApply: () => applied++,
            onInsert: () {},
            onReplace: () {},
            onReject: () {},
          ),
        ),
      ),
    );

    final card = tester.getRect(find.byType(AICanvasTransactionCard));
    expect(card.left, greaterThanOrEqualTo(0));
    expect(card.right, lessThanOrEqualTo(320));
    expect(find.text('Group selected nodes.'), findsOneWidget);
    for (final label in ['Apply', 'Insert', 'Replace', 'Reject']) {
      final button = tester.getRect(find.text(label));
      expect(button.left, greaterThanOrEqualTo(card.left));
      expect(button.right, lessThanOrEqualTo(card.right));
      expect(button.top, greaterThanOrEqualTo(card.top));
      expect(button.bottom, lessThanOrEqualTo(card.bottom));
    }
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(applied, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('transaction review host bounds a persisted local card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final action = AICanvasAction.groupNodes(selectionIds: const ['a', 'b']);
    final now = DateTime.utc(2026, 9, 13);
    final entry = AICanvasTransactionEntry(
      id: 'local-review-entry',
      projectId: 'review-host',
      action: action,
      text: 'Group selected nodes.',
      createdAt: now,
      updatedAt: now,
    );
    await LocalStorageService().saveAICanvasTransactions('review-host', [
      entry,
    ]);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          const SingleChildScrollView(
            child: AICanvasTransactionReview(projectId: 'review-host'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final review = tester.getRect(find.byType(AICanvasTransactionReview));
    final card = tester.getRect(find.byType(AICanvasTransactionCard));
    expect(review.left, greaterThanOrEqualTo(0));
    expect(review.right, lessThanOrEqualTo(320));
    expect(card.left, greaterThanOrEqualTo(review.left));
    expect(card.right, lessThanOrEqualTo(review.right));
    expect(find.text('Group selected nodes.'), findsOneWidget);
    for (final label in ['Apply', 'Insert', 'Replace', 'Reject']) {
      final bounds = tester.getRect(find.text(label));
      expect(bounds.left, greaterThanOrEqualTo(card.left));
      expect(bounds.right, lessThanOrEqualTo(card.right));
      expect(bounds.top, greaterThanOrEqualTo(card.top));
      expect(bounds.bottom, lessThanOrEqualTo(card.bottom));
    }
    expect(tester.takeException(), isNull);
  });
  test('read-only transactions reject canvas mutations', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final nodes = container.read(documentNodesProvider.notifier);
    nodes.addNode(_rectangle('a', 0, 0));
    nodes.addNode(_rectangle('b', 300, 0));
    final executor = AICanvasActionExecutor(
      nodesNotifier: nodes,
      edgesNotifier: container.read(documentEdgesProvider.notifier),
      readOnly: true,
    );

    final preview = await executor.preview(
      AICanvasAction.tidyNodes(selectionIds: const ['a', 'b']),
    );
    final result = await executor.execute(
      AICanvasAction.tidyNodes(selectionIds: const ['a', 'b']),
      confirmed: true,
    );

    expect(preview.status, AICanvasActionStatus.rejected);
    expect(result.status, AICanvasActionStatus.rejected);
    expect(container.read(documentNodesProvider).map((node) => node.x), [
      0,
      300,
    ]);
  });

  test('rejects the legacy fabricated agentArrange proposal', () {
    expect(
      () => AICanvasAction.fromAssistant(
        const AIAssistantAction(
          actionType: 'agentArrange',
          payload: {'align': 'smart_grid'},
          description: 'Unverified layout suggestion.',
        ),
      ),
      throwsA(isA<AICanvasActionValidationException>()),
    );
  });

  testWidgets('Generate panel fits narrow view without review card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(353, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(child: testApp(const AIPanel(projectId: 'generate-panel'))),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('OUTPUT SEMANTICS'), findsNothing);
    expect(find.byType(AICanvasTransactionReview), findsNothing);
    expect(find.byTooltip('Add or choose output'), findsOneWidget);
    expect(find.text('Generate'), findsOneWidget);
    expect(find.text('Enhance'), findsNothing);
    await tester.tap(find.byTooltip('Show options'));
    await tester.pumpAndSettle();
    expect(find.text('OUTPUT SEMANTICS'), findsOneWidget);

    final panelContext = tester.element(find.byType(AIPanel));
    ProviderScope.containerOf(panelContext)
        .read(aiCreativeEngineProvider.notifier)
        .setCategory(AICreativeCategory.aiAssistant);
    await tester.pumpAndSettle();

    expect(find.text('Assistant'), findsOneWidget);
    expect(find.text('OUTPUT SEMANTICS'), findsNothing);
    expect(find.text('Ask'), findsOneWidget);
    expect(
      find.text('Canvas context is sent to a chat provider.'),
      findsOneWidget,
    );
    expect(
      find.text('Responses are text-only and do not create canvas actions.'),
      findsOneWidget,
    );
  });
}

CanvasNode _rectangle(String id, double x, double y) => CanvasNode(
  id: id,
  type: NodeType.rectangle,
  x: x,
  y: y,
  width: 100,
  height: 80,
  payload: ShapePayload(),
);
