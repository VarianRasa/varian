import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/history/presentation/version_diff_dialog.dart';
import 'package:varian/features/history/snapshot_manager.dart';

import '../../test_app.dart';

void main() {
  testWidgets('version diff fits compact viewport and shows local changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    CanvasDocument document({double x = 0}) => CanvasDocument(
      projectId: 'local-project',
      nodes: [
        CanvasNode(
          id: 'local-node',
          type: NodeType.rectangle,
          x: x,
          y: 0,
          width: 100,
          height: 80,
          payload: ShapePayload(),
        ),
      ],
      updatedAt: DateTime.utc(2026, 10, 3),
    );
    final snapshot = DocumentSnapshotRecord(
      id: 'local-snapshot',
      description: 'Local fixture',
      timestamp: DateTime.utc(2026, 10, 2),
      document: document(),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) => VersionDiffDialog(
                  current: document(x: 12),
                  snapshot: snapshot,
                ),
              ),
              child: const Text('Open version diff'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open version diff'));
    await tester.pumpAndSettle();

    expect(find.text('VERSION DIFF'), findsOneWidget);
    expect(find.text('1 changes'), findsOneWidget);
    expect(find.text('1 node diubah'), findsOneWidget);
    expect(find.text('Local fixture'), findsOneWidget);
    final dialog = tester.getRect(find.byType(Dialog));
    expect(dialog.left, greaterThanOrEqualTo(0));
    expect(dialog.right, lessThanOrEqualTo(320));
    expect(dialog.bottom, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('VERSION DIFF'), findsNothing);
  });
}
