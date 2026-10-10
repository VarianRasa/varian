import 'package:merman/merman.dart';

import '../../../domain/models/mermaid_payload.dart';
import '../domain/mermaid_renderer.dart';
import '../domain/mermaid_svg_sanitizer.dart';

/// Native renderer backed by the locally bundled merman FFI engine.
class MermanMermaidRenderer implements MermaidRenderer {
  Merman? _engine;

  @override
  String get rendererVersion => 'merman-0.7.0';

  Merman get _openedEngine => _engine ??= Merman.open();

  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async {
    final limitDiagnostic = MermaidSourceLimits.validate(source);
    if (limitDiagnostic != null) {
      return MermaidValidationResult.invalid(limitDiagnostic);
    }

    try {
      final result = _openedEngine.validate(
        source,
        optionsJson: config.toNativeOptionsJson(),
      );
      if (result.valid) {
        return MermaidValidationResult.valid(
          diagramType: detectMermaidDiagramType(source),
        );
      }
      return MermaidValidationResult.invalid(
        rendererDiagnostic(
          result.codeName,
          result.error ?? 'Mermaid source is invalid.',
        ),
      );
    } on MermanException catch (error) {
      return MermaidValidationResult.invalid(
        rendererDiagnostic(error.codeName, error.message),
      );
    } catch (_) {
      return const MermaidValidationResult.invalid(
        MermaidDiagnostic(
          code: 'RENDERER_UNAVAILABLE',
          message: 'The local Mermaid renderer is unavailable.',
        ),
      );
    }
  }

  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async {
    final validation = await validate(source, config: config);
    if (!validation.isValid) {
      return MermaidRenderResult.failure(validation.diagnostic!);
    }

    try {
      final svg = MermaidSvgSanitizer.normalizeForFlutter(
        _openedEngine.renderSvg(
          source,
          optionsJson: config.toNativeOptionsJson(),
        ),
      );
      return MermaidRenderResult(svg: svg, diagramType: validation.diagramType);
    } on MermaidSvgSecurityException catch (error) {
      return MermaidRenderResult.failure(
        rendererDiagnostic(
          error.code,
          'Mermaid renderer returned unsafe SVG output.',
        ),
      );
    } on MermanException catch (error) {
      return MermaidRenderResult.failure(
        rendererDiagnostic(error.codeName, error.message),
      );
    } catch (_) {
      return MermaidRenderResult.failure(
        rendererDiagnostic(
          'RENDER_ERROR',
          'The Mermaid diagram could not be rendered.',
        ),
      );
    }
  }
}

MermaidRenderer createPlatformMermaidRenderer() => MermanMermaidRenderer();
