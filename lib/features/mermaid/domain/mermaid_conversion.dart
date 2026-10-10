import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/mermaid_payload.dart';

/// The complete detached native projection of a Mermaid source node.
///
/// A successful result contains every object that will be committed. A failed
/// result contains no partial native objects so the caller can keep the source
/// node unchanged.
class MermaidConversionResult {
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final String diagramType;
  final List<MermaidDiagnostic> warnings;
  final MermaidDiagnostic? diagnostic;
  final String? renderedSvg;

  const MermaidConversionResult({
    this.nodes = const [],
    this.edges = const [],
    this.diagramType = 'unknown',
    this.warnings = const [],
    this.diagnostic,
    this.renderedSvg,
  });

  const MermaidConversionResult.failure(
    MermaidDiagnostic diagnostic, {
    String diagramType = 'unknown',
  }) : this(diagnostic: diagnostic, diagramType: diagramType);

  bool get isSuccess => diagnostic == null;

  List<String> get nativeNodeIds => nodes.map((node) => node.id).toList();

  List<String> get nativeEdgeIds => edges.map((edge) => edge.id).toList();
}
