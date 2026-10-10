import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/domain/canvas_precision.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_precision_dialog.dart';
import 'package:varian/features/canvas/state/canvas_precision_provider.dart';

import '../../test_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('precision settings fit compact viewport and update toggles', (
    tester,
  ) async {
    const projectId = 'precision-dialog-compact-fixture';
    tester.view.physicalSize = const Size(390, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(canvasPrecisionProvider(projectId).notifier).ready;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          Builder(
            builder: (context) => Scaffold(
              body: UiButton(
                onPressed: () => showUiDialog<void>(
                  context: context,
                  builder: (_) => CanvasPrecisionDialog(projectId: projectId),
                ),
                child: const Text('Open precision settings'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open precision settings'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    final dialogBounds = tester.getRect(find.byType(Dialog));
    expect(dialogBounds.left, greaterThanOrEqualTo(0));
    expect(dialogBounds.top, greaterThanOrEqualTo(0));
    expect(dialogBounds.right, lessThanOrEqualTo(390));
    expect(dialogBounds.bottom, lessThanOrEqualTo(480));
    for (final action in [
      find.byTooltip('Close precision settings'),
      find.text('Done'),
    ]) {
      final bounds = tester.getRect(action);
      expect(bounds.left, greaterThanOrEqualTo(dialogBounds.left));
      expect(bounds.right, lessThanOrEqualTo(dialogBounds.right));
      expect(bounds.top, greaterThanOrEqualTo(dialogBounds.top));
      expect(bounds.bottom, lessThanOrEqualTo(dialogBounds.bottom));
    }
    expect(dialog.constraints!.maxWidth, 390 - AppSpacing.md * 2);
    expect(find.text('Show grid'), findsOneWidget);
    expect(find.text('Show rulers'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Show rulers'));
    await tester.pumpAndSettle();
    expect(
      container.read(canvasPrecisionProvider(projectId)).rulersVisible,
      isTrue,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('guide editor retains its field while saving local guide data', (
    tester,
  ) async {
    const projectId = 'precision-guide-editor-fixture';
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(canvasPrecisionProvider(projectId).notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          Builder(
            builder: (context) => Scaffold(
              body: UiButton(
                onPressed: () => showUiDialog<void>(
                  context: context,
                  builder: (_) => CanvasPrecisionDialog(projectId: projectId),
                ),
                child: const Text('Open precision settings'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open precision settings'));
    await tester.pumpAndSettle();
    final addGuide = find.text('Add guide').first;
    await tester.ensureVisible(addGuide);
    await tester.tap(addGuide);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '48.5');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();

    final guides = container.read(canvasPrecisionProvider(projectId)).guides;
    expect(guides, hasLength(1));
    expect(guides.single.axis, CanvasGuideAxis.vertical);
    expect(guides.single.position, 48.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('precision settings use the shared wide dialog width', (
    tester,
  ) async {
    const projectId = 'precision-dialog-wide-fixture';
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => Scaffold(
              body: UiButton(
                onPressed: () => showUiDialog<void>(
                  context: context,
                  builder: (_) => CanvasPrecisionDialog(projectId: projectId),
                ),
                child: const Text('Open precision settings'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open precision settings'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<UiDialog>(find.byType(UiDialog)).constraints!.maxWidth,
      560,
    );
    expect(find.text('Precision settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
