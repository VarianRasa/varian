import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/canvas/domain/command_palette.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_command_palette.dart';

void main() {
  testWidgets('keyboard highlight is selected and Enter invokes its command', (
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

    final semantics = tester.ensureSemantics();
    final search = find.bySemanticsLabel('Search canvas');
    final undo = find.bySemanticsLabel('Undo');
    expect(
      tester.getSemantics(search).flagsCollection.isSelected,
      ui.Tristate.isTrue,
    );
    expect(
      tester.getSemantics(undo).flagsCollection.isSelected,
      ui.Tristate.isFalse,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      tester.getSemantics(search).flagsCollection.isSelected,
      ui.Tristate.isFalse,
    );
    expect(
      tester.getSemantics(undo).flagsCollection.isSelected,
      ui.Tristate.isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'history.undo');
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
