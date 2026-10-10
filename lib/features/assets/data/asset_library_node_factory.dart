import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/models/durable_asset_reference.dart';
import '../../../domain/models/model3d_payload.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../domain/asset_library.dart';

class AssetLibraryNodeFactory {
  const AssetLibraryNodeFactory._();

  static CanvasNode create({
    required AssetLibraryItem item,
    required String nodeId,
    required Offset position,
    String? assetId,
    String? imageArtifactReference,
  }) {
    if (!item.isInsertable) {
      throw StateError(
        'This library asset is not ready or has no durable source.',
      );
    }
    final metadataType = item.metadata['insertNodeType']?.toString();
    final shapeType = _shapeType(metadataType);
    if (shapeType != null && item.source == AssetLibrarySource.bundled) {
      return CanvasNode(
        id: nodeId,
        type: shapeType,
        x: position.dx - 110,
        y: position.dy - 70,
        width: 220,
        height: 140,
        name: item.name,
        payload: ShapePayload(label: item.name),
      );
    }

    // Catalog URLs and machine-local paths are compatibility inputs only. The
    // factory is the durable canvas boundary, so only scoped Storage metadata
    // or a validated owned artifact reference may cross it.
    final storagePath = durableAssetReference(item.storagePath);
    final imageReference = validImageArtifactReference(
      imageArtifactReference ??
          item.metadata['imageArtifactReference']?.toString(),
    );
    final videoReference = validVideoArtifactReference(
      item.metadata['videoArtifactReference']?.toString(),
    );
    final model3dReference = validModel3DArtifactReference(
      item.metadata['model3dArtifactReference']?.toString(),
    );
    final fileReference = validFileArtifactReference(
      item.metadata['fileArtifactReference']?.toString(),
    );
    final audioReference = validMediaArtifactReference(
      item.metadata['audioArtifactReference']?.toString(),
    );
    final hasSource = switch (item.kind) {
      AssetLibraryItemKind.image ||
      AssetLibraryItemKind.graphic ||
      AssetLibraryItemKind.icon ||
      AssetLibraryItemKind.illustration =>
        storagePath != null || imageReference != null,
      AssetLibraryItemKind.video =>
        storagePath != null || videoReference != null,
      AssetLibraryItemKind.audio =>
        storagePath != null || audioReference != null,
      AssetLibraryItemKind.model3d =>
        storagePath != null || model3dReference != null,
      AssetLibraryItemKind.file => storagePath != null || fileReference != null,
    };
    if (!hasSource) {
      throw StateError(
        'This library asset must be materialized before insertion.',
      );
    }

    switch (item.kind) {
      case AssetLibraryItemKind.image:
      case AssetLibraryItemKind.graphic:
      case AssetLibraryItemKind.icon:
      case AssetLibraryItemKind.illustration:
        final width = item.width == null ? 280.0 : _canvasWidth(item);
        final height = item.height == null ? 200.0 : _canvasHeight(item);
        return CanvasNode(
          id: nodeId,
          type: NodeType.image,
          x: position.dx - width / 2,
          y: position.dy - height / 2,
          width: width,
          height: height,
          name: item.name,
          payload: ImagePayload(
            assetId: assetId ?? item.id,
            imageArtifactReference: imageReference,
            storagePath: storagePath,
            // URLs and native paths are transient catalog inputs. The canvas
            // insertion path must materialize them before calling this factory.
            caption: item.attribution,
          ),
        );
      case AssetLibraryItemKind.video:
        return CanvasNode(
          id: nodeId,
          type: NodeType.videoCard,
          x: position.dx - 160,
          y: position.dy - 90,
          width: 320,
          height: 180,
          name: item.name,
          payload: VideoPayload(
            title: item.name,
            assetId: assetId ?? item.id,
            storagePath: storagePath,
            videoArtifactReference: videoReference,
            // Provider URLs and local paths stay in the catalog compatibility
            // layer until materialized; they never enter the canvas payload.
            durationMs: item.durationMs,
            videoWidth: item.width,
            videoHeight: item.height,
          ),
        );
      case AssetLibraryItemKind.audio:
        return CanvasNode(
          id: nodeId,
          type: NodeType.audioCard,
          x: position.dx - 160,
          y: position.dy - 55,
          width: 320,
          height: 110,
          name: item.name,
          payload: AudioPayload(
            trackName: item.name,
            assetId: assetId ?? item.id,
            artist: item.creator ?? '',
            storagePath: storagePath,
            audioArtifactReference: audioReference,
            durationSeconds: item.durationMs == null
                ? null
                : (item.durationMs! / 1000).round(),
          ),
        );
      case AssetLibraryItemKind.model3d:
        return CanvasNode(
          id: nodeId,
          type: NodeType.model3d,
          x: position.dx - 150,
          y: position.dy - 150,
          width: 300,
          height: 300,
          name: item.name,
          payload: Model3DPayload(
            fileName: item.name,
            fileSizeText: _sizeLabel(item.sizeBytes),
            assetId: assetId ?? item.id,
            storagePath: storagePath,
            artifactReference: model3dReference,
          ),
        );
      case AssetLibraryItemKind.file:
        return CanvasNode(
          id: nodeId,
          type: NodeType.fileCard,
          x: position.dx - 140,
          y: position.dy - 90,
          width: 280,
          height: 180,
          name: item.name,
          payload: FilePayload(
            fileName: item.name,
            assetId: assetId ?? item.id,
            fileExtension: _extension(item.name),
            fileSizeText: _sizeLabel(item.sizeBytes),
            artifactReference: fileReference,
            storagePath: storagePath,
            description: item.description,
          ),
        );
    }
  }

  static NodeType? _shapeType(String? name) {
    if (name == null) return null;
    for (final type in NodeType.values) {
      if (type.name == name) return type;
    }
    return null;
  }

  static double _canvasWidth(AssetLibraryItem item) {
    final width = math.max(1.0, item.width?.toDouble() ?? 280);
    final height = math.max(1.0, item.height?.toDouble() ?? 200);
    final scale = math.min(320 / width, 240 / height);
    return width * scale;
  }

  static double _canvasHeight(AssetLibraryItem item) {
    final width = math.max(1.0, item.width?.toDouble() ?? 280);
    final height = math.max(1.0, item.height?.toDouble() ?? 200);
    final scale = math.min(320 / width, 240 / height);
    return height * scale;
  }

  static String _sizeLabel(int? size) {
    if (size == null || size <= 0) return 'Unknown size';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 || dot == name.length - 1
        ? 'FILE'
        : name.substring(dot + 1).toUpperCase();
  }
}
