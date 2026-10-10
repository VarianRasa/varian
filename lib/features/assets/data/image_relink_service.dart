import 'asset_service.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';

class ImageRelinkAssignment {
  final String nodeId;
  final AssetPickerResult asset;

  const ImageRelinkAssignment({required this.nodeId, required this.asset});
}

List<ImageRelinkAssignment> planImageRelinks(
  Iterable<CanvasNode> nodes,
  List<AssetPickerResult> assets,
) {
  if (assets.isEmpty) return const [];

  final targets = nodes
      .where(
        (node) => node.type == NodeType.image && node.payload is ImagePayload,
      )
      .toList(growable: false);
  final usedAssetIndexes = <int>{};
  final assignments = <ImageRelinkAssignment>[];

  for (final node in targets) {
    final payload = node.payload as ImagePayload;
    final nodeKey =
        _assetStem(payload.assetId) ??
        _assetStem(payload.localPath) ??
        _assetStem(payload.url);
    var assetIndex = -1;
    if (nodeKey != null) {
      for (var index = 0; index < assets.length; index++) {
        if (!usedAssetIndexes.contains(index) &&
            _assetStem(assets[index].name) == nodeKey) {
          assetIndex = index;
          break;
        }
      }
      if (assetIndex < 0) {
        for (var index = 0; index < assets.length; index++) {
          final candidateKey = _assetStem(assets[index].name);
          if (!usedAssetIndexes.contains(index) &&
              candidateKey != null &&
              _isStemVariant(nodeKey, candidateKey)) {
            assetIndex = index;
            break;
          }
        }
      }
    }
    if (assetIndex < 0) {
      for (var index = 0; index < assets.length; index++) {
        if (!usedAssetIndexes.contains(index)) {
          assetIndex = index;
          break;
        }
      }
    }
    if (assetIndex < 0) break;

    usedAssetIndexes.add(assetIndex);
    assignments.add(
      ImageRelinkAssignment(nodeId: node.id, asset: assets[assetIndex]),
    );
  }

  return assignments;
}

String? _assetStem(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final withoutQuery = raw.split('?').first.split('#').first;
  final basename = withoutQuery.replaceAll('\\', '/').split('/').last;
  if (basename.isEmpty) return null;
  final dot = basename.lastIndexOf('.');
  final stem = dot > 0 ? basename.substring(0, dot) : basename;
  final normalized = stem.trim().toLowerCase();
  return normalized.isEmpty ? null : normalized;
}

bool _isStemVariant(String first, String second) {
  for (final separator in ['-', '_', ' ']) {
    if (first.startsWith('$second$separator') ||
        second.startsWith('$first$separator')) {
      return true;
    }
  }
  return false;
}
