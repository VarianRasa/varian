import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/export/export_presets.dart';
import 'package:varian/features/history/presentation/recovery_browser.dart';
import 'package:varian/features/history/snapshot_manager.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import '../test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export preset registry resolves stable IDs and all capabilities', () {
    expect(
      ExportPresetRegistry.lookup(' SVG '),
      same(ExportPresetRegistry.svg),
    );
    expect(
      ExportPresetRegistry.lookup('text'),
      same(ExportPresetRegistry.plainText),
    );
    expect(ExportPresetRegistry.lookup('unknown'), isNull);
    expect(
      ExportPresetRegistry.byFormat(ExportPresetFormat.pdf),
      same(ExportPresetRegistry.pdf),
    );
    expect(
      ExportPresetRegistry.all.map((preset) => preset.id),
      containsAll(<String>[
        'json',
        'svg',
        'png',
        'markdown',
        'text',
        'drawio',
        'pdf',
      ]),
    );
  });

  testWidgets('recovery browser renders loading and empty states', (
    tester,
  ) async {
    Widget wrap(Widget child) => testApp(child);

    await tester.pumpWidget(
      wrap(const RecoveryBrowser(versions: AsyncValue.loading())),
    );
    expect(find.text('Loading recovery history'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      wrap(const RecoveryBrowser(versions: AsyncValue.data([]))),
    );
    expect(find.text('No saved versions'), findsOneWidget);
  });

  testWidgets('recovery browser delegates restore and delete records', (
    tester,
  ) async {
    final snapshot = DocumentSnapshotRecord(
      id: 'snapshot-1',
      description: 'Before import',
      timestamp: DateTime(2026, 8, 26, 9, 30),
      document: CanvasDocument(
        projectId: 'project-1',
        updatedAt: DateTime(2026, 8, 26),
      ),
    );
    DocumentSnapshotRecord? restored;
    DocumentSnapshotRecord? deleted;

    await tester.pumpWidget(
      testApp(
        RecoveryBrowser(
          versions: AsyncValue.data([snapshot]),
          onRestore: (value) => restored = value,
          onDelete: (value) => deleted = value,
        ),
      ),
    );

    expect(find.text('Before import'), findsOneWidget);
    expect(find.text('1/20 saved'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Restore Before import'));
    await tester.tap(find.bySemanticsLabel('Delete Before import'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(restored, same(snapshot));
    expect(deleted, same(snapshot));
  });
  testWidgets('recovery history scrolls records in a short panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 300);
    tester.view.devicePixelRatio = 1;
    DocumentSnapshotRecord? restored;
    final versions = List.generate(
      20,
      (index) => DocumentSnapshotRecord(
        id: 'snapshot-$index',
        description: 'Snapshot $index',
        timestamp: DateTime(2026, 8, 26, 9, 30).add(Duration(minutes: index)),
        document: CanvasDocument(
          projectId: 'project-1',
          updatedAt: DateTime(2026, 8, 26),
          nodes: [
            CanvasNode(
              id: 'node-$index',
              type: NodeType.rectangle,
              x: 0,
              y: 0,
              width: 40,
              height: 30,
              payload: ShapePayload(),
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      testApp(
        SizedBox(
          width: 320,
          height: 220,
          child: RecoveryBrowser(
            versions: AsyncValue.data(versions),
            onRestore: (record) => restored = record,
          ),
        ),
      ),
    );

    final scrollable = find.descendant(
      of: find.byType(RecoveryBrowser),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Snapshot 19'),
      -240,
      scrollable: scrollable,
    );

    final restoreAction = find.byTooltip('Restore Snapshot 19');
    await tester.ensureVisible(restoreAction);
    await tester.tap(restoreAction);
    expect(restored, same(versions.last));
    expect(tester.takeException(), isNull);
  });
}
