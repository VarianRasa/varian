import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/features/media/media_timeline_editor_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets(
    'timeline editor remains scrollable on compact large-text screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const MediaTimelineEditorDialog(
                        initialTimeline: MediaTimeline(sourceDurationMs: 90000),
                      ),
                    ),
                    child: const Text('Open timeline'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open timeline'));
      await tester.pumpAndSettle();
      final dialog = tester.getRect(find.byType(Dialog));
      expect(dialog.left, greaterThanOrEqualTo(0));
      expect(dialog.right, lessThanOrEqualTo(320));
      expect(dialog.top, greaterThanOrEqualTo(0));
      expect(dialog.bottom, lessThanOrEqualTo(480));

      expect(find.text('Media timeline'), findsOneWidget);
      expect(find.text('Clips and trim'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final apply = find.text('Apply timeline');
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      final applyRect = tester.getRect(apply);
      expect(applyRect.top, greaterThanOrEqualTo(0));
      expect(applyRect.bottom, lessThanOrEqualTo(480));
      expect(applyRect.left, greaterThanOrEqualTo(dialog.left));
      expect(applyRect.right, lessThanOrEqualTo(dialog.right));
      expect(applyRect.top, greaterThanOrEqualTo(dialog.top));
      expect(applyRect.bottom, lessThanOrEqualTo(dialog.bottom));
      final cancelRect = tester.getRect(find.text('Cancel'));
      expect(cancelRect.left, greaterThanOrEqualTo(dialog.left));
      expect(cancelRect.right, lessThanOrEqualTo(dialog.right));
      expect(cancelRect.top, greaterThanOrEqualTo(dialog.top));
      expect(cancelRect.bottom, lessThanOrEqualTo(dialog.bottom));
      expect(tester.takeException(), isNull);

      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(find.text('Apply timeline'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('applying a trim returns the edited clip range', (tester) async {
    MediaTimeline? appliedTimeline;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  appliedTimeline = await showDialog<MediaTimeline>(
                    context: context,
                    builder: (_) => const MediaTimelineEditorDialog(
                      initialTimeline: MediaTimeline(sourceDurationMs: 90000),
                    ),
                  );
                },
                child: const Text('Open timeline'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open timeline'));
    await tester.pumpAndSettle();

    await tester.enterText(find.bySemanticsLabel('Trim start (seconds)'), '10');
    await tester.enterText(find.bySemanticsLabel('Trim end (seconds)'), '60');
    await tester.tap(find.text('Trim'));
    await tester.pumpAndSettle();
    expect(find.text('00:10 – 01:00'), findsOneWidget);

    await tester.tap(find.text('Apply timeline'));
    await tester.pumpAndSettle();

    expect(appliedTimeline, isNotNull);
    expect(appliedTimeline!.sourceDurationMs, 90000);
    expect(appliedTimeline!.clips, hasLength(1));
    expect(appliedTimeline!.clips.single.startMs, 10000);
    expect(appliedTimeline!.clips.single.endMs, 60000);
    expect(tester.takeException(), isNull);
  });
}
