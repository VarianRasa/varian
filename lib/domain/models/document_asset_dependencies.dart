import 'component_payload.dart';
import 'document_asset.dart';
import 'drawing_paper_payload.dart';
import 'media_timeline.dart';
import 'model3d_payload.dart';
import 'node.dart';
import 'node_payload.dart';

/// A durable artifact reachable from a canvas node payload.
///
/// [assetId] is the preferred identity. A dependency may carry only a durable
/// reference for legacy/auxiliary payload fields; durable boundaries must
/// resolve that reference to exactly one manifest entry before publication.
class DocumentAssetDependency {
  final String? assetId;
  final String? durableReference;
  final DocumentAssetKind kind;

  const DocumentAssetDependency({
    required this.kind,
    this.assetId,
    this.durableReference,
  });

  bool get isEmpty => assetId == null && durableReference == null;
}

/// The transitive artifact dependencies of a set of canvas nodes.
class DocumentAssetDependencyClosure {
  final List<DocumentAssetDependency> dependencies;

  const DocumentAssetDependencyClosure(this.dependencies);

  Set<String> get assetIds => {
    for (final dependency in dependencies) ?dependency.assetId,
  };

  Iterable<DocumentAssetDependency> get unkeyed =>
      dependencies.where((dependency) => dependency.assetId == null);
}

/// Collects every asset identity reachable from [nodes], including nested-board
/// children, image masks, model snapshots, and media timeline artifacts.
DocumentAssetDependencyClosure collectDocumentAssetDependencies(
  Iterable<CanvasNode> nodes,
) {
  final dependencies = <DocumentAssetDependency>[];
  final visited = <CanvasNode>{};

  void add({
    required DocumentAssetKind kind,
    String? assetId,
    String? durableReference,
  }) {
    final normalizedId = _normalized(assetId);
    final normalizedReference = _normalized(durableReference);
    if (normalizedId == null && normalizedReference == null) return;
    dependencies.add(
      DocumentAssetDependency(
        kind: kind,
        assetId: normalizedId,
        durableReference: normalizedReference,
      ),
    );
  }

  void addTimeline(MediaTimeline? timeline, DocumentAssetKind kind) {
    if (timeline == null) return;
    for (final artifact in timeline.artifacts.items) {
      add(kind: kind, durableReference: artifact.reference);
    }
  }

  void visit(CanvasNode node) {
    if (!visited.add(node)) return;
    final payload = node.payload;
    switch (payload) {
      case ImagePayload():
        add(
          kind: DocumentAssetKind.image,
          assetId: payload.assetId,
          durableReference:
              payload.imageArtifactReference ?? payload.storagePath,
        );
        final mask = payload.backgroundMask;
        if (mask != null) {
          add(
            kind: DocumentAssetKind.image,
            assetId: mask.assetId,
            durableReference: mask.imageArtifactReference ?? mask.storagePath,
          );
        }
      case FilePayload():
        add(
          kind: DocumentAssetKind.document,
          assetId: payload.assetId,
          durableReference: payload.artifactReference ?? payload.storagePath,
        );
      case VideoPayload():
        add(
          kind: DocumentAssetKind.video,
          assetId: payload.assetId,
          durableReference:
              payload.videoArtifactReference ?? payload.storagePath,
        );
        add(
          kind: DocumentAssetKind.image,
          durableReference:
              payload.posterArtifactReference ?? payload.posterStoragePath,
        );
        addTimeline(payload.mediaTimeline, DocumentAssetKind.video);
      case AudioPayload():
        add(
          kind: DocumentAssetKind.audio,
          assetId: payload.assetId,
          durableReference:
              payload.audioArtifactReference ?? payload.storagePath,
        );
        addTimeline(payload.mediaTimeline, DocumentAssetKind.audio);
      case Model3DPayload():
        add(
          kind: DocumentAssetKind.model3d,
          assetId: payload.assetId,
          durableReference: payload.artifactReference ?? payload.storagePath,
        );
        for (final snapshot in payload.snapshots) {
          add(
            kind: DocumentAssetKind.image,
            assetId: snapshot.assetId,
            durableReference: snapshot.artifactReference,
          );
        }
      case AnnotatedImagePayload():
        add(
          kind: DocumentAssetKind.image,
          assetId: payload.assetId,
          durableReference: payload.imageArtifactReference,
        );
      case DrawingPaperPayload():
        add(
          kind: DocumentAssetKind.image,
          durableReference: payload.compositePreviewRef,
        );
        add(
          kind: DocumentAssetKind.image,
          durableReference: payload.referenceConfig.storagePath,
        );
        for (final page in payload.studioPages) {
          visit(
            CanvasNode(
              id: page.id,
              type: NodeType.drawingPaper,
              x: page.position.dx,
              y: page.position.dy,
              width: 0,
              height: 0,
              payload: page.payload,
            ),
          );
        }
      case ComponentPayload():
        for (final child in payload.templateChildren) {
          visit(child);
        }
        for (final slot in payload.slots) {
          for (final child in slot.fallbackChildren) {
            visit(child);
          }
        }
        for (final children in payload.slotContent.values) {
          for (final child in children) {
            visit(child);
          }
        }
      case NestedBoardPayload():
        for (final child in payload.subNodes) {
          visit(child);
        }
      default:
        break;
    }
  }

  for (final node in nodes) {
    visit(node);
  }
  return DocumentAssetDependencyClosure(List.unmodifiable(dependencies));
}

String? _normalized(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
