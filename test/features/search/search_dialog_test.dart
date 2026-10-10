import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/search/presentation/search_dialog.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import '../../test_app.dart';

void main() {
  testWidgets('selecting a canvas result calls back in a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final selected = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentNodesProvider.overrideWith(
            (ref) => DocumentNodesNotifier(
              ref,
              initialNodes: [
                CanvasNode(
                  id: 'sticky-1',
                  type: NodeType.stickyNote,
                  x: 0,
                  y: 0,
                  width: 120,
                  height: 80,
                  payload: StickyNotePayload(text: 'Needle note'),
                ),
              ],
            ),
          ),
        ],
        child: testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) => SearchDialog(
                  onSelectNode: (nodeId) => selected.add(nodeId),
                ),
              ),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Search canvas objects and projects'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(Dialog).last).height,
      lessThanOrEqualTo(420),
    );
    final dialogRect = tester.getRect(find.byType(Dialog).last);
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(360));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(420));
    for (final action in [
      find.byType(TextFormField),
      find.byTooltip('Close search'),
    ]) {
      final rect = tester.getRect(action);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(420));
    }

    await tester.enterText(find.byType(TextFormField), 'Needle');
    await tester.pumpAndSettle();
    final result = find.text('Needle note');
    expect(result, findsOneWidget);
    await tester.ensureVisible(result);
    await tester.tap(result);
    await tester.pumpAndSettle();

    expect(selected, ['sticky-1']);
    expect(find.byType(SearchDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search dialog sizes around keyboard insets', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (dialogContext) => MediaQuery(
                  data: MediaQuery.of(
                    dialogContext,
                  ).copyWith(viewInsets: const EdgeInsets.only(bottom: 280)),
                  child: const SearchDialog(),
                ),
              ),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open search'));
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
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    for (final control in [
      find.byType(TextFormField),
      find.byTooltip('Close search'),
    ]) {
      final rect = tester.getRect(control);
      expect(rect.left, greaterThanOrEqualTo(dialog.left));
      expect(rect.right, lessThanOrEqualTo(dialog.right));
      expect(rect.top, greaterThanOrEqualTo(dialog.top));
      expect(rect.bottom, lessThanOrEqualTo(keyboardTop));
    }
    expect(tester.takeException(), isNull);
  });
}
