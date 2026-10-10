import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/media/image_crop_screen.dart';

import '../../test_app.dart';

void main() {
  testWidgets('image crop screen renders shared page chrome around local image', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final imageData = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/pWQAAAAASUVORK5CYII=',
      ),
    );

    await tester.pumpWidget(
      testApp(ImageCropScreen(imageData: imageData, onCropped: (_) {})),
    );
    await tester.pump();

    expect(find.text('CROP IMAGE'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('CROP'), findsOneWidget);
    expect(find.byType(UiPageScaffold), findsOneWidget);
    final cropAction = tester.getRect(find.text('CROP'));
    expect(cropAction.left, greaterThanOrEqualTo(0));
    expect(cropAction.right, lessThanOrEqualTo(320));
    expect(cropAction.top, greaterThanOrEqualTo(0));
    expect(cropAction.bottom, lessThanOrEqualTo(480));
    final back = tester.getRect(find.byTooltip('Back'));
    expect(back.left, greaterThanOrEqualTo(0));
    expect(back.top, greaterThanOrEqualTo(0));
    expect(back.bottom, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
  });
}
