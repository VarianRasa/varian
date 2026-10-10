import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/column_card_editor_modal.dart';

import '../../test_app.dart';

void main() {
  testWidgets('compact batch add scrolls and saves non-empty card titles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final node = CanvasNode(
      id: 'column',
      type: NodeType.columnContainer,
      x: 0,
      y: 0,
      width: 280,
      height: 420,
      payload: ColumnPayload(cards: const []),
    );
    CanvasNode? updated;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => ColumnCardEditorModal.show(
                context,
                node: node,
                onUpdate: (value) => updated = value,
              ),
              child: const Text('Edit column'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit column'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Batch Add'));
    await tester.pumpAndSettle();
    expect(find.text('Batch Add Cards'), findsOneWidget);
    expect(find.text('Add All Cards'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byType(UiTextField).last,
      'First card\n  \nSecond card  ',
    );
    await tester.tap(find.text('Add All Cards'));
    await tester.pumpAndSettle();

    final updatedPayload = updated!.payload as ColumnPayload;
    expect(updatedPayload.cards.map((card) => card.title), [
      'First card',
      'Second card',
    ]);
    expect(find.text('Batch Add Cards'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'card accent options keep 44px targets and save the selected color',
    (tester) async {
      final node = CanvasNode(
        id: 'column-with-card',
        type: NodeType.columnContainer,
        x: 0,
        y: 0,
        width: 280,
        height: 420,
        payload: ColumnPayload(
          cards: const [ColumnCardItem(id: 'card', title: 'Design card')],
        ),
      );
      CanvasNode? updated;

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => UiButton(
                onPressed: () => ColumnCardEditorModal.show(
                  context,
                  node: node,
                  onUpdate: (value) => updated = value,
                ),
                child: const Text('Edit card accents'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit card accents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Design card'));
      await tester.pumpAndSettle();

      final blue = find.bySemanticsLabel('Card accent color: Blue');
      expect(
        tester.getSize(blue),
        const Size(
          AppControlSize.minimumHitTarget,
          AppControlSize.minimumHitTarget,
        ),
      );
      await tester.tap(blue);
      await tester.pumpAndSettle();
      final selectedSwatch = tester.widget<Container>(
        find.descendant(
          of: blue,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).border != null,
          ),
        ),
      );
      final selectedBorder = selectedSwatch.decoration! as BoxDecoration;
      expect(selectedBorder.border!.top.width, AppBorder.focus);
      await tester.tap(find.text('Save Card'));
      await tester.pumpAndSettle();

      final savedCard = (updated!.payload as ColumnPayload).cards.single;
      expect(savedCard.title, 'Design card');
      expect(savedCard.cardColor, const Color(0xFF3B82F6));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('card surface and metadata wrap keep tokenized geometry', (
    tester,
  ) async {
    final card = const ColumnCardItem(
      id: 'measured-card',
      title: 'Local card title',
      description: 'Fixture description',
      tags: ['local-tag'],
      dueDate: 'Today',
      assignee: 'Local user',
    );
    final node = CanvasNode(
      id: 'column-with-measured-card',
      type: NodeType.columnContainer,
      x: 0,
      y: 0,
      width: 280,
      height: 420,
      payload: ColumnPayload(cards: [card]),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => ColumnCardEditorModal.show(
                context,
                node: node,
                onUpdate: (_) {},
              ),
              child: const Text('Measure card chrome'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Measure card chrome'));
    await tester.pumpAndSettle();

    final cardFinder = find.byKey(const ValueKey('measured-card'));
    final cardSurface = tester.widget<Container>(cardFinder);
    final metadataWrap = tester.widget<Wrap>(
      find.descendant(of: cardFinder, matching: find.byType(Wrap)),
    );
    expect(
      cardSurface.padding,
      const EdgeInsets.all(AppSpacing.sm + AppSpacing.xxs),
    );
    expect(
      (cardSurface.decoration! as BoxDecoration).border!.top.width,
      AppBorder.thin,
    );
    expect(metadataWrap.spacing, AppSpacing.sm);
    expect(metadataWrap.runSpacing, AppSpacing.xs);
    expect(find.text(card.title), findsOneWidget);
    expect(find.text(card.description), findsOneWidget);
    expect(find.text('local-tag'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Local user'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
