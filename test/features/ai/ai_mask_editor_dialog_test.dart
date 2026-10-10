import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/ai/domain/ai_workflow_contract.dart';
import 'package:varian/features/ai/presentation/ai_workflow_dialogs.dart';
import '../../test_app.dart';

void main() {
  testWidgets('keyboard draws and commits a mask stroke in a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    AIMaskDocument? result;
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () async {
                result = await showUiDialog<AIMaskDocument>(
                  context: context,
                  builder: (_) => const AIMaskEditorDialog(
                    initialMask: AIMaskDocument(
                      width: 100,
                      height: 80,
                      operation: AIMaskOperation.inpaint,
                    ),
                  ),
                );
              },
              child: const Text('Edit mask'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit mask'));
    await tester.pumpAndSettle();

    final drawingArea = find.bySemanticsLabel('Mask drawing area');
    expect(drawingArea, findsOneWidget);
    expect(
      tester.getSize(find.byType(Dialog).last).height,
      lessThanOrEqualTo(420),
    );
    const viewport = Rect.fromLTWH(0, 0, 360, 420);
    final dialog = tester.getRect(find.byType(Dialog).last);
    expect(dialog.left, greaterThanOrEqualTo(viewport.left));
    expect(dialog.right, lessThanOrEqualTo(viewport.right));
    expect(dialog.top, greaterThanOrEqualTo(viewport.top));
    expect(dialog.bottom, lessThanOrEqualTo(viewport.bottom));
    final drawingRect = tester.getRect(drawingArea);
    expect(drawingRect.left, greaterThanOrEqualTo(dialog.left));
    expect(drawingRect.right, lessThanOrEqualTo(dialog.right));
    final paintButton = tester.getRect(
      find.bySemanticsLabel('Switch to erasing mask strokes'),
    );
    expect(paintButton.left, greaterThanOrEqualTo(dialog.left));
    expect(paintButton.right, lessThanOrEqualTo(dialog.right));
    expect(tester.takeException(), isNull);
    Focus.of(tester.element(drawingArea)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Use 1 strokes'),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    final useMask = tester.getRect(find.text('Use 1 strokes'));
    expect(useMask.left, greaterThanOrEqualTo(dialog.left));
    expect(useMask.right, lessThanOrEqualTo(dialog.right));
    expect(useMask.top, greaterThanOrEqualTo(dialog.top));
    expect(useMask.bottom, lessThanOrEqualTo(dialog.bottom));
    await tester.tap(find.text('Use 1 strokes'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.strokes, hasLength(1));
    expect(result!.strokes.single.points, hasLength(2));
    expect(result!.strokes.single.points.last.dx, greaterThan(0));
    expect(result!.strokes.single.points.last.dy, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
  testWidgets('mask editor keeps footer controls above a visible keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) => const AIMaskEditorDialog(
                  initialMask: AIMaskDocument(
                    width: 100,
                    height: 80,
                    operation: AIMaskOperation.inpaint,
                  ),
                ),
              ),
              child: const Text('Edit mask'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit mask'));
    await tester.pumpAndSettle();

    const keyboardTop = 420.0;
    final dialogSurface = find.descendant(
      of: find.byType(Dialog).last,
      matching: find.byWidgetPredicate(
        (widget) => widget is Material && widget.shape != null,
      ),
    );
    final dialog = tester.getRect(dialogSurface);
    expect(dialog.left, greaterThanOrEqualTo(0));
    expect(dialog.right, lessThanOrEqualTo(360));
    expect(dialog.top, greaterThanOrEqualTo(0));
    expect(dialog.bottom, lessThanOrEqualTo(keyboardTop));

    await tester.scrollUntilVisible(
      find.text('Cancel'),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    final cancel = tester.getRect(find.text('Cancel'));
    expect(cancel.left, greaterThanOrEqualTo(dialog.left));
    expect(cancel.right, lessThanOrEqualTo(dialog.right));
    expect(cancel.top, greaterThanOrEqualTo(dialog.top));
    expect(cancel.bottom, lessThanOrEqualTo(keyboardTop));
    expect(tester.takeException(), isNull);
  });
}
