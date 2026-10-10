import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/mermaid/domain/mermaid_renderer.dart';
import 'package:varian/features/mermaid/presentation/mermaid_node_preview.dart';

import '../../test_app.dart';

class _FakeMermaidRenderer implements MermaidRenderer {
  @override
  final String? rendererVersion;
  final Map<String, Completer<MermaidRenderResult>> pending = {};
  final List<String> renderedSources = [];

  _FakeMermaidRenderer({this.rendererVersion});

  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async => const MermaidValidationResult.valid(diagramType: 'flowchart');

  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) {
    renderedSources.add(source);
    final completer = Completer<MermaidRenderResult>();
    pending[source] = completer;
    return completer.future;
  }

  void complete(String source, MermaidRenderResult result) {
    pending.remove(source)?.complete(result);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const svg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20">'
      '<rect width="40" height="20" fill="#fff"/></svg>';

  testWidgets('renders a bounded SVG and publishes derived state', (
    tester,
  ) async {
    final renderer = _FakeMermaidRenderer();
    final updates = <MermaidPayload>[];
    final payload = MermaidPayload(
      source: 'flowchart TD\n  A --> B',
      sourceRevision: 1,
    );

    await tester.pumpWidget(
      testApp(
        MermaidNodePreview(
          payload: payload,
          renderer: renderer,
          onRenderStateChanged: updates.add,
        ),
      ),
    );
    await tester.pump();

    renderer.complete(
      payload.source,
      const MermaidRenderResult(svg: svg, diagramType: 'flowchart'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(updates, hasLength(1));
    expect(updates.single.cachedSvg, svg);
    expect(updates.single.cachedSvgRevision, 1);
    expect(updates.single.diagramType, 'flowchart');
  });

  testWidgets('drops an unsafe cached SVG and shows the render error state', (
    tester,
  ) async {
    final renderer = _FakeMermaidRenderer();
    final payload = MermaidPayload(
      source: 'flowchart TD\n  A --> B',
      sourceRevision: 2,
      cachedSvg: '<svg><script>alert(1)</script></svg>',
      cachedSvgRevision: 2,
    );

    await tester.pumpWidget(
      testApp(MermaidNodePreview(payload: payload, renderer: renderer)),
    );
    await tester.pump();

    expect(find.byType(SvgPicture), findsNothing);
    expect(
      find.byKey(const ValueKey('mermaid-preview-status')),
      findsOneWidget,
    );
    renderer.complete(
      payload.source,
      const MermaidRenderResult.failure(
        MermaidDiagnostic(code: 'RENDER_ERROR', message: 'Preview failed.'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Preview failed.'), findsWidgets);
    expect(renderer.renderedSources, [payload.source]);
  });

  testWidgets('ignores a stale render result after the source changes', (
    tester,
  ) async {
    final renderer = _FakeMermaidRenderer();
    final updates = <MermaidPayload>[];
    final first = MermaidPayload(
      source: 'flowchart TD\n  A --> B',
      sourceRevision: 1,
    );
    final second = first.updateSource('flowchart LR\n  A --> C');

    await tester.pumpWidget(
      testApp(
        MermaidNodePreview(
          payload: first,
          renderer: renderer,
          onRenderStateChanged: updates.add,
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      testApp(
        MermaidNodePreview(
          payload: second,
          renderer: renderer,
          onRenderStateChanged: updates.add,
        ),
      ),
    );
    await tester.pump();

    renderer.complete(
      first.source,
      const MermaidRenderResult(svg: svg, diagramType: 'flowchart'),
    );
    await tester.pump();
    expect(updates, isEmpty);

    renderer.complete(
      second.source,
      const MermaidRenderResult(svg: svg, diagramType: 'flowchart'),
    );
    await tester.pump();
    await tester.pump();

    expect(updates, hasLength(1));
    expect(updates.single.sourceRevision, second.sourceRevision);
  });

  testWidgets('rejects a cached SVG from a different source revision', (
    tester,
  ) async {
    final renderer = _FakeMermaidRenderer();
    final payload = MermaidPayload(
      source: 'flowchart TD\n  A --> B',
      sourceRevision: 2,
      cachedSvg: svg,
      cachedSvgRevision: 1,
    );

    await tester.pumpWidget(
      testApp(MermaidNodePreview(payload: payload, renderer: renderer)),
    );
    await tester.pump();

    expect(find.byType(SvgPicture), findsNothing);
    renderer.complete(
      payload.source,
      const MermaidRenderResult.failure(
        MermaidDiagnostic(code: 'RENDER_ERROR', message: 'Preview failed.'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Preview failed.'), findsWidgets);
  });

  testWidgets('rejects a cached SVG from a different renderer version', (
    tester,
  ) async {
    final renderer = _FakeMermaidRenderer(
      rendererVersion: 'web-mermaid-11.17.2',
    );
    const config = MermaidRenderConfig();
    final payload = MermaidPayload(
      source: 'flowchart TD\\n  A --> B',
      sourceRevision: 1,
      cachedSvg: svg,
      cachedSvgRevision: 1,
      cachedSvgConfigKey: config.cacheKey,
      rendererVersion: 'merman-0.7.0',
    );

    await tester.pumpWidget(
      testApp(MermaidNodePreview(payload: payload, renderer: renderer)),
    );
    await tester.pump();

    expect(find.byType(SvgPicture), findsNothing);
    renderer.complete(
      payload.source,
      const MermaidRenderResult.failure(
        MermaidDiagnostic(code: 'RENDER_ERROR', message: 'Preview failed.'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Preview failed.'), findsWidgets);
  });

  testWidgets('rejects a cached SVG from a different Mermaid theme', (
    tester,
  ) async {
    final renderer = _FakeMermaidRenderer();
    const defaultConfig = MermaidRenderConfig();
    final payload = MermaidPayload(
      source: 'flowchart TD\n  A --> B',
      theme: MermaidTheme.dark,
      sourceRevision: 1,
      cachedSvg: svg,
      cachedSvgRevision: 1,
      cachedSvgConfigKey: defaultConfig.cacheKey,
    );

    await tester.pumpWidget(
      testApp(MermaidNodePreview(payload: payload, renderer: renderer)),
    );
    await tester.pump();

    expect(find.byType(SvgPicture), findsNothing);
    renderer.complete(
      payload.source,
      const MermaidRenderResult.failure(
        MermaidDiagnostic(code: 'RENDER_ERROR', message: 'Preview failed.'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Preview failed.'), findsWidgets);
  });

  testWidgets('publishes the renderer version with fresh cache metadata', (
    tester,
  ) async {
    final renderer = _FakeMermaidRenderer(rendererVersion: 'test-renderer-1');
    final updates = <MermaidPayload>[];
    final payload = MermaidPayload(
      source: 'flowchart TD\\n  A --> B',
      sourceRevision: 1,
    );

    await tester.pumpWidget(
      testApp(
        MermaidNodePreview(
          payload: payload,
          renderer: renderer,
          onRenderStateChanged: updates.add,
        ),
      ),
    );
    await tester.pump();

    renderer.complete(
      payload.source,
      const MermaidRenderResult(svg: svg, diagramType: 'flowchart'),
    );
    await tester.pump();
    await tester.pump();

    expect(updates.single.rendererVersion, 'test-renderer-1');
  });

  testWidgets('normalizes cached and newly rendered SVG styles', (
    tester,
  ) async {
    final renderer = _FakeMermaidRenderer();
    final updates = <MermaidPayload>[];
    const styledSvg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>.node{fill:#ECECFF;stroke:#9370DB;}</style>'
        '<rect class="node" width="40" height="20"/></svg>';
    const config = MermaidRenderConfig();
    final cachedPayload = MermaidPayload(
      source: 'flowchart TD\n  A --> B',
      sourceRevision: 1,
      cachedSvg: styledSvg,
      cachedSvgRevision: 1,
      cachedSvgConfigKey: config.cacheKey,
    );

    await tester.pumpWidget(
      testApp(
        MermaidNodePreview(
          payload: cachedPayload,
          renderer: renderer,
          onRenderStateChanged: updates.add,
        ),
      ),
    );
    await tester.pump();

    renderer.complete(
      cachedPayload.source,
      const MermaidRenderResult(svg: styledSvg, diagramType: 'flowchart'),
    );
    await tester.pump();
    await tester.pump();

    expect(updates, hasLength(1));
    expect(updates.single.cachedSvg, isNot(contains('<style>')));
    expect(updates.single.cachedSvgConfigKey, config.cacheKey);
  });
}
