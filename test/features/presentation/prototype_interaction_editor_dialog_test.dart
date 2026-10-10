import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/prototype_interaction.dart';
import 'package:varian/features/presentation/prototype_interaction_editor_dialog.dart';
import '../../test_app.dart';

void main() {
  testWidgets('prototype editor section dividers use thin border', (
    tester,
  ) async {
    final nodes = [
      CanvasNode(
        id: 'button',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 120,
        height: 48,
        payload: ShapePayload(),
      ),
      CanvasNode(
        id: 'target',
        type: NodeType.frame,
        x: 200,
        y: 0,
        width: 320,
        height: 240,
        payload: FramePayload(name: 'Target'),
      ),
    ];

    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => Scaffold(
              body: UiButton(
                key: const ValueKey('open-prototype-editor'),
                onPressed: () {
                  PrototypeInteractionEditorDialog.show(
                    context,
                    sourceNodeId: 'button',
                    sourceNodeLabel: 'Button',
                    initialInteractions: const [
                      PrototypeInteraction(
                        id: 'navigate-target',
                        targetFrameId: 'target',
                      ),
                      PrototypeInteraction(
                        id: 'go-back',
                        action: PrototypeAction.back,
                      ),
                    ],
                    initialStateId: null,
                    nodes: nodes,
                  );
                },
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-prototype-editor')));
    await tester.pumpAndSettle();
    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 296);
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final saveButton = find.text('Save prototype');
    await tester.ensureVisible(saveButton);
    final saveRect = tester.getRect(saveButton);
    expect(saveRect.left, greaterThanOrEqualTo(dialogRect.left));
    expect(saveRect.right, lessThanOrEqualTo(dialogRect.right));
    expect(saveRect.bottom, lessThanOrEqualTo(dialogRect.bottom));
    final interactionTiles = tester.widgetList<ListTile>(find.byType(ListTile));
    expect(interactionTiles, hasLength(2));
    expect(interactionTiles.map((tile) => tile.selected), [true, false]);
    await tester.tap(find.text('go-back'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => tile.selected),
      [false, true],
    );

    final dividers = tester.widgetList<Divider>(find.byType(Divider));
    expect(dividers, hasLength(2));
    expect(
      dividers.every((divider) => divider.height == AppBorder.thin),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
