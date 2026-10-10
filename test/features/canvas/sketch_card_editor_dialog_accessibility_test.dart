import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/sketch_card_editor_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets(
    'stroke swatches expose named selection and activate with Space and Enter',
    (tester) async {
      tester.view.physicalSize = const Size(800, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final node = CanvasNode(
        id: 'sketch',
        type: NodeType.sketchCard,
        x: 0,
        y: 0,
        width: 240,
        height: 160,
        payload: SketchCardPayload(),
      );
      SketchCardPayload? saved;
      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showUiDialog<void>(
                    context: context,
                    builder: (_) => SketchCardEditorDialog(
                      node: node,
                      onSave: (payload) => saved = payload,
                    ),
                  ),
                  child: const Text('Open sketch editor'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open sketch editor'));
      await tester.pumpAndSettle();
      final header = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('sketch-card-editor-header')),
      );
      final headerBorder =
          (header.decoration as BoxDecoration).border! as Border;
      expect(headerBorder.bottom.width, AppBorder.thin);
      expect(headerBorder.bottom.color, AppTokens.dark.panelBorder);
      final controls = tester
          .widgetList<ListView>(
            find.descendant(
              of: find.byType(SketchCardEditorDialog),
              matching: find.byType(ListView),
            ),
          )
          .single;
      final controlChildren =
          (controls.childrenDelegate as SliverChildListDelegate).children;
      final patternIndex = controlChildren.indexWhere(
        (child) => child is UiSelect<String> && child.label == 'Pattern',
      );
      expect(patternIndex, greaterThan(0));
      expect(
        (controlChildren[patternIndex - 1] as SizedBox).height,
        AppSpacing.sm + AppSpacing.xs + AppSpacing.xxs,
      );
      expect(
        (controlChildren[patternIndex + 1] as SizedBox).height,
        AppSpacing.sm,
      );

      final semantics = tester.ensureSemantics();
      final amber = find.bySemanticsLabel('Stroke color Amber');
      final blue = find.bySemanticsLabel('Stroke color Blue');
      expect(
        tester.getSemantics(amber).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      expect(
        tester.getSemantics(blue).flagsCollection.isSelected,
        ui.Tristate.isFalse,
      );
      final blueTarget = find.byKey(
        const ValueKey('sketch-card-stroke-color-Blue'),
      );
      await tester.ensureVisible(blueTarget);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(blueTarget),
        const Size(
          AppControlSize.minimumHitTarget,
          AppControlSize.minimumHitTarget,
        ),
      );
      final blueRect = tester.getRect(blueTarget);
      await tester.tapAt(blueRect.bottomRight - const Offset(2, 2));
      await tester.pump();
      expect(
        tester.getSemantics(blue).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );

      final redTarget = find.byKey(
        const ValueKey('sketch-card-stroke-color-Red'),
      );
      await tester.ensureVisible(redTarget);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Stroke color Amber'));
      await tester.pump();
      expect(
        tester.getSemantics(amber).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      Focus.of(tester.element(blueTarget)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(
        tester.getSemantics(blue).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      expect(
        tester.getSemantics(amber).flagsCollection.isSelected,
        ui.Tristate.isFalse,
      );
      final selectedBlueSwatch = find.descendant(
        of: blueTarget,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              (widget.decoration as BoxDecoration).border != null,
        ),
      );
      expect(
        ((tester.widget<DecoratedBox>(selectedBlueSwatch).decoration)
                as BoxDecoration)
            .border!
            .top
            .width,
        AppBorder.focus,
      );
      expect(
        tester.getSemantics(blue).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );

      final amberTarget = find.byKey(
        const ValueKey('sketch-card-stroke-color-Amber'),
      );
      Focus.of(tester.element(amberTarget)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        tester.getSemantics(amber).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(saved?.strokeColor, const Color(0xFFF59E0B));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
