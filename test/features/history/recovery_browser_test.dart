import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/history/presentation/recovery_browser.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/history/snapshot_manager.dart';

import '../../test_app.dart';

void main() {
  testWidgets('recovery list dividers use the thin border token', (
    tester,
  ) async {
    final records = [
      DocumentSnapshotRecord(
        id: 'snapshot-1',
        document: CanvasDocument(
          projectId: 'project',
          updatedAt: DateTime.utc(2026, 10, 3),
        ),
        timestamp: DateTime.utc(2026, 10, 3),
        description: 'Snapshot one',
      ),
      DocumentSnapshotRecord(
        id: 'snapshot-2',
        document: CanvasDocument(
          projectId: 'project',
          updatedAt: DateTime.utc(2026, 10, 2),
        ),
        timestamp: DateTime.utc(2026, 10, 2),
        description: 'Snapshot two',
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(RecoveryBrowser(versions: AsyncValue.data(records))),
      ),
    );

    final dividers = tester.widgetList<Divider>(find.byType(Divider));
    expect(dividers, hasLength(2));
    expect(
      dividers.map((divider) => divider.height),
      everyElement(AppBorder.thin),
    );
    expect(find.text('Snapshot one'), findsOneWidget);
    expect(find.text('Snapshot two'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'compact recovery actions stay in bounds and reach local callbacks',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final record = DocumentSnapshotRecord(
        id: 'compact-snapshot',
        document: CanvasDocument(
          projectId: 'project',
          updatedAt: DateTime.utc(2026, 10, 3),
        ),
        timestamp: DateTime.utc(2026, 10, 3),
        description: 'Compact local snapshot',
      );
      final restored = <String>[];
      final deleted = <String>[];

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            RecoveryBrowser(
              versions: AsyncValue.data([record]),
              onRestore: (snapshot) => restored.add(snapshot.id),
              onDelete: (snapshot) => deleted.add(snapshot.id),
            ),
          ),
        ),
      );

      final viewport = const Rect.fromLTWH(0, 0, 320, 480);
      final surface = tester.getRect(find.byType(UiSurface));
      expect(surface.left, greaterThanOrEqualTo(viewport.left));
      expect(surface.right, lessThanOrEqualTo(viewport.right));
      expect(surface.top, greaterThanOrEqualTo(viewport.top));
      expect(surface.bottom, lessThanOrEqualTo(viewport.bottom));
      for (final action in [
        find.byTooltip('Restore Compact local snapshot'),
        find.byTooltip('Delete Compact local snapshot'),
      ]) {
        final rect = tester.getRect(action);
        expect(rect.left, greaterThanOrEqualTo(surface.left));
        expect(rect.right, lessThanOrEqualTo(surface.right));
        expect(rect.top, greaterThanOrEqualTo(surface.top));
        expect(rect.bottom, lessThanOrEqualTo(surface.bottom));
      }

      await tester.tap(find.byTooltip('Restore Compact local snapshot'));
      await tester.tap(find.byTooltip('Delete Compact local snapshot'));
      expect(restored, ['compact-snapshot']);
      expect(deleted, ['compact-snapshot']);
      expect(tester.takeException(), isNull);
    },
  );
}
