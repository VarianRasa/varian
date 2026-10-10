import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/timelapse_playback_dialog.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

import '../../test_app.dart';

void main() {
  testWidgets('time-lapse slider announces frames and seeks recorded actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final payload = DrawingPaperPayload(
      presetName: 'Time-lapse test',
      pixelWidth: 240,
      pixelHeight: 180,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final listener = container.listen(
      drawingStudioProviderFamily(payload),
      (_, _) {},
    );
    addTearDown(listener.close);
    final notifier = container.read(
      drawingStudioProviderFamily(payload).notifier,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    notifier.addLayer(name: 'Timeline layer');
    expect(notifier.timelapseRecorder.frameCount, 2);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) =>
                    TimelapsePlaybackDialog(initialPayload: payload),
              ),
              child: const Text('Open playback'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open playback'));
    await tester.pumpAndSettle();
    final dialogBounds = tester.getRect(find.byType(Dialog).last);
    expect(dialogBounds.left, greaterThanOrEqualTo(0));
    expect(dialogBounds.right, lessThanOrEqualTo(360));
    expect(dialogBounds.top, greaterThanOrEqualTo(0));
    expect(dialogBounds.bottom, lessThanOrEqualTo(300));
    for (final control in [
      find.byTooltip('Close time-lapse playback'),
      find.byTooltip('Play playback'),
      find.byKey(const ValueKey('timelapse-frame-slider')),
    ]) {
      final bounds = tester.getRect(control);
      expect(bounds.left, greaterThanOrEqualTo(dialogBounds.left));
      expect(bounds.right, lessThanOrEqualTo(dialogBounds.right));
      expect(bounds.top, greaterThanOrEqualTo(dialogBounds.top));
      expect(bounds.bottom, lessThanOrEqualTo(dialogBounds.bottom));
    }
    final playbackDialog = tester.widget<Dialog>(find.byType(Dialog).last);
    expect(
      (playbackDialog.shape! as RoundedRectangleBorder).side.width,
      AppBorder.thin,
    );
    final playbackDivider = tester.widget<Divider>(
      find.descendant(
        of: find.byType(TimelapsePlaybackDialog),
        matching: find.byType(Divider),
      ),
    );
    expect(playbackDivider.thickness, AppBorder.thin);

    final slider = find.byKey(const ValueKey('timelapse-frame-slider'));
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Time-lapse frame'), findsOneWidget);
    expect(find.textContaining('Frame: 0 / 2'), findsOneWidget);
    expect(find.textContaining('Action: Initial Open'), findsOneWidget);
    await tester.tap(slider);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.textContaining('Frame: 1 / 2'), findsOneWidget);
    expect(find.textContaining('Action: Add Layer'), findsOneWidget);
    expect(
      tester.getSize(find.byType(Dialog).last).height,
      lessThanOrEqualTo(300),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
