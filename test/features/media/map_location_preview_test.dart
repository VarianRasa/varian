import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/media/map_location_preview.dart';

void main() {
  testWidgets('map preview uses the standard control clipping radius', (
    tester,
  ) async {
    ClipRRect? preview;
    final payload = MapPayload(
      locationTitle: 'Fixture location',
      address: 'Fixture address',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            preview =
                MapLocationPreview(payload: payload).build(context)
                    as ClipRRect;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(preview, isNotNull);
    expect(preview!.borderRadius, BorderRadius.circular(AppRadius.control));
    final labelPositioned = (preview!.child as Stack).children[1] as Positioned;
    final labelBox = labelPositioned.child as DecoratedBox;
    final labelPadding = labelBox.child as Padding;
    expect(
      labelPadding.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs + AppSpacing.xxs / 2,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
