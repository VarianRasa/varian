import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/link_card/presentation/link_card_inspector.dart';

import '../../test_app.dart';

void main() {
  testWidgets('link inspector uses local metadata and shared surface spacing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final node = CanvasNode(
      id: 'local-link-inspector',
      type: NodeType.linkCard,
      x: 0,
      y: 0,
      width: 240,
      height: 160,
      payload: LinkPayload(
        title: 'Local reference',
        url: 'https://example.invalid/reference',
        description: 'Fixture metadata only',
        previewStatus: LinkPreviewStatus.error,
        previewError: 'Local preview unavailable',
      ),
    );

    await tester.pumpWidget(
      testApp(
        SingleChildScrollView(
          child: LinkCardInspector(
            node: node,
            onSubmitUrl: (_) {},
            onTitleChanged: (_) {},
            onDescriptionChanged: (_) {},
            onRefresh: () {},
            onOpenInApp: () {},
            onOpenExternal: () {},
          ),
        ),
      ),
    );

    final surfaces = tester
        .widgetList<UiSurface>(find.byType(UiSurface))
        .toList();
    expect(surfaces, hasLength(1));
    expect(surfaces.single.padding, const EdgeInsets.all(AppSpacing.sm));
    expect(find.text('example.invalid'), findsOneWidget);
    expect(find.text('Local preview unavailable'), findsOneWidget);
    expect(find.byKey(const Key('link-inspector-url')), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
