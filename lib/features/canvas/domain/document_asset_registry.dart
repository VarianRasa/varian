import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/document_asset.dart';
import '../../../domain/models/document_asset_dependencies.dart';
import '../../../domain/models/durable_asset_reference.dart';
import '../../../domain/models/model3d_payload.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../../../features/assets/data/asset_service.dart';

/// Carries a producer's prepared node and manifest entry across the final
/// publication boundary without dropping byte-backed metadata or lifecycle
/// context.
class PreparedDocumentAssetNode {
  final CanvasNode node;
  final DocumentAsset asset;
  final int operationGeneration;
  final String projectId;
  final String? accountId;

  const PreparedDocumentAssetNode({
    required this.node,
    required this.asset,
    this.operationGeneration = 0,
    this.projectId = '',
    this.accountId,
  });
}

/// Chooses a stable manifest identity for an artifact attached to a node.
///
/// Existing IDs are reused only when the manifest contains them and no other
/// node references them. Replacements therefore cannot mutate a shared asset
/// entry that another node still renders.
String? _effectiveDocumentAssetReference(DocumentAsset asset) =>
    asset.durableReference ?? asset.remoteUrl;

String stableDocumentAssetId({
  required String? candidate,
  required DocumentAssetManifest manifest,
  required Iterable<CanvasNode> nodes,
  String? ownerNodeId,
  String? fallback,
}) {
  manifest.validateIdentity();
  final normalized = candidate?.trim();
  final candidateAsset = normalized == null ? null : manifest[normalized];
  if (normalized != null &&
      normalized.isNotEmpty &&
      candidateAsset != null &&
      !nodes.any(
        (node) =>
            node.id != ownerNodeId &&
            _nodeReferencesDocumentAsset(
              node,
              normalized,
              durableReference: _effectiveDocumentAssetReference(
                candidateAsset,
              ),
            ),
      )) {
    return normalized;
  }

  // New nodes do not have a manifest candidate yet. Prefer the caller's
  // identity when it is unused; this keeps node, payload, and manifest IDs
  // aligned without allowing a shared entry to be overwritten.
  final normalizedFallback = fallback?.trim();
  if (normalizedFallback != null &&
      normalizedFallback.isNotEmpty &&
      manifest[normalizedFallback] == null &&
      !nodes.any(
        (node) =>
            node.id != ownerNodeId &&
            (node.id == normalizedFallback ||
                _nodeReferencesDocumentAsset(node, normalizedFallback)),
      )) {
    return normalizedFallback;
  }
  return const Uuid().v4();
}

bool _nodeReferencesDocumentAsset(
  CanvasNode node,
  String assetId, {
  String? durableReference,
}) {
  return collectDocumentAssetDependencies([node]).dependencies.any(
    (dependency) =>
        dependency.assetId == assetId ||
        (durableReference != null &&
            dependency.durableReference == durableReference),
  );
}

/// Builds a manifest record from a validated artifact reference or a
/// project-scoped Storage path. Runtime paths and delivery URLs are omitted.
DocumentAsset? buildDocumentAsset({
  required String id,
  required DocumentAssetKind kind,
  required String name,
  required String mimeType,
  required String? artifactReference,
  required String? storagePath,
  required int? declaredSize,
  required Uint8List? bytes,
  DocumentAsset? existing,
  Map<String, dynamic> metadata = const {},
}) {
  final typedReference = _typedArtifactReference(kind, artifactReference);
  final stableStoragePath = durableAssetReference(storagePath);
  final durableReference = typedReference ?? stableStoragePath;
  if (durableReference == null) return null;

  final normalizedName = name.trim().isEmpty ? 'Untitled asset' : name.trim();
  final normalizedMimeType = mimeType.trim().isEmpty
      ? 'application/octet-stream'
      : mimeType.trim().toLowerCase();
  final sizeBytes = bytes?.lengthInBytes ?? declaredSize;
  final checksum = bytes == null || bytes.isEmpty
      ? null
      : sha256.convert(bytes).toString();
  final now = DateTime.now().toUtc();
  final storage = typedReference != null
      ? DocumentAssetStorage.local
      : DocumentAssetStorage.remote;

  return existing?.copyWith(
        id: id,
        kind: kind,
        storage: storage,
        name: normalizedName,
        mimeType: normalizedMimeType,
        sizeBytes: sizeBytes,
        checksum: checksum,
        localPath: null,
        remoteUrl: null,
        durableReference: durableReference,
        thumbnailReference: null,
        version: existing.version + 1,
        updatedAt: now,
        metadata: metadata,
      ) ??
      DocumentAsset(
        id: id,
        kind: kind,
        storage: storage,
        name: normalizedName,
        mimeType: normalizedMimeType,
        sizeBytes: sizeBytes,
        checksum: checksum,
        durableReference: durableReference,
        createdAt: now,
        updatedAt: now,
        metadata: metadata,
      );
}

String? _typedArtifactReference(
  DocumentAssetKind kind,
  String? artifactReference,
) => switch (kind) {
  DocumentAssetKind.image => validImageArtifactReference(artifactReference),
  DocumentAssetKind.audio => validMediaArtifactReference(artifactReference),
  DocumentAssetKind.video => validVideoArtifactReference(artifactReference),
  DocumentAssetKind.model3d => validModel3DArtifactReference(artifactReference),
  DocumentAssetKind.document => validFileArtifactReference(artifactReference),
  _ => durableAssetReference(artifactReference),
};

String imageMimeTypeForName(String name) =>
    inferAssetMimeType(name, fallback: 'image/png');

String fileMimeTypeForName(String name) =>
    inferAssetMimeType(name, fallback: 'application/octet-stream');

/// Removes a staged artifact only when no persisted node references it.
/// Runtime callers use this after a replacement commit or rollback; it never
/// removes an asset that is still reachable from a document node.
DocumentAssetManifest removeUnreferencedDocumentAsset(
  DocumentAssetManifest manifest, {
  required String stagedAssetId,
  required Iterable<CanvasNode> nodes,
}) {
  manifest.validateIdentity();
  final stagedAsset = manifest[stagedAssetId];
  final referenced =
      stagedAsset != null &&
      nodes.any(
        (node) => _nodeReferencesDocumentAsset(
          node,
          stagedAssetId,
          durableReference: _effectiveDocumentAssetReference(stagedAsset),
        ),
      );
  return referenced ? manifest : manifest.remove(stagedAssetId);
}

/// Settles a temporary Model3D replacement manifest entry after either a
/// commit or a rejected operation. A staged ID is retained only when a node
/// still references it; this makes rollback safe for shared assets.
DocumentAssetManifest settleModel3DReplacementManifest({
  required DocumentAssetManifest manifest,
  required String stagedAssetId,
  required String? committedAssetId,
  required Iterable<CanvasNode> nodes,
}) {
  manifest.validateIdentity();
  if (committedAssetId == stagedAssetId) return manifest;
  return removeUnreferencedDocumentAsset(
    manifest,
    stagedAssetId: stagedAssetId,
    nodes: nodes,
  );
}

/// Commits a replacement manifest entry and returns the replacement payload's
/// final identity. The staged ID is never reused when the current asset is
/// shared by another node, and the staged entry is removed only after the
/// caller has published the node reference.
({DocumentAssetManifest manifest, String assetId}) commitModel3DReplacement({
  required DocumentAssetManifest manifest,
  required String stagedAssetId,
  required String? currentAssetId,
  String? ownerNodeId,
  required Iterable<CanvasNode> nodes,
}) {
  manifest.validateIdentity();
  final asset = manifest[stagedAssetId];
  if (asset == null) {
    throw StateError('Staged Model3D asset is missing from the manifest.');
  }
  final assetId = stableDocumentAssetId(
    candidate: currentAssetId,
    manifest: manifest,
    nodes: nodes,
    ownerNodeId: ownerNodeId,
  );
  final existing = manifest[assetId];
  final replacement = asset.copyWith(
    id: assetId,
    version: existing == null ? asset.version : existing.version + 1,
    createdAt: existing?.createdAt ?? asset.createdAt,
    updatedAt: DateTime.now().toUtc(),
  );
  var next = manifest.upsert(replacement);
  if (assetId != stagedAssetId) {
    next = removeUnreferencedDocumentAsset(
      next,
      stagedAssetId: stagedAssetId,
      nodes: nodes,
    );
  }
  return (manifest: next, assetId: assetId);
}

/// Publishes a prepared Model3D replacement as one manifest/node boundary.
/// If node publication fails, the temporary staged entry is removed and the
/// previous current asset entry is restored without leaving the replacement
/// identity orphaned in the manifest.
void publishModel3DReplacement({
  required DocumentAssetManifest originalManifest,
  required DocumentAssetManifest committedManifest,
  required String stagedAssetId,
  required Iterable<CanvasNode> nodes,
  required void Function(DocumentAssetManifest manifest) setManifest,
  required void Function() publishNode,
}) {
  originalManifest.validateIdentity();
  committedManifest.validateIdentity();
  setManifest(committedManifest);
  try {
    publishNode();
  } catch (_) {
    setManifest(
      removeUnreferencedDocumentAsset(
        originalManifest,
        stagedAssetId: stagedAssetId,
        nodes: nodes,
      ),
    );
    rethrow;
  }
}

/// Publishes a producer-created manifest entry together with its node.
///
/// Manifest publication happens first so the node never points at an absent
/// asset. If node publication fails, the exact original manifest is restored;
/// this keeps the operation atomic from the document's perspective.
void publishDocumentAssetAndNode({
  required DocumentAssetManifest originalManifest,
  required DocumentAssetManifest committedManifest,
  required void Function(DocumentAssetManifest manifest) setManifest,
  required void Function() publishNode,
}) {
  originalManifest.validateIdentity();
  committedManifest.validateIdentity();
  setManifest(committedManifest);
  try {
    publishNode();
  } catch (_) {
    setManifest(originalManifest);
    rethrow;
  }
}

/// Verifies that an asynchronous Model3D snapshot still targets the same
/// persisted source before publishing its manifest entry and payload update.
/// Verifies that an asynchronous artifact replacement still targets the same
/// node snapshot, project, and authenticated account before publishing it.
bool canCommitDocumentAssetReplacement({
  required CanvasNode capturedNode,
  required CanvasNode currentNode,
  required String operationProjectId,
  required String currentProjectId,
  required String? expectedAccountId,
  required String? currentAccountId,
}) {
  if (operationProjectId != currentProjectId ||
      expectedAccountId != currentAccountId ||
      capturedNode.id != currentNode.id ||
      capturedNode.type != currentNode.type) {
    return false;
  }
  return jsonEncode(capturedNode.toPersistenceJson()) ==
      jsonEncode(currentNode.toPersistenceJson());
}

/// Verifies that an asynchronous producer still belongs to the same editor
/// generation, project, and authenticated account before it publishes state.
bool canCommitArtifactProducer({
  required int operationGeneration,
  required int currentGeneration,
  required String operationProjectId,
  required String currentProjectId,
  required String? expectedAccountId,
  required String? currentAccountId,
}) =>
    operationGeneration == currentGeneration &&
    operationProjectId == currentProjectId &&
    expectedAccountId == currentAccountId;

bool canCommitModel3DSnapshot({
  required CanvasNode capturedNode,
  required CanvasNode currentNode,
}) {
  if (capturedNode.id != currentNode.id ||
      capturedNode.type != NodeType.model3d ||
      currentNode.type != NodeType.model3d) {
    return false;
  }
  final captured = capturedNode.payload;
  final current = currentNode.payload;
  if (captured is! Model3DPayload || current is! Model3DPayload) {
    return false;
  }
  return captured.assetId == current.assetId &&
      captured.artifactReference == current.artifactReference &&
      jsonEncode(captured.toPersistenceJson()) ==
          jsonEncode(current.toPersistenceJson());
}
