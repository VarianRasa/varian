import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/media/audio_player_screen.dart';
import '../../test_app.dart';

import 'package:flutter/material.dart';

void main() {
  testWidgets('offers retry when the audio source cannot be resolved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        const AudioPlayerScreen(title: 'Test track', artist: 'Test artist'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Exception: Audio source is empty'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Exception: Audio source is empty'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    final retryRect = tester.getRect(find.text('Retry'));
    expect(retryRect.left, greaterThanOrEqualTo(0));
    expect(retryRect.right, lessThanOrEqualTo(390));
    expect(retryRect.top, greaterThanOrEqualTo(0));
    expect(retryRect.bottom, lessThanOrEqualTo(844));
    expect(tester.takeException(), isNull);
  });
}
