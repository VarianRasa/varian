import 'dart:js_interop';

import '../../../domain/models/mermaid_payload.dart';
import '../domain/mermaid_renderer.dart';
import '../domain/mermaid_svg_sanitizer.dart';

@JS('globalThis.mermaid')
external _MermaidJs? get _mermaid;

@JS()
extension type _MermaidJs._(JSObject _) implements JSObject {
  external void initialize(JSObject config);
  external JSPromise<JSAny?> parse(String source);
  external JSPromise<_MermaidRenderOutput> render(String id, String source);
}

@JS()
extension type _MermaidRenderOutput._(JSObject _) implements JSObject {
  external String get svg;
}

class WebMermaidRenderer implements MermaidRenderer {
  static int _renderSequence = 0;
  static final _operations = _WebMermaidOperationQueue();

  @override
  String get rendererVersion => 'mermaid-js-11.17.2';

  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) => _operations.run(() => _validate(source, config: config));

  Future<MermaidValidationResult> _validate(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async {
    final limitDiagnostic = MermaidSourceLimits.validate(source);
    if (limitDiagnostic != null) {
      return MermaidValidationResult.invalid(limitDiagnostic);
    }

    final engine = _mermaid;
    if (engine == null) {
      return const MermaidValidationResult.invalid(
        MermaidDiagnostic(
          code: 'RENDERER_UNAVAILABLE',
          message: 'The local Mermaid web renderer is unavailable.',
        ),
      );
    }

    try {
      _initialize(engine, config);
      await engine.parse(source).toDart;
      return MermaidValidationResult.valid(
        diagramType: detectMermaidDiagramType(source),
      );
    } catch (_) {
      return MermaidValidationResult.invalid(
        rendererDiagnostic('MERMAID_PARSE_ERROR', 'Mermaid source is invalid.'),
      );
    }
  }

  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) => _operations.run(() => _render(source, config: config));

  Future<MermaidRenderResult> _render(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async {
    final validation = await _validate(source, config: config);
    if (!validation.isValid) {
      return MermaidRenderResult.failure(validation.diagnostic!);
    }

    final engine = _mermaid;
    if (engine == null) {
      return MermaidRenderResult.failure(
        rendererDiagnostic(
          'RENDERER_UNAVAILABLE',
          'The local Mermaid web renderer is unavailable.',
        ),
      );
    }

    try {
      final output = await engine
          .render('varian-mermaid-${_renderSequence++}', source)
          .toDart;
      final svg = MermaidSvgSanitizer.normalizeForFlutter(output.svg);
      return MermaidRenderResult(svg: svg, diagramType: validation.diagramType);
    } on MermaidSvgSecurityException catch (error) {
      return MermaidRenderResult.failure(
        rendererDiagnostic(
          error.code,
          'Mermaid renderer returned unsafe SVG output.',
        ),
      );
    } catch (_) {
      return MermaidRenderResult.failure(
        rendererDiagnostic(
          'MERMAID_RENDER_ERROR',
          'The Mermaid diagram could not be rendered.',
        ),
      );
    }
  }

  void _initialize(_MermaidJs engine, MermaidRenderConfig config) {
    final options = <String, dynamic>{
      'securityLevel': 'strict',
      'startOnLoad': false,
      'suppressErrorRendering': true,
      'htmlLabels': false,
      'theme': config.theme.value,
    };
    if (config.direction != null) {
      options['direction'] = config.direction!.value;
    }

    final safeOverrides = config.safeOverrides;
    final flowchart = <String, dynamic>{'htmlLabels': false};
    final configuredFlowchart = safeOverrides['flowchart'];
    if (configuredFlowchart is Map) {
      for (final entry in configuredFlowchart.entries) {
        if (entry.key is String &&
            (entry.value is String ||
                entry.value is num ||
                entry.value is bool)) {
          flowchart[entry.key as String] = entry.value;
        }
      }
    }
    options['flowchart'] = flowchart;

    for (final entry in safeOverrides.entries) {
      if (entry.key == 'flowchart') continue;
      options[entry.key] = entry.value;
    }

    engine.initialize(options.jsify() as JSObject);
  }
}

class _WebMermaidOperationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

MermaidRenderer createPlatformMermaidRenderer() => WebMermaidRenderer();
