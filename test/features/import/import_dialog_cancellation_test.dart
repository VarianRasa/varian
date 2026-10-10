import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_package.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/import/presentation/import_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets(
    'cancelling an import preview leaves the current project intact',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final existing = _node('existing');
      final rawJson = CanvasDocumentPackage(
        document: CanvasDocument(
          projectId: 'import-cancel-test',
          nodes: [_node('imported')],
          updatedAt: DateTime.utc(2026, 9, 13),
        ),
      ).encode();
      container.read(documentNodesProvider.notifier).setNodes([existing]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(const _DialogLauncher()),
        ),
      );

      await tester.tap(find.text('Open import dialog'));
      await tester.pumpAndSettle();
      final canvasJsonTab = find.text('CANVAS JSON');
      await tester.ensureVisible(canvasJsonTab);
      await tester.pumpAndSettle();
      await tester.tap(canvasJsonTab);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, rawJson);
      await tester.tap(find.text('Preview Import'));
      await tester.pumpAndSettle();

      expect(find.text('IMPORT PREVIEW'), findsOneWidget);
      expect(container.read(documentNodesProvider), [existing]);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('IMPORT DIAGRAM / DOCUMENT'), findsNothing);
      expect(container.read(documentNodesProvider), [existing]);
    },
  );
}

CanvasNode _node(String id) => CanvasNode(
  id: id,
  type: NodeType.rectangle,
  x: 0,
  y: 0,
  width: 120,
  height: 80,
  payload: ShapePayload(),
);

class _DialogLauncher extends StatelessWidget {
  const _DialogLauncher();

  @override
  Widget build(BuildContext context) => UiButton(
    onPressed: () => showUiDialog<void>(
      context: context,
      builder: (_) =>
          ImportDialog(projectId: 'import-cancel-test', onImport: (_) async {}),
    ),
    child: const Text('Open import dialog'),
  );
}
