import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/export/data/export_file_saver.dart';
import 'package:varian/features/inspect/domain/inspect_handoff.dart';
import 'package:varian/features/inspect/presentation/inspect_handoff_dialog.dart';

import '../../test_app.dart';

void main() {
  final document = CanvasDocument(
    projectId: 'project-a',
    schemaVersion: 3,
    updatedAt: DateTime.utc(2026, 9, 13),
    nodes: [
      CanvasNode(
        id: 'title',
        type: NodeType.text,
        x: 12,
        y: 18,
        width: 160,
        height: 32,
        payload: TextPayload(text: 'Inspect me'),
      ),
    ],
  );

  testWidgets('shows inspect data and changes handoff format', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(dialog: InspectHandoffDialog(document: document)),
        ),
      ),
    );

    await tester.tap(find.text('Open inspect'));
    await tester.pumpAndSettle();

    expect(find.text('INSPECT & HANDOFF'), findsOneWidget);
    expect(find.textContaining('1 visible node'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inspect-handoff-content')),
      findsOneWidget,
    );
    expect(find.textContaining('documentSchemaVersion'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('inspect-handoff-format')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CSS · .css').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('documentSchemaVersion: 3'), findsOneWidget);
    expect(find.text('Save CSS'), findsOneWidget);
  });

  testWidgets('reflows and scrolls controls on a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    InspectHandoffFormat? savedFormat;
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(
            dialog: InspectHandoffDialog(
              document: document,
              onExport: (format, _) async {
                savedFormat = format;
                return ExportSaveOutcome.saved;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open inspect'));
    await tester.pumpAndSettle();

    final viewport = const Rect.fromLTWH(0, 0, 320, 420);
    final dialog = tester.getRect(find.byType(Dialog).last);
    expect(dialog.left, greaterThanOrEqualTo(viewport.left));
    expect(dialog.right, lessThanOrEqualTo(viewport.right));
    expect(dialog.top, greaterThanOrEqualTo(viewport.top));
    expect(dialog.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(
      tester
          .getRect(find.byKey(const ValueKey('inspect-handoff-content')))
          .width,
      lessThanOrEqualTo(dialog.width),
    );
    expect(tester.takeException(), isNull);
    final previewFrame = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('inspect-handoff-content')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).border != null,
            ),
          )
          .first,
    );
    final previewBorder =
        (previewFrame.decoration as BoxDecoration).border! as Border;
    expect(previewBorder.top.width, AppBorder.thin);
    expect(tester.takeException(), isNull);
    final summaryBorders = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(Wrap).first,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).border != null,
            ),
          ),
        )
        .map((container) => (container.decoration! as BoxDecoration).border!)
        .cast<Border>()
        .toList();
    expect(summaryBorders, isNotEmpty);
    expect(
      summaryBorders.every((border) => border.top.width == AppBorder.thin),
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('inspect-handoff-content')),
      findsOneWidget,
    );
    final headerClose = find.byTooltip('Close inspect mode').first;
    final closeRect = tester.getRect(headerClose);
    expect(closeRect.left, greaterThanOrEqualTo(dialog.left));
    expect(closeRect.right, lessThanOrEqualTo(dialog.right));
    expect(closeRect.top, greaterThanOrEqualTo(dialog.top));
    expect(closeRect.bottom, lessThanOrEqualTo(dialog.bottom));
    final saveButton = find.bySemanticsLabel('Save handoff');
    await tester.scrollUntilVisible(
      saveButton,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(savedFormat, InspectHandoffFormat.json);
    expect(find.byType(InspectHandoffDialog), findsNothing);
  });
  testWidgets('wide inspect handoff controls remain aligned and save locally', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? savedContent;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(
            dialog: InspectHandoffDialog(
              document: document,
              onExport: (_, content) async {
                savedContent = content;
                return ExportSaveOutcome.saved;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open inspect'));
    await tester.pumpAndSettle();

    final dialog = tester.getRect(find.byType(Dialog).last);
    expect(dialog.left, greaterThanOrEqualTo(0));
    expect(dialog.right, lessThanOrEqualTo(1100));
    expect(dialog.top, greaterThanOrEqualTo(0));
    expect(dialog.bottom, lessThanOrEqualTo(800));
    final format = tester.getRect(
      find.byKey(const ValueKey('inspect-handoff-format')),
    );
    final copy = tester.getRect(find.bySemanticsLabel('Copy handoff'));
    expect(format.right, lessThanOrEqualTo(copy.left));
    expect(format.center.dy, closeTo(copy.center.dy, 1));
    final close = tester.getRect(find.text('Close'));
    final save = tester.getRect(find.bySemanticsLabel('Save handoff'));
    expect(close.right, lessThanOrEqualTo(save.left));
    expect(close.center.dy, closeTo(save.center.dy, 1));
    for (final action in [format, copy, close, save]) {
      expect(action.left, greaterThanOrEqualTo(dialog.left));
      expect(action.right, lessThanOrEqualTo(dialog.right));
      expect(action.top, greaterThanOrEqualTo(dialog.top));
      expect(action.bottom, lessThanOrEqualTo(dialog.bottom));
    }
    final expectedContent = tester
        .widget<SelectableText>(
          find.byKey(const ValueKey('inspect-handoff-content')),
        )
        .data;
    await tester.tap(find.bySemanticsLabel('Save handoff'));
    await tester.pumpAndSettle();

    expect(savedContent, expectedContent);
    expect(find.byType(InspectHandoffDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delegates save and closes on success', (tester) async {
    InspectHandoffFormat? savedFormat;
    String? savedContent;
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(
            dialog: InspectHandoffDialog(
              document: document,
              onExport: (format, content) async {
                savedFormat = format;
                savedContent = content;
                return ExportSaveOutcome.saved;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open inspect'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.bySemanticsLabel('Save handoff'));
    await tester.tap(find.bySemanticsLabel('Save handoff'));
    await tester.pumpAndSettle();

    expect(savedFormat, InspectHandoffFormat.json);
    expect(savedContent, contains('documentSchemaVersion'));
    expect(find.byType(InspectHandoffDialog), findsNothing);
  });
  testWidgets('failed save feedback uses the Material body role', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(
            dialog: InspectHandoffDialog(
              document: document,
              onExport: (_, _) async => ExportSaveOutcome.failed,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open inspect'));
    await tester.pumpAndSettle();
    final saveButton = find.bySemanticsLabel('Save handoff');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final error = find.text('Handoff save failed. Please try again.');
    final theme = Theme.of(tester.element(error));
    final tokens = theme.extension<AppTokens>()!;
    expect(
      tester.widget<Text>(error).style,
      theme.textTheme.bodyMedium!.copyWith(color: tokens.danger),
    );
    expect(
      tester.getSemantics(error),
      matchesSemantics(
        label: 'Handoff save failed. Please try again.',
        isLiveRegion: true,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

class _DialogLauncher extends StatelessWidget {
  final Widget dialog;

  const _DialogLauncher({required this.dialog});

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: () =>
        showUiDialog<void>(context: context, builder: (_) => dialog),
    child: const Text('Open inspect'),
  );
}
