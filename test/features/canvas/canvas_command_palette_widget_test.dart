import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/canvas/domain/command_palette.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_command_palette.dart';

void main() {
  testWidgets('command palette filters and invokes selected command', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasCommandPalette(
            commands: const [
              CanvasCommandDescriptor(
                id: 'canvas.search',
                title: 'Search canvas',
                description: 'Find content',
                category: CanvasCommandCategory.navigation,
              ),
              CanvasCommandDescriptor(
                id: 'history.undo',
                title: 'Undo',
                description: 'Undo a change',
                category: CanvasCommandCategory.history,
              ),
            ],
            onSelected: (id) => selected = id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search canvas'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'undo');
    await tester.pump();
    expect(find.text('Search canvas'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(selected, 'history.undo');
  });

  testWidgets('command palette stays within a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasCommandPalette(
            commands: const [
              CanvasCommandDescriptor(
                id: 'canvas.search',
                title: 'Search canvas',
                description: 'Find content',
                category: CanvasCommandCategory.navigation,
              ),
              CanvasCommandDescriptor(
                id: 'history.undo',
                title: 'Undo',
                description: 'Undo a change',
                category: CanvasCommandCategory.history,
              ),
            ],
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialog = tester.getRect(find.byType(Dialog));
    expect(dialog.left, greaterThanOrEqualTo(0));
    expect(dialog.right, lessThanOrEqualTo(320));
    expect(dialog.top, greaterThanOrEqualTo(0));
    expect(dialog.bottom, lessThanOrEqualTo(480));
    expect(
      tester.getRect(find.text('COMMAND PALETTE')).bottom,
      lessThanOrEqualTo(480),
    );
    expect(
      tester
          .getRect(find.text('↑ ↓ Navigate   Enter Select   Esc Close'))
          .bottom,
      lessThanOrEqualTo(480),
    );
    expect(tester.takeException(), isNull);
  });
}
