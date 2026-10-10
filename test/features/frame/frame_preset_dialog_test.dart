import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/presentation/dialogs/frame_preset_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets('frame preset cards render without unbounded flex errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(child: testApp(const _DialogLauncher())),
    );
    await tester.tap(find.text('Open frame presets'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('FRAME DEVICE & ARTBOARD PRESETS'), findsOneWidget);
    expect(find.text('iPhone 16 / 15 Pro'), findsOneWidget);
  });
  testWidgets('preset labels inherit Material text roles', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(child: testApp(const _DialogLauncher())),
    );
    await tester.tap(find.text('Open frame presets'));
    await tester.pumpAndSettle();

    final name = find.text('iPhone 16 / 15 Pro');
    final dimensions = find.text('393 × 852 px');
    final theme = Theme.of(tester.element(name));
    final tokens = theme.extension<AppTokens>()!;
    expect(
      tester.widget<Text>(name).style,
      theme.textTheme.bodyMedium!.copyWith(
        color: tokens.text,
        fontWeight: FontWeight.w600,
      ),
    );
    expect(
      tester.widget<Text>(dimensions).style,
      theme.textTheme.labelSmall!.copyWith(
        color: tokens.accent,
        fontWeight: FontWeight.bold,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

class _DialogLauncher extends StatelessWidget {
  const _DialogLauncher();

  @override
  Widget build(BuildContext context) => UiButton(
    onPressed: () => showUiDialog<void>(
      context: context,
      builder: (_) => FramePresetDialog(onSelectPreset: (_, _) {}),
    ),
    child: const Text('Open frame presets'),
  );
}
