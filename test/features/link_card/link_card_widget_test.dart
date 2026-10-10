import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/link_card/presentation/link_card_widget.dart';

void main() {
  testWidgets('empty selected card edits and submits URL', (tester) async {
    String? submitted;
    await tester.pumpWidget(
      _app(
        LinkCardWidget(
          node: _node(LinkPayload()),
          selected: true,
          onSubmitUrl: (value) => submitted = value,
          onRefresh: () {},
          onOpenInApp: () {},
          onOpenExternal: () {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('link-card-url')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('link-card-url')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.byKey(const Key('link-card-url-editor')),
      'https://example.com',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);

    expect(submitted, 'https://example.com');
  });

  testWidgets('direct CDN image links render a CORS-tolerant preview', (
    tester,
  ) async {
    const imageUrl = 'https://i.pinimg.com/736x/reference.jpg';
    await tester.pumpWidget(
      _app(
        LinkCardWidget(
          node: _node(LinkPayload(url: imageUrl)),
          selected: true,
          onSubmitUrl: (_) {},
          onRefresh: () {},
          onOpenInApp: () {},
          onOpenExternal: () {},
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image).first);
    final provider = image.image as NetworkImage;
    expect(provider.url, imageUrl);
    expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.fallback);
  });

  testWidgets('URL label and editor keep touch targets at compact sizes', (
    tester,
  ) async {
    for (final size in [
      const Size(320, 220),
      const Size(180, 120),
      const Size(120, 100),
      const Size(120, 80),
    ]) {
      await tester.pumpWidget(
        _app(
          LinkCardWidget(
            key: ValueKey('link-card-${size.width}x${size.height}'),
            node: _node(LinkPayload(url: 'https://example.com')),
            selected: true,
            onSubmitUrl: (_) {},
            onRefresh: () {},
            onOpenInApp: () {},
            onOpenExternal: () {},
          ),
          size: size,
        ),
      );
      await tester.pump();

      final card = find.byType(LinkCardWidget);
      final url = find.byKey(const Key('link-card-url'));
      expect(url, findsOneWidget, reason: 'URL label at $size');
      final urlRect = tester.getRect(url);
      expect(
        urlRect.height,
        greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
      );
      expect(urlRect.left, greaterThanOrEqualTo(tester.getRect(card).left));
      expect(urlRect.right, lessThanOrEqualTo(tester.getRect(card).right));
      expect(urlRect.bottom, lessThanOrEqualTo(tester.getRect(card).bottom));
      expect(tester.takeException(), isNull);

      await tester.tap(url);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(url);
      await tester.pumpAndSettle();

      final editor = find.byKey(const Key('link-card-url-editor'));
      final editorRect = tester.getRect(editor);
      expect(
        editorRect.height,
        greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
      );
      expect(editorRect.left, greaterThanOrEqualTo(tester.getRect(card).left));
      expect(editorRect.right, lessThanOrEqualTo(tester.getRect(card).right));
      expect(editorRect.bottom, lessThanOrEqualTo(tester.getRect(card).bottom));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('selected card forwards secondary click', (tester) async {
    Offset? position;
    await tester.pumpWidget(
      _app(
        LinkCardWidget(
          node: _node(LinkPayload(url: 'https://example.com')),
          selected: true,
          onSubmitUrl: (_) {},
          onRefresh: () {},
          onOpenInApp: () {},
          onOpenExternal: () {},
          onSecondaryTap: (value) => position = value,
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(LinkCardWidget)),
      buttons: 2,
    );
    await gesture.up();
    await tester.pump();

    expect(position, isNotNull);
  });
  testWidgets('refresh and external actions meet the 40px touch target', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LinkCardWidget(
          node: _node(LinkPayload(url: 'https://example.com')),
          selected: true,
          onSubmitUrl: (_) {},
          onRefresh: () {},
          onOpenInApp: () {},
          onOpenExternal: () {},
        ),
      ),
    );

    for (final key in [
      const Key('link-card-refresh'),
      const Key('link-card-external'),
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(AppControlSize.touch));
      expect(size.height, greaterThanOrEqualTo(AppControlSize.touch));
    }
  });

  testWidgets('ready card exposes refresh and external actions', (
    tester,
  ) async {
    var refreshes = 0;
    var external = 0;
    await tester.pumpWidget(
      _app(
        LinkCardWidget(
          node: _node(
            LinkPayload(
              title: 'Example',
              url: 'https://example.com',
              description: 'Preview description',
              previewStatus: LinkPreviewStatus.ready,
            ),
          ),
          selected: true,
          onSubmitUrl: (_) {},
          onRefresh: () => refreshes++,
          onOpenInApp: () {},
          onOpenExternal: () => external++,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('link-card-refresh')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('link-card-external')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(refreshes, 1);
    expect(external, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('opens and edits from keyboard focus', (tester) async {
    var opens = 0;
    String? submitted;
    await tester.pumpWidget(
      _app(
        LinkCardWidget(
          node: _node(LinkPayload(url: 'https://example.com')),
          selected: true,
          onSubmitUrl: (value) => submitted = value,
          onRefresh: () {},
          onOpenInApp: () => opens++,
          onOpenExternal: () {},
        ),
      ),
    );

    final cardFocus = tester
        .widget<Focus>(find.byKey(const Key('link-card-keyboard-focus')))
        .focusNode!;
    cardFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opens, 1);

    final urlFocus = tester
        .widget<Focus>(find.byKey(const Key('link-card-url-keyboard-focus')))
        .focusNode!;
    urlFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.byKey(const Key('link-card-url-editor')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('link-card-url-editor')),
      'https://updated.example',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, 'https://updated.example');
  });
}

Widget _app(Widget child, {Size size = const Size(320, 220)}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: size.width, height: size.height, child: child),
    ),
  ),
);

CanvasNode _node(LinkPayload payload) => CanvasNode(
  id: 'link',
  type: NodeType.linkCard,
  x: 0,
  y: 0,
  width: 320,
  height: 220,
  payload: payload,
);
