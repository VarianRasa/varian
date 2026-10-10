import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/annotation_pin_editor_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets(
    'marker colors are named, keyboard operable, and preserve pin data',
    (tester) async {
      tester.view.physicalSize = const Size(390, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final createdAt = DateTime.utc(2026, 9, 20, 12);
      final originalPin = ImageAnnotationPin(
        id: 'pin-1',
        position: const Offset(18, 24),
        text: 'Keep this note',
        author: 'Ari',
        createdAt: createdAt,
        status: AnnotationPinStatus.inProgress,
        isResolved: true,
      );
      ImageAnnotationPin? savedPin;

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showUiDialog<void>(
                  context: context,
                  builder: (_) => AnnotationPinEditorDialog(
                    pin: originalPin,
                    pinIndex: 0,
                    onSave: (pin) => savedPin = pin,
                    onDelete: () {},
                  ),
                ),
                child: const Text('Open pin'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open pin'));
      await tester.pumpAndSettle();

      final statusLabel = tester.getRect(find.text('Status'));
      final statusSelect = tester.getRect(
        find.byType(UiSelect<AnnotationPinStatus>),
      );
      expect(
        statusSelect.top - statusLabel.bottom,
        AppSpacing.xs + AppSpacing.xxs,
      );
      final header = tester.widget<Container>(
        find.byKey(const ValueKey('annotation-pin-editor-header')),
      );
      final headerBorder =
          (header.decoration! as BoxDecoration).border! as Border;
      final status = tester.widget<Container>(
        find.byKey(const ValueKey('annotation-pin-status-control')),
      );
      final statusBorder =
          (status.decoration! as BoxDecoration).border! as Border;
      final footer = tester.widget<Container>(
        find.byKey(const ValueKey('annotation-pin-editor-footer')),
      );
      final footerBorder =
          (footer.decoration! as BoxDecoration).border! as Border;
      expect(headerBorder.bottom.width, AppBorder.thin);
      expect(statusBorder.top.width, AppBorder.thin);
      expect(statusBorder.right.width, AppBorder.thin);
      expect(statusBorder.bottom.width, AppBorder.thin);
      expect(statusBorder.left.width, AppBorder.thin);
      expect(footerBorder.top.width, AppBorder.thin);
      final pink = find.bySemanticsLabel('Marker color Pink');
      final blue = find.bySemanticsLabel('Marker color Blue');
      expect(pink, findsOneWidget);
      expect(blue, findsOneWidget);

      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(pink).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      expect(
        tester.getSemantics(blue).flagsCollection.isSelected,
        ui.Tristate.isFalse,
      );

      final blueTarget = find.byKey(
        const ValueKey('annotation-pin-color-blue'),
      );
      Focus.of(tester.element(blueTarget)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        tester.getSize(blueTarget),
        const Size(AppControlSize.compact, AppControlSize.compact),
      );

      final selectedBlueDecoration = tester.widget<Container>(
        find.descendant(of: blueTarget, matching: find.byType(Container)),
      );
      expect(
        (selectedBlueDecoration.decoration! as BoxDecoration).border!.top.width,
        AppBorder.focus,
      );
      expect(
        tester.getSemantics(blue).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      final footerActions = tester.widget<Wrap>(
        find
            .ancestor(of: find.text('Cancel'), matching: find.byType(Wrap))
            .first,
      );
      expect(footerActions.spacing, AppSpacing.sm);
      expect(footerActions.runSpacing, AppSpacing.sm);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(savedPin, isNotNull);
      expect(savedPin!.color, const Color(0xFF3B82F6));
      expect(savedPin!.id, originalPin.id);
      expect(savedPin!.position, originalPin.position);
      expect(savedPin!.text, originalPin.text);
      expect(savedPin!.author, originalPin.author);
      expect(savedPin!.createdAt, createdAt);
      expect(savedPin!.status, originalPin.status);
      expect(savedPin!.isResolved, originalPin.isResolved);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
