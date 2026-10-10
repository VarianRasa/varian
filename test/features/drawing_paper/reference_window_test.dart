import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/reference_window.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

import '../../test_app.dart';

void main() {
  testWidgets('reference window moves by keyboard and drag within viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final payload = DrawingPaperPayload(
      presetName: 'Reference test',
      pixelWidth: 240,
      pixelHeight: 180,
      referenceConfig: const ReferenceImageConfig(
        x: 20,
        y: 30,
        width: 200,
        height: 160,
        visible: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Scaffold(
            body: Stack(
              children: [ReferenceWindowView(initialPayload: payload)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReferenceWindowView)),
    );
    final pane = find.byKey(const ValueKey('drawing-reference-window'));
    final header = find.byKey(
      const ValueKey('drawing-reference-window-drag-handle'),
    );
    expect(tester.getSize(header).height, AppControlSize.minimumHitTarget);
    final closeButton = find.byTooltip('Close reference window');
    final closeButtonRect = tester.getRect(closeButton);
    expect(
      closeButtonRect.width,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );
    expect(
      closeButtonRect.height,
      greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
    );

    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(header).label,
      contains('Reference window. Use arrow keys to move.'),
    );
    final focusNode = Focus.of(tester.element(header));
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(pane), const Offset(30, 30));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(pane), const Offset(30, 40));

    await tester.drag(header, const Offset(500, 500));
    await tester.pumpAndSettle();
    final bounds = tester.getRect(pane);
    expect(bounds.left, 160);
    expect(bounds.top, 140);
    expect(bounds.right, lessThanOrEqualTo(360));
    expect(bounds.bottom, lessThanOrEqualTo(300));

    final updated = container
        .read(drawingStudioProviderFamily(payload))
        .payload;
    expect(updated.referenceConfig.x, 160);
    expect(updated.referenceConfig.y, 140);
    expect(updated.referenceConfig.width, payload.referenceConfig.width);
    expect(updated.referenceConfig.height, payload.referenceConfig.height);
    expect(updated.pixelWidth, payload.pixelWidth);
    expect(updated.layers, payload.layers);

    final closeRect = tester.getRect(closeButton);
    await tester.tapAt(Offset(closeRect.right - 2, closeRect.bottom - 2));
    await tester.pumpAndSettle();
    expect(
      container
          .read(drawingStudioProviderFamily(payload))
          .payload
          .referenceConfig
          .visible,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
