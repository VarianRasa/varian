import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/canvas_screen.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/selection_provider.dart';

import '../../test_app.dart';

class _NoopAutosaveController extends AutosaveController {
  _NoopAutosaveController(super.ref);

  @override
  void init(String projectId, {bool syncCloud = true}) {}

  @override
  Future<void> saveImmediately({bool syncCloud = true}) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('adjacent paper control creates a fresh same-size paper', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final payload = DrawingPaperPayload(
      presetName: 'A5 Notebook',
      pixelWidth: 120,
      pixelHeight: 80,
    );
    final paper = CanvasNode(
      id: 'paper_1',
      type: NodeType.drawingPaper,
      x: 80,
      y: 80,
      width: 240,
      height: 160,
      payload: payload,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          autosaveControllerProvider.overrideWith(
            (ref) => _NoopAutosaveController(ref),
          ),
        ],
        child: testApp(
          const CanvasScreen(
            projectId: 'adjacent-paper-test',
            projectName: 'Adjacent paper test',
          ),
        ),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CanvasScreen)),
    );
    container.read(documentNodesProvider.notifier).setNodes([paper]);
    container.read(selectionProvider.notifier).select(paper.id);
    await tester.pump();

    final addButtons = find.byTooltip('Add same-size paper');
    expect(addButtons, findsNWidgets(4));
    await tester.tap(addButtons.first);
    await tester.pump(const Duration(milliseconds: 200));

    final nodes = container.read(documentNodesProvider);
    expect(nodes, hasLength(2));
    final added = nodes.singleWhere((node) => node.id != paper.id);
    expect(added.width, paper.width);
    expect(added.height, paper.height);
    expect(added.payload, isA<DrawingPaperPayload>());
    final addedPayload = added.payload as DrawingPaperPayload;
    expect(addedPayload.presetName, payload.presetName);
    expect(addedPayload.pixelWidth, payload.pixelWidth);
    expect(addedPayload.pixelHeight, payload.pixelHeight);
    expect(addedPayload.rasterDocumentId, isNot(payload.rasterDocumentId));
    expect(addedPayload.layers, hasLength(1));
    expect(addedPayload.layers.single.strokes, isEmpty);
  });
}
