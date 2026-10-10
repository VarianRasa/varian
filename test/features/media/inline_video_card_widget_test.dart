import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/media/inline_video_card_widget.dart';

import '../../test_app.dart';

void main() {
  testWidgets(
    'missing video source renders local error without player startup',
    (tester) async {
      await tester.pumpWidget(
        testApp(
          const Center(
            child: SizedBox(
              width: 320,
              height: 180,
              child: InlineVideoCardWidget(sourcePath: ''),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Video source is missing.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final card = tester.getRect(find.byType(InlineVideoCardWidget));
      expect(card.width, 320);
      expect(card.height, 180);
      final error = tester.getRect(find.text('Video source is missing.'));
      expect(error.left, greaterThanOrEqualTo(card.left));
      expect(error.right, lessThanOrEqualTo(card.right));
      expect(error.top, greaterThanOrEqualTo(card.top));
      expect(error.bottom, lessThanOrEqualTo(card.bottom));
      expect(tester.takeException(), isNull);
    },
  );
}
