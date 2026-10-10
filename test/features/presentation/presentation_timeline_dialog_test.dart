import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/features/presentation/presentation_timeline_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/presentation/domain/storyboard_timeline.dart';

import '../../test_app.dart';

void main() {
  testWidgets('timeline dialog fits compact view and applies its shot data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const timeline = PresentationTimeline(
      shots: [
        StoryboardShot(id: 'shot-a', title: 'Opening', frameId: 'frame-a'),
        StoryboardShot(id: 'shot-b', title: 'Closing', frameId: 'frame-b'),
      ],
    );
    PresentationTimeline? applied;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showUiDialog<PresentationTimeline>(
                context: context,
                builder: (_) =>
                    const PresentationTimelineDialog(initialTimeline: timeline),
              ).then((result) => applied = result),
              child: const Text('Open timeline'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open timeline'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 296);
    expect(dialog.constraints!.maxHeight, 456);
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final applyRect = tester.getRect(find.text('Apply order'));
    expect(applyRect.left, greaterThanOrEqualTo(dialogRect.left));
    expect(applyRect.right, lessThanOrEqualTo(dialogRect.right));
    expect(applyRect.bottom, lessThanOrEqualTo(dialogRect.bottom));
    expect(find.byType(PresentationTimelineDialog), findsOneWidget);
    expect(find.text('Opening'), findsOneWidget);
    expect(find.text('Closing'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Apply order'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Apply order'));
    await tester.pumpAndSettle();

    expect(applied?.shots.map((shot) => shot.id), ['shot-a', 'shot-b']);
    expect(applied?.shots.first.frameId, 'frame-a');
  });
}
