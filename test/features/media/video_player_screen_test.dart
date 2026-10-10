import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/media/video_player_screen.dart';

import '../../test_app.dart';

void main() {
  testWidgets(
    'video source error remains usable on compact large-text screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: const VideoPlayerScreen(sourcePath: ''),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('VIDEO PLAYER'), findsOneWidget);
      expect(find.text('Video source is missing.'), findsOneWidget);
      final retry = find.text('Retry');
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      final retryRect = tester.getRect(retry);
      expect(retryRect.top, greaterThanOrEqualTo(0));
      expect(retryRect.bottom, lessThanOrEqualTo(320));
      expect(retryRect.left, greaterThanOrEqualTo(0));
      expect(retryRect.right, lessThanOrEqualTo(320));
      final back = tester.getRect(find.byTooltip('Back'));
      expect(back.left, greaterThanOrEqualTo(0));
      expect(back.right, lessThanOrEqualTo(320));
      expect(back.top, greaterThanOrEqualTo(0));
      expect(back.bottom, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);

      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('Video source is missing.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
