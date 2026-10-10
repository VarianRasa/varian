import '../../../domain/models/mermaid_payload.dart';

class MermaidValidationResult {
  final bool isValid;
  final String diagramType;
  final MermaidDiagnostic? diagnostic;

  const MermaidValidationResult({
    required this.isValid,
    this.diagramType = 'unknown',
    this.diagnostic,
  });

  const MermaidValidationResult.valid({String diagramType = 'unknown'})
    : this(isValid: true, diagramType: diagramType);

  const MermaidValidationResult.invalid(MermaidDiagnostic diagnostic)
    : this(isValid: false, diagramType: 'unknown', diagnostic: diagnostic);
}

class MermaidRenderResult {
  final String? svg;
  final String diagramType;
  final MermaidDiagnostic? diagnostic;

  const MermaidRenderResult({
    this.svg,
    this.diagramType = 'unknown',
    this.diagnostic,
  });

  bool get isSuccess => svg != null && diagnostic == null;

  const MermaidRenderResult.failure(MermaidDiagnostic diagnostic)
    : this(diagnostic: diagnostic);
}

abstract interface class MermaidRenderer {
  /// Stable identity for renderer output and persisted preview caches.
  ///
  /// Adapters without a stable renderer identity return `null` to preserve
  /// legacy cache behavior.
  String? get rendererVersion;

  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  });

  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  });
}

String detectMermaidDiagramType(String source) {
  for (final rawLine in source.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('%%')) continue;
    if (line.startsWith('---')) continue;
    final match = RegExp(r'^([A-Za-z][A-Za-z0-9_-]*)').firstMatch(line);
    if (match != null) return match.group(1)!.toLowerCase();
  }
  return 'unknown';
}

/// Maps Mermaid header aliases to the stable family name stored on a canvas
/// source node. Unknown future headers stay visible instead of becoming
/// `unknown`, so the native fallback can still report which renderer family
/// produced the SVG.
String normalizeMermaidDiagramType(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return 'unknown';
  return switch (value) {
    'graph' || 'flowchart' => 'flowchart',
    'statediagram' || 'statediagram-v2' => 'statediagram',
    'sequencediagram' => 'sequencediagram',
    'classdiagram' => 'classdiagram',
    'erdiagram' => 'erdiagram',
    'requirementdiagram' => 'requirementdiagram',
    'quadrantchart' => 'quadrantchart',
    'xychart' || 'xychart-beta' => 'xychart',
    'sankey' || 'sankey-beta' => 'sankey',
    'block' || 'block-beta' => 'block',
    'architecture' || 'architecture-beta' => 'architecture',
    'packet' || 'packet-beta' => 'packet',
    'kanban' => 'kanban',
    'radar' || 'radar-beta' => 'radar',
    'treemap' => 'treemap',
    'venn' => 'venn',
    'zenuml' => 'zenuml',
    _ =>
      value.endsWith('-beta')
          ? value.substring(0, value.length - '-beta'.length)
          : value,
  };
}

MermaidDiagnostic rendererDiagnostic(
  String code,
  String message, {
  int? line,
  int? column,
}) => MermaidDiagnostic(
  code: code,
  message: message.length > 1000 ? message.substring(0, 1000) : message,
  line: line,
  column: column,
);
