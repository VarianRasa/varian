import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/media/embed_webview_screen.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../test_app.dart';

void main() {
  testWidgets('shows a responsive external-link fallback on desktop', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    try {
      await tester.pumpWidget(
        testApp(
          const EmbedWebviewScreen(
            url: 'https://example.com/document',
            title: 'Reference document',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('REFERENCE DOCUMENT'), findsOneWidget);
      expect(find.text('https://example.com/document'), findsOneWidget);
      expect(find.text('OPEN EXTERNAL LINK'), findsOneWidget);
      expect(find.byType(UiPageScaffold), findsOneWidget);
      final externalLinkButton = find.ancestor(
        of: find.text('OPEN EXTERNAL LINK'),
        matching: find.byType(UiButton),
      );
      expect(externalLinkButton, findsOneWidget);
      final buttonRect = tester.getRect(externalLinkButton);
      expect(buttonRect.left, greaterThanOrEqualTo(0));
      expect(buttonRect.right, lessThanOrEqualTo(320));
      expect(buttonRect.top, greaterThanOrEqualTo(0));
      expect(buttonRect.bottom, lessThanOrEqualTo(568));
      expect(find.byType(WebViewWidget), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
    expect(tester.takeException(), isNull);
  });
}
