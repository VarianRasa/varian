import '../../../domain/models/mermaid_payload.dart';
import '../domain/mermaid_renderer.dart';

class StubMermaidRenderer implements MermaidRenderer {
  const StubMermaidRenderer();

  @override
  String? get rendererVersion => null;

  static const _diagnostic = MermaidDiagnostic(
    code: 'RENDERER_UNAVAILABLE',
    message: 'The local Mermaid renderer is unavailable on this target.',
  );

  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async {
    final limitDiagnostic = MermaidSourceLimits.validate(source);
    return limitDiagnostic == null
        ? const MermaidValidationResult.invalid(_diagnostic)
        : MermaidValidationResult.invalid(limitDiagnostic);
  }

  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async {
    final validation = await validate(source, config: config);
    return MermaidRenderResult.failure(validation.diagnostic ?? _diagnostic);
  }
}

MermaidRenderer createPlatformMermaidRenderer() => const StubMermaidRenderer();
