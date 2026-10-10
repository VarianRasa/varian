import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/mermaid/domain/mermaid_renderer.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/features/mermaid/presentation/mermaid_editor_dialog.dart';

import '../../test_app.dart';

class _EditorRenderer implements MermaidRenderer {
  @override
  String? get rendererVersion => null;

  final List<MermaidRenderConfig> renderConfigs = [];

  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async {
    if (source.contains('bad')) {
      return const MermaidValidationResult.invalid(
        MermaidDiagnostic(
          code: 'MERMAID_PARSE_ERROR',
          message: 'Unexpected token.',
          line: 2,
          column: 4,
        ),
      );
    }
    return const MermaidValidationResult.valid(diagramType: 'flowchart');
  }

  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async {
    renderConfigs.add(config);
    return const MermaidRenderResult(
      svg: '<svg viewBox="0 0 40 20"><rect width="40" height="20"/></svg>',
      diagramType: 'flowchart',
    );
  }
}

CanvasNode _node() => CanvasNode(
  id: 'mermaid-editor-node',
  type: NodeType.mermaid,
  x: 0,
  y: 0,
  width: 320,
  height: 220,
  payload: MermaidPayload(source: 'flowchart TD\n  A --> B', sourceRevision: 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saves edited Mermaid source and preserves its revision', (
    tester,
  ) async {
    MermaidPayload? saved;
    await tester.pumpWidget(
      testApp(
        MermaidEditorDialog(
          node: _node(),
          renderer: _EditorRenderer(),
          onSave: (value) => saved = value,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 320));

    final field = find.byKey(const ValueKey('mermaid-source-field'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'flowchart LR\n  A --> C');
    await tester.tap(find.byKey(const ValueKey('mermaid-save-source')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.source, 'flowchart LR\n  A --> C');
    expect(saved!.sourceRevision, 2);
  });

  testWidgets('shows line and column diagnostics for invalid Mermaid source', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        MermaidEditorDialog(
          node: _node(),
          renderer: _EditorRenderer(),
          onSave: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 320));
    await tester.enterText(
      find.byKey(const ValueKey('mermaid-source-field')),
      'flowchart TD\n  bad',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mermaid-editor-diagnostic')),
      findsOneWidget,
    );
    expect(find.textContaining('Line 2, column 4'), findsOneWidget);
    expect(find.textContaining('Unexpected token.'), findsWidgets);
  });

  testWidgets('theme selector rerenders with the selected Mermaid theme', (
    tester,
  ) async {
    final renderer = _EditorRenderer();
    await tester.pumpWidget(
      testApp(
        MermaidEditorDialog(node: _node(), renderer: renderer, onSave: (_) {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 320));

    await tester.tap(find.byKey(const ValueKey('mermaid-theme-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();

    expect(
      renderer.renderConfigs.any((config) => config.theme == MermaidTheme.dark),
      isTrue,
    );
  });

  testWidgets('read-only Mermaid editor does not enable source save', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        MermaidEditorDialog(
          node: _node(),
          readOnly: true,
          renderer: _EditorRenderer(),
          onSave: (_) => fail('read-only editor saved source'),
        ),
      ),
    );
    await tester.pump();

    final saveButton = tester.widget<Widget>(
      find.byKey(const ValueKey('mermaid-save-source')),
    );
    expect(saveButton, isNotNull);
    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .any(
            (semantics) =>
                semantics.properties.button == true &&
                semantics.properties.enabled == false,
          ),
      isTrue,
    );
  });
  testWidgets('Mermaid footer actions fit in a compact-height viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testApp(
        MermaidEditorDialog(
          node: _node(),
          renderer: _EditorRenderer(),
          onSave: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 320));

    final viewport = Rect.fromLTWH(0, 0, 320, 480);
    final dialog = tester.getRect(find.byType(Dialog));
    expect(dialog.left, greaterThanOrEqualTo(viewport.left));
    expect(dialog.top, greaterThanOrEqualTo(viewport.top));
    expect(dialog.right, lessThanOrEqualTo(viewport.right));
    expect(dialog.bottom, lessThanOrEqualTo(viewport.bottom));

    for (final finder in [
      find.byKey(const ValueKey('mermaid-editor-header')),
      find.byKey(const ValueKey('mermaid-editor-footer')),
      find.text('Cancel'),
      find.byKey(const ValueKey('mermaid-save-source')),
    ]) {
      final bounds = tester.getRect(finder);
      expect(bounds.left, greaterThanOrEqualTo(dialog.left));
      expect(bounds.top, greaterThanOrEqualTo(dialog.top));
      expect(bounds.right, lessThanOrEqualTo(dialog.right));
      expect(bounds.bottom, lessThanOrEqualTo(dialog.bottom));
    }

    expect(tester.takeException(), isNull);
  });
  testWidgets('wide editor preview split uses a thin border token', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testApp(
        MermaidEditorDialog(
          node: _node(),
          renderer: _EditorRenderer(),
          onSave: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 320));

    final divider = tester.widget<VerticalDivider>(
      find.byType(VerticalDivider),
    );
    expect(divider.width, AppBorder.thin);
    expect(divider.thickness, AppBorder.thin);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dialog header and footer use thin chrome borders', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        MermaidEditorDialog(
          node: _node(),
          renderer: _EditorRenderer(),
          onSave: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 320));

    final header = tester.widget<Container>(
      find.byKey(const ValueKey('mermaid-editor-header')),
    );
    final footer = tester.widget<Container>(
      find.byKey(const ValueKey('mermaid-editor-footer')),
    );
    final headerBorder =
        (header.decoration! as BoxDecoration).border! as Border;
    final footerBorder =
        (footer.decoration! as BoxDecoration).border! as Border;
    expect(headerBorder.bottom.width, AppBorder.thin);
    expect(headerBorder.bottom.color, AppTokens.dark.panelBorder);
    expect(footerBorder.top.width, AppBorder.thin);
    expect(footerBorder.top.color, AppTokens.dark.panelBorder);
    final preview = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('mermaid-editor-preview-frame')),
    );
    final previewDecoration = preview.decoration;
    expect(previewDecoration, isA<BoxDecoration>());
    final previewBorder =
        (previewDecoration as BoxDecoration).border! as Border;
    expect(previewBorder.top.width, AppBorder.thin);
    expect(tester.takeException(), isNull);
  });
}
