import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/publishing/domain/published_snapshot.dart';
import 'package:varian/features/publishing/presentation/published_snapshot_dialog.dart';
import 'package:varian/app/widgets/ui_primitives.dart';

import '../../test_app.dart';

void main() {
  testWidgets('snapshot dialog and publish action fit a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testApp(
        PublishedSnapshotDialog(
          document: CanvasDocument(
            projectId: 'dialog-project',
            updatedAt: DateTime.utc(2026, 9, 11),
          ),
          publishedBy: 'owner',
          onPublish: (_) async => null,
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
    final publishButton = find.byKey(const ValueKey('publish-snapshot-button'));
    final publishRect = tester.getRect(publishButton);
    expect(publishRect.left, greaterThanOrEqualTo(dialogRect.left));
    expect(publishRect.right, lessThanOrEqualTo(dialogRect.right));
    expect(publishRect.bottom, lessThanOrEqualTo(dialogRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('publishes a configured immutable snapshot', (tester) async {
    PublishedSnapshot? published;
    await tester.pumpWidget(
      testApp(
        PublishedSnapshotDialog(
          document: CanvasDocument(
            projectId: 'dialog-project',
            updatedAt: DateTime.utc(2026, 9, 11),
          ),
          publishedBy: 'owner',
          onPublish: (snapshot) async {
            published = snapshot;
            return 'https://example.test/share/dialog-project';
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('publish-snapshot-button')));
    await tester.pumpAndSettle();

    expect(published?.projectId, 'dialog-project');
    expect(published?.version, 1);
    expect(published?.contentHash, isNotEmpty);
    expect(find.text('Published v1'), findsOneWidget);
    expect(
      find.text('https://example.test/share/dialog-project'),
      findsOneWidget,
    );
  });

  testWidgets('requires a password for protected snapshots', (tester) async {
    await tester.pumpWidget(
      testApp(
        PublishedSnapshotDialog(
          document: CanvasDocument(
            projectId: 'dialog-project',
            updatedAt: DateTime.utc(2026, 9, 11),
          ),
          publishedBy: 'owner',
          onPublish: (_) async => null,
        ),
      ),
    );
    await tester.pump();
    final access = find.byKey(const ValueKey('published-access'));
    await tester.tap(access);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Password protected').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('publish-snapshot-button')));
    await tester.pumpAndSettle();

    final error = find.text('Password is required for protected snapshots.');
    expect(error, findsOneWidget);
    expect(tester.getSemantics(error).flagsCollection.isLiveRegion, isTrue);
  });

  testWidgets('announces publish failures to assistive technology', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        PublishedSnapshotDialog(
          document: CanvasDocument(
            projectId: 'dialog-project',
            updatedAt: DateTime.utc(2026, 9, 11),
          ),
          publishedBy: 'owner',
          onPublish: (_) async => throw StateError('remote unavailable'),
        ),
      ),
    );
    await tester.pump();

    final access = find.byKey(const ValueKey('published-access'));
    await tester.tap(access);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Password protected').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('published-password')),
      'safe-test-password',
    );
    await tester.tap(find.byKey(const ValueKey('publish-snapshot-button')));
    await tester.pumpAndSettle();

    final error = find.textContaining('Publish failed:');
    expect(error, findsOneWidget);
    expect(tester.getSemantics(error).flagsCollection.isLiveRegion, isTrue);
  });
}
