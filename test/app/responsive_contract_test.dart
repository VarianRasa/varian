import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/responsive.dart';

void main() {
  testWidgets('uses the contract window classes at desktop widths', (
    tester,
  ) async {
    Future<AppWindowClass> classAt(double width) async {
      AppWindowClass? value;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(
            builder: (context) {
              value = AppResponsive.windowClass(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return value!;
    }

    expect(await classAt(320), AppWindowClass.compact);
    expect(await classAt(600), AppWindowClass.medium);
    expect(await classAt(840), AppWindowClass.expanded);
    expect(await classAt(1179), AppWindowClass.expanded);
    expect(await classAt(1180), AppWindowClass.wide);
  });

  testWidgets('does not infer desktop input modality from width', (
    tester,
  ) async {
    bool? touch;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(320, 800)),
        child: Builder(
          builder: (context) {
            touch = AppResponsive.usesTouchLayout(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(touch, isTrue);
  });
}
