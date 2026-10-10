import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/features/media/inline_audio_card_widget.dart';

import '../../test_app.dart';

void main() {
  testWidgets('missing audio source renders tokenized local error card', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        const Center(
          child: SizedBox(
            width: 320,
            height: 160,
            child: InlineAudioCardWidget(
              title: 'Local track',
              artist: 'Fixture',
              description: 'No media source supplied',
              durationText: '00:00',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Audio unavailable'), findsOneWidget);
    expect(find.byTooltip('Retry'), findsOneWidget);
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(InlineAudioCardWidget),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, AppTokens.dark.panel);
    expect(decoration.borderRadius, BorderRadius.circular(AppRadius.control));
    expect(find.byType(Scaffold), findsNothing);
    final card = tester.getRect(find.byType(InlineAudioCardWidget));
    expect(card.width, 320);
    expect(card.height, 160);
    final retry = tester.getRect(find.byTooltip('Retry'));
    expect(retry.left, greaterThanOrEqualTo(card.left));
    expect(retry.right, lessThanOrEqualTo(card.right));
    expect(retry.top, greaterThanOrEqualTo(card.top));
    expect(retry.bottom, lessThanOrEqualTo(card.bottom));
    expect(tester.takeException(), isNull);
  });
}
