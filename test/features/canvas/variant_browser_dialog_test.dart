import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/dialogs/variant_browser_dialog.dart';

import '../../test_app.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required CanvasNode anchorNode,
    required List<CanvasNode> nodes,
    ValueChanged<String>? onSelectNode,
  }) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testApp(
        VariantBrowserDialog(
          anchorNode: anchorNode,
          nodes: nodes,
          onSelectNode: onSelectNode ?? (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the direct source lineage and excludes unrelated images', (
    tester,
  ) async {
    final source = _image('source', name: 'Original Source');
    final selectedVariant = _image(
      'selected-variant',
      name: 'Selected Variant',
      variantOfNodeId: source.id,
    );
    final siblingVariant = _image(
      'sibling-variant',
      name: 'Sibling Variant',
      variantOfNodeId: source.id,
    );
    final unrelated = _image('unrelated', name: 'Unrelated Image');

    await pumpDialog(
      tester,
      anchorNode: selectedVariant,
      nodes: [unrelated, siblingVariant, source, selectedVariant],
    );

    final thumbnail = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          (widget.decoration as BoxDecoration?)?.color ==
              AppTokens.dark.canvas &&
          (widget.decoration as BoxDecoration?)?.borderRadius ==
              BorderRadius.circular(AppRadius.control),
    );
    expect(thumbnail, findsNWidgets(3));
    for (final frame in tester.widgetList<Container>(thumbnail)) {
      final border = (frame.decoration! as BoxDecoration).border! as Border;
      expect(border.top.width, AppBorder.thin);
    }
    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey('variant-row-surface-sibling-variant')),
          )
          .borderRadius,
      const BorderRadius.all(Radius.circular(AppRadius.control)),
    );
    expect(find.text('Selected Variant'), findsOneWidget);
    expect(find.text('Sibling Variant'), findsOneWidget);
    expect(find.text('Unrelated Image'), findsNothing);
    expect(find.text('Image'), findsNWidgets(3));
  });

  testWidgets('allows exactly two images for side-by-side compare', (
    tester,
  ) async {
    final source = _image('source', name: 'Original Source');
    final firstVariant = _image(
      'first-variant',
      name: 'First Variant',
      variantOfNodeId: source.id,
    );
    final secondVariant = _image(
      'second-variant',
      name: 'Second Variant',
      variantOfNodeId: source.id,
    );
    final thirdVariant = _image(
      'third-variant',
      name: 'Third Variant',
      variantOfNodeId: source.id,
    );
    var selectedNodeId = <String>[];

    await pumpDialog(
      tester,
      anchorNode: source,
      nodes: [source, firstVariant, secondVariant, thirdVariant],
      onSelectNode: selectedNodeId.add,
    );

    final firstCheckbox = find.byKey(
      const ValueKey('compare-checkbox-first-variant'),
    );
    await tester.ensureVisible(firstCheckbox);
    await tester.tap(firstCheckbox);
    await tester.pumpAndSettle();

    final secondCheckbox = find.byKey(
      const ValueKey('compare-checkbox-second-variant'),
    );
    await tester.ensureVisible(secondCheckbox);
    await tester.tap(secondCheckbox);
    await tester.pumpAndSettle();

    final thirdCheckbox = find.byKey(
      const ValueKey('compare-checkbox-third-variant'),
    );
    tester.widget<UiCheckbox>(thirdCheckbox).onChange?.call(true);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<UiCheckbox>(
            find.byKey(const ValueKey('compare-checkbox-first-variant')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<UiCheckbox>(
            find.byKey(const ValueKey('compare-checkbox-second-variant')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<UiCheckbox>(
            find.byKey(const ValueKey('compare-checkbox-third-variant')),
          )
          .value,
      isFalse,
    );
    expect(find.text('SIDE-BY-SIDE COMPARE'), findsOneWidget);
    expect(
      (tester
                  .widget<Container>(
                    find.byKey(const ValueKey('variant-compare-panel')),
                  )
                  .decoration
              as BoxDecoration)
          .borderRadius,
      BorderRadius.circular(AppRadius.panel),
    );
    final comparePanel = tester.widget<Container>(
      find.byKey(const ValueKey('variant-compare-panel')),
    );
    final comparePanelBorder =
        (comparePanel.decoration! as BoxDecoration).border! as Border;
    expect(comparePanelBorder.top.width, AppBorder.thin);
    expect(find.text('2 of 2 images selected'), findsOneWidget);
    expect(selectedNodeId, isEmpty);
  });

  testWidgets('calls onSelectNode only from the explicit select action', (
    tester,
  ) async {
    final source = _image('source', name: 'Original Source');
    final variant = _image(
      'variant',
      name: 'Chosen Variant',
      variantOfNodeId: source.id,
    );
    final selectedNodeIds = <String>[];

    await pumpDialog(
      tester,
      anchorNode: source,
      nodes: [source, variant],
      onSelectNode: selectedNodeIds.add,
    );

    final variantRow = find.byKey(const ValueKey('variant-row-variant'));
    await tester.ensureVisible(variantRow);
    await tester.tap(variantRow);
    await tester.pumpAndSettle();
    expect(selectedNodeIds, isEmpty);

    final selectAction = find.byKey(const ValueKey('variant-select-action'));
    await tester.ensureVisible(selectAction);
    await tester.tap(selectAction);
    await tester.pumpAndSettle();

    expect(selectedNodeIds, <String>['variant']);
  });
}

CanvasNode _image(String id, {required String name, String? variantOfNodeId}) =>
    CanvasNode(
      id: id,
      type: NodeType.image,
      x: 0,
      y: 0,
      width: 320,
      height: 200,
      name: name,
      variantOfNodeId: variantOfNodeId,
      payload: ImagePayload(caption: name),
    );
