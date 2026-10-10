import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/component_editor_modal.dart';

import '../../test_app.dart';

void main() {
  testWidgets('adds a component property and saves it to the node', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final node = CanvasNode(
      id: 'component-master',
      type: NodeType.component,
      x: 0,
      y: 0,
      width: 240,
      height: 120,
      payload: ComponentPayload(
        masterComponentId: 'component-master',
        componentName: 'Action',
        isMaster: true,
      ),
    );
    CanvasNode? updated;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => ComponentEditorModal.show(
                context,
                node: node,
                onUpdate: (value) => updated = value,
              ),
              child: const Text('Edit component'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit component'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Prop'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Add component property'), findsOneWidget);

    final propertyName = find.byWidgetPredicate(
      (widget) => widget is UiTextField && widget.label == 'Property Name',
    );
    await tester.enterText(propertyName, 'label');
    await tester.tap(find.text('Add Property'));
    await tester.pumpAndSettle();

    final updatedPayload = updated!.payload as ComponentPayload;
    expect(updatedPayload.properties, hasLength(1));
    expect(updatedPayload.properties.single.name, 'label');
    expect(updatedPayload.propertyValues.values, contains('Button Label'));
  });

  testWidgets(
    'compact component dialogs add variants, slots, and shape layers',
    (tester) async {
      tester.view.physicalSize = const Size(390, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final node = CanvasNode(
        id: 'compact-component',
        type: NodeType.component,
        x: 0,
        y: 0,
        width: 240,
        height: 120,
        payload: ComponentPayload(
          masterComponentId: 'compact-component',
          componentName: 'Compact action',
          isMaster: true,
        ),
      );
      CanvasNode? updated;

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => UiButton(
                onPressed: () => ComponentEditorModal.show(
                  context,
                  node: node,
                  onUpdate: (value) => updated = value,
                ),
                child: const Text('Edit compact component'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit compact component'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dialogBounds = tester.getRect(find.byType(Dialog).last);
      expect(dialogBounds.left, greaterThanOrEqualTo(0));
      expect(dialogBounds.top, greaterThanOrEqualTo(0));
      expect(dialogBounds.right, lessThanOrEqualTo(390));
      expect(dialogBounds.bottom, lessThanOrEqualTo(480));

      await tester.drag(find.byType(ListView).first, const Offset(0, -350));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('New Variant'));
      await tester.tap(find.text('New Variant'));
      await tester.pumpAndSettle();
      expect(find.text('Add Component Variant'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) => widget is UiTextField && widget.label == 'Variant Name',
        ),
        'Compact',
      );
      await tester.tap(find.text('Add Variant'));
      await tester.pumpAndSettle();
      expect(
        (updated!.payload as ComponentPayload).variants.single.name,
        'Compact',
      );

      await tester.ensureVisible(find.text('New Slot'));
      await tester.tap(find.text('New Slot'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) => widget is UiTextField && widget.label == 'Slot Name',
        ),
        'Label',
      );
      await tester.tap(find.text('Add Slot'));
      await tester.pumpAndSettle();
      expect((updated!.payload as ComponentPayload).slots.single.name, 'Label');

      await tester.ensureVisible(find.text('Layers / Shapes'));
      await tester.tap(find.text('Layers / Shapes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Shape Layer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rectangle (R)'));
      await tester.pumpAndSettle();
      final layerId =
          (updated!.payload as ComponentPayload).templateChildren.single.id;
      await tester.ensureVisible(find.byKey(ValueKey(layerId)));
      await tester.pumpAndSettle();
      final layerRow = tester.widget<Container>(find.byKey(ValueKey(layerId)));
      final layerBorder =
          (layerRow.decoration! as BoxDecoration).border! as Border;
      expect(layerBorder.left.width, AppBorder.thin);
      expect(layerBorder.top.width, AppBorder.thin);
      expect(layerBorder.right.width, AppBorder.thin);
      expect(layerBorder.bottom.width, AppBorder.thin);
      expect(
        (updated!.payload as ComponentPayload).templateChildren.single.type,
        NodeType.rectangle,
      );
      expect(
        (updated!.payload as ComponentPayload).templateChildren,
        hasLength(1),
      );
      expect(find.text('Add Shape Layer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
