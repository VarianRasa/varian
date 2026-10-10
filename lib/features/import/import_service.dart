import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/connector_edge.dart';
import '../../domain/models/document.dart';
import '../../domain/models/document_asset.dart';
import '../../domain/models/durable_asset_reference.dart';
import '../../domain/models/document_package.dart';
import '../../domain/models/document_package_archive.dart';
import '../../domain/models/component_payload.dart';
import '../../domain/models/document_package_diagnostics.dart';
import '../../domain/models/drawing_paper_payload.dart';
import '../../domain/models/model3d_payload.dart';
import '../../domain/models/node.dart';
import '../../domain/models/node_payload.dart';
import '../../data/artifacts/artifact_store_bundle.dart';
import '../ai/data/image_artifact_store.dart';
import '../ai/data/video_artifact_store.dart';
import '../assets/data/asset_service.dart';
import '../assets/data/file_artifact_store.dart';
import '../media/data/media_artifact_store.dart';
import '../../domain/models/media_timeline.dart';
import '../model3d/data/model3d_artifact_store.dart';
import '../canvas/domain/document_asset_registry.dart';
import '../diagrams/data/drawio_xml_codec.dart';
import 'import_loss_report.dart';
import 'pdf_editable_importer.dart';
import 'pptx_editable_importer.dart';

class ImportResult {
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final DocumentAssetManifest assets;
  final String? error;
  final DocumentPackageHealthReport? packageHealth;
  final DocumentPackageMigrationPreview? migrationPreview;
  final DocumentPackageRepairResult? repairResult;
  final DocumentPackageArchive? packageArchive;
  final ImportLossReport? lossReport;

  /// Bytes kept transiently between import preview and artifact materialization.
  /// They are never serialized into the imported document.
  final Map<String, Uint8List> transientAssetBytes;

  /// Attachment bytes keyed by file-card node ID. These bytes are materialized
  /// through [FileArtifactStore] before the node is merged into a document.
  final Map<String, Uint8List> transientPayloadBytes;

  /// Timeline artifact bytes keyed by their imported opaque reference. These
  /// bytes are materialized through [MediaArtifactStore] before publication.
  final Map<String, Uint8List> transientMediaArtifactBytes;

  ImportResult({
    this.nodes = const [],
    this.edges = const [],
    this.assets = const DocumentAssetManifest(),
    this.error,
    this.packageHealth,
    this.migrationPreview,
    this.repairResult,
    this.packageArchive,
    this.lossReport,
    this.transientAssetBytes = const {},
    this.transientPayloadBytes = const {},
    this.transientMediaArtifactBytes = const {},
  });

  bool get isSuccess => error == null;
  bool get wasRepaired => repairResult?.changed == true;

  /// Materializes imported bytes into app-owned stores before merge. Remaining
  /// bytes stay transient and are never serialized into the document.
  Future<ImportResult> materializeArtifacts({
    ArtifactStoreBundle? artifactStoreBundle,
    ImageArtifactStore? imageArtifactStore,
    FileArtifactStore? fileArtifactStore,
    MediaArtifactStore? mediaArtifactStore,
    VideoArtifactStore? videoArtifactStore,
    Model3DArtifactStore? model3DArtifactStore,
  }) async {
    if (transientAssetBytes.isEmpty &&
        transientPayloadBytes.isEmpty &&
        transientMediaArtifactBytes.isEmpty) {
      return this;
    }
    final stores =
        artifactStoreBundle ??
        ArtifactStoreBundle(
          imageArtifactStore: imageArtifactStore,
          fileArtifactStore: fileArtifactStore,
          mediaArtifactStore: mediaArtifactStore,
          videoArtifactStore: videoArtifactStore,
          model3DArtifactStore: model3DArtifactStore,
        );
    final imageStore = stores.imageArtifactStore;
    final fileStore = stores.fileArtifactStore;
    final mediaStore = stores.mediaArtifactStore;
    final videoStore = stores.videoArtifactStore;
    final model3DStore = stores.model3DArtifactStore;
    var nextAssets = assets;
    final nextNodes = List<CanvasNode>.from(nodes);
    final remainingAssets = <String, Uint8List>{};
    final remainingPayloads = <String, Uint8List>{};
    final remainingMediaArtifacts = <String, Uint8List>{};
    final failures = <String>[];
    final referenceRemaps = <String, String>{};

    for (final entry in transientAssetBytes.entries) {
      final asset = nextAssets[entry.key];
      if (asset == null) {
        remainingAssets[entry.key] = entry.value;
        continue;
      }
      try {
        final reference = switch (asset.kind) {
          DocumentAssetKind.image => validImageArtifactReference(
            (await imageStore.save(
              entry.value,
              fileName: asset.name,
            )).reference,
          ),
          DocumentAssetKind.audio => validMediaArtifactReference(
            (await mediaStore.save(
              entry.value,
              kind: MediaArtifactKind.original,
              mimeType: asset.mimeType,
              checksum: _checksum(entry.value),
              fileName: asset.name,
              storagePolicy: MediaStoragePolicy.durable,
            )).reference,
          ),
          DocumentAssetKind.video => validVideoArtifactReference(
            (await videoStore.save(
              entry.value,
              fileName: asset.name,
            )).reference,
          ),
          DocumentAssetKind.model3d => validModel3DArtifactReference(
            (await model3DStore.save(
              entry.value,
              fileName: asset.name,
            )).reference,
          ),
          DocumentAssetKind.document => validFileArtifactReference(
            (await fileStore.save(entry.value, fileName: asset.name)).reference,
          ),
          _ => null,
        };
        if (reference == null) {
          remainingAssets[entry.key] = entry.value;
          failures.add(
            '${asset.name}: invalid ${asset.kind.name} artifact reference',
          );
          continue;
        }
        final previousReference = asset.durableReference;
        if (previousReference != null && previousReference != reference) {
          referenceRemaps[previousReference] = reference;
        }
        nextAssets = nextAssets.upsert(
          asset.copyWith(
            storage: DocumentAssetStorage.local,
            durableReference: reference,
            localPath: null,
            remoteUrl: null,
          ),
        );
        for (var index = 0; index < nextNodes.length; index++) {
          final node = nextNodes[index];
          nextNodes[index] = _replaceMaterializedAssetReference(
            node,
            asset.id,
            reference,
            referenceRemaps: referenceRemaps,
          );
        }
      } catch (error) {
        remainingAssets[entry.key] = entry.value;
        failures.add('${asset.name}: ${_safeError(error)}');
      }
    }

    for (final entry in transientMediaArtifactBytes.entries) {
      final oldReference = validMediaArtifactReference(entry.key);
      if (oldReference == null) {
        remainingMediaArtifacts[entry.key] = entry.value;
        failures.add('Timeline artifact: invalid durable media reference');
        continue;
      }
      MediaArtifact? sourceArtifact;
      for (final node in nextNodes) {
        sourceArtifact ??= _findMediaArtifactByReference(node, oldReference);
        if (sourceArtifact != null) break;
      }
      final artifact = sourceArtifact;
      if (artifact == null) {
        remainingMediaArtifacts[entry.key] = entry.value;
        continue;
      }
      try {
        final reference = validMediaArtifactReference(
          (await mediaStore.save(
            entry.value,
            kind: artifact.kind,
            mimeType: _safeTimelineMimeType(artifact.mimeType),
            checksum: _checksum(entry.value),
            fileName: _timelineArtifactFileName(artifact),
            storagePolicy: MediaStoragePolicy.durable,
          )).reference,
        );
        if (reference == null) {
          remainingMediaArtifacts[entry.key] = entry.value;
          failures.add(
            'Timeline artifact: invalid durable media artifact reference',
          );
          continue;
        }
        if (oldReference != reference) {
          referenceRemaps[oldReference] = reference;
        }
        for (var index = 0; index < nextNodes.length; index++) {
          nextNodes[index] = _replaceNodeTimelineReference(
            nextNodes[index],
            referenceRemaps,
          );
        }
      } catch (error) {
        remainingMediaArtifacts[entry.key] = entry.value;
        failures.add('Timeline artifact: ${_safeError(error)}');
      }
    }

    for (final entry in transientPayloadBytes.entries) {
      CanvasNode? target;
      for (final node in nextNodes) {
        target = _findNestedNodeById(node, entry.key);
        if (target != null) break;
      }
      final payload = target?.payload;
      if (target == null || payload is! FilePayload) {
        remainingPayloads[entry.key] = entry.value;
        continue;
      }
      try {
        final artifact = await fileStore.save(
          entry.value,
          fileName: payload.fileName,
        );
        final reference = validFileArtifactReference(artifact.reference);
        if (reference == null) {
          remainingPayloads[entry.key] = entry.value;
          failures.add('${payload.fileName}: invalid file artifact reference');
          continue;
        }
        final assetId = payload.assetId ?? entry.key;
        final asset = buildDocumentAsset(
          id: assetId,
          kind: DocumentAssetKind.document,
          name: payload.fileName,
          mimeType: inferAssetMimeType(
            payload.fileName,
            fallback: 'application/octet-stream',
          ),
          artifactReference: reference,
          storagePath: null,
          declaredSize: entry.value.lengthInBytes,
          bytes: entry.value,
        );
        if (asset == null) {
          remainingPayloads[entry.key] = entry.value;
          failures.add('${payload.fileName}: invalid document asset metadata');
          continue;
        }
        nextAssets = nextAssets.upsert(asset);
        final updatedNode = target.copyWith(
          payload: payload.copyWith(
            assetId: assetId,
            artifactReference: reference,
            clearLocalPath: true,
            clearBase64Data: true,
            clearRemoteUrl: true,
          ),
        );
        for (var index = 0; index < nextNodes.length; index++) {
          nextNodes[index] = _replaceNestedNodeById(
            nextNodes[index],
            target.id,
            updatedNode,
          );
        }
      } catch (error) {
        remainingPayloads[entry.key] = entry.value;
        failures.add('${payload.fileName}: ${_safeError(error)}');
      }
    }

    final nextLossReport = failures.isEmpty && lossReport == null
        ? null
        : ImportLossReport(
            format: lossReport?.format ?? ImportSourceFormat.file,
            preserved: lossReport?.preserved ?? const [],
            lossy: lossReport?.lossy ?? const [],
            unsupported: [
              ...?lossReport?.unsupported,
              ...failures.map((failure) => 'Artifact unavailable: $failure'),
            ],
          );
    return ImportResult(
      nodes: nextNodes,
      edges: edges,
      assets: nextAssets,
      error: error,
      packageHealth: packageHealth,
      migrationPreview: migrationPreview,
      repairResult: repairResult,
      packageArchive: packageArchive,
      lossReport: nextLossReport,
      transientAssetBytes: remainingAssets,
      transientPayloadBytes: remainingPayloads,
      transientMediaArtifactBytes: remainingMediaArtifacts,
    );
  }

  static String _safeTimelineMimeType(String? mimeType) {
    final normalized = mimeType?.trim().toLowerCase();
    if (normalized != null &&
        RegExp(
          r'^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$',
        ).hasMatch(normalized)) {
      return normalized;
    }
    return 'application/octet-stream';
  }

  static String _timelineArtifactFileName(MediaArtifact artifact) =>
      'timeline-${artifact.kind.name}';

  static String _safeError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\\s+'), ' ').trim();
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  static String _checksum(Uint8List bytes) =>
      DocumentPackageArchiveChecksum.sha256(bytes);

  static CanvasNode _replaceMaterializedAssetReference(
    CanvasNode node,
    String assetId,
    String reference, {
    Map<String, String> referenceRemaps = const {},
  }) {
    return node.copyWith(
      payload: _replacePayloadAssetReference(
        node.payload,
        assetId,
        reference,
        referenceRemaps: referenceRemaps,
      ),
    );
  }

  static NodePayload _replacePayloadAssetReference(
    NodePayload payload,
    String assetId,
    String reference, {
    Map<String, String> referenceRemaps = const {},
  }) {
    String? remapReference(String? value) =>
        value == null ? null : referenceRemaps[value] ?? value;

    MediaTimeline? remapTimeline(MediaTimeline? timeline) {
      if (timeline == null) return null;
      final artifacts = timeline.artifacts.items
          .map((artifact) {
            final remappedReference = remapReference(artifact.reference);
            if (remappedReference == null) return artifact;
            return MediaArtifact(
              kind: artifact.kind,
              path: null,
              url: null,
              reference: remappedReference,
              mimeType: artifact.mimeType,
              sizeBytes: artifact.sizeBytes,
              checksum: artifact.checksum,
            );
          })
          .toList(growable: false);
      return timeline.copyWith(
        artifacts: MediaArtifactManifest(items: artifacts),
      );
    }

    DrawingPaperPayload remapDrawingPaper(DrawingPaperPayload paper) {
      final remappedReference = remapReference(paper.compositePreviewRef);
      final remappedStorage = remapReference(paper.referenceConfig.storagePath);
      return paper.copyWith(
        compositePreviewRef: remappedReference ?? paper.compositePreviewRef,
        referenceConfig: paper.referenceConfig.copyWith(
          storagePath: remappedStorage ?? paper.referenceConfig.storagePath,
        ),
        studioPages: paper.studioPages
            .map(
              (page) => page.copyWith(payload: remapDrawingPaper(page.payload)),
            )
            .toList(growable: false),
      );
    }

    switch (payload) {
      case ImagePayload():
        var next = payload;
        final remappedImageReference = remapReference(
          payload.imageArtifactReference,
        );
        final remappedStoragePath = remapReference(payload.storagePath);
        if (payload.assetId == assetId) {
          next = payload.copyWith(
            imageArtifactReference: reference,
            clearLocalPath: true,
            clearUrl: true,
          );
        } else {
          if (remappedImageReference != null &&
              remappedImageReference != payload.imageArtifactReference) {
            next = next.copyWith(
              imageArtifactReference: remappedImageReference,
              clearLocalPath: true,
              clearUrl: true,
            );
          }
          if (remappedStoragePath != null &&
              remappedStoragePath != payload.storagePath) {
            next = next.copyWith(storagePath: remappedStoragePath);
          }
        }
        final mask = next.backgroundMask;
        final remappedMaskReference = remapReference(
          mask?.imageArtifactReference,
        );
        final remappedMaskStoragePath = remapReference(mask?.storagePath);
        if (mask?.assetId == assetId) {
          next = next.copyWith(
            backgroundMask: ImageMask(
              assetId: mask!.assetId,
              imageArtifactReference: reference,
              storagePath: mask.storagePath,
              localPath: null,
              url: null,
              mode: mask.mode,
              opacity: mask.opacity,
              enabled: mask.enabled,
            ),
          );
        } else if (mask != null &&
            (remappedMaskReference != null ||
                remappedMaskStoragePath != null)) {
          next = next.copyWith(
            backgroundMask: mask.copyWith(
              imageArtifactReference:
                  remappedMaskReference ?? mask.imageArtifactReference,
              storagePath: remappedMaskStoragePath ?? mask.storagePath,
              localPath: null,
              url: null,
            ),
          );
        }
        return next;
      case FilePayload():
        if (payload.assetId == assetId) {
          return payload.copyWith(
            artifactReference: reference,
            clearLocalPath: true,
            clearBase64Data: true,
            clearRemoteUrl: true,
          );
        }
        final remappedArtifactReference = remapReference(
          payload.artifactReference,
        );
        final remappedStoragePath = remapReference(payload.storagePath);
        if (remappedArtifactReference == null && remappedStoragePath == null) {
          return payload;
        }
        return payload.copyWith(
          artifactReference:
              remappedArtifactReference ?? payload.artifactReference,
          storagePath: remappedStoragePath ?? payload.storagePath,
          clearLocalPath: true,
          clearBase64Data: true,
          clearRemoteUrl: true,
        );
      case AudioPayload():
        var next = payload;
        final remappedAudioReference = remapReference(
          payload.audioArtifactReference,
        );
        final remappedAudioStoragePath = remapReference(payload.storagePath);
        if (payload.assetId == assetId) {
          next = payload.copyWith(
            audioArtifactReference: reference,
            audioPath: null,
            audioUrl: null,
          );
        } else {
          if (remappedAudioReference != null &&
              remappedAudioReference != payload.audioArtifactReference) {
            next = next.copyWith(
              audioArtifactReference: remappedAudioReference,
              audioPath: null,
              audioUrl: null,
            );
          }
          if (remappedAudioStoragePath != null &&
              remappedAudioStoragePath != payload.storagePath) {
            next = next.copyWith(storagePath: remappedAudioStoragePath);
          }
        }
        final timeline = remapTimeline(next.mediaTimeline);
        return next.copyWith(mediaTimeline: timeline);
      case VideoPayload():
        var next = payload;
        final remappedVideoReference = remapReference(
          payload.videoArtifactReference,
        );
        final remappedVideoStoragePath = remapReference(payload.storagePath);
        if (payload.assetId == assetId) {
          next = payload.copyWith(
            videoArtifactReference: reference,
            videoPath: null,
            videoUrl: null,
          );
        } else {
          if (remappedVideoReference != null &&
              remappedVideoReference != payload.videoArtifactReference) {
            next = next.copyWith(
              videoArtifactReference: remappedVideoReference,
              videoPath: null,
              videoUrl: null,
            );
          }
          if (remappedVideoStoragePath != null &&
              remappedVideoStoragePath != payload.storagePath) {
            next = next.copyWith(storagePath: remappedVideoStoragePath);
          }
        }
        final posterReference = remapReference(next.posterArtifactReference);
        final posterStoragePath = remapReference(next.posterStoragePath);
        if (posterReference != null &&
            posterReference != next.posterArtifactReference) {
          next = next.copyWith(
            posterArtifactReference: posterReference,
            posterPath: null,
            clearPosterUrl: true,
          );
        } else if (posterStoragePath != null &&
            posterStoragePath != next.posterStoragePath) {
          next = next.copyWith(posterStoragePath: posterStoragePath);
        }
        final posterMatches =
            next.posterArtifactReference == null &&
            next.posterStoragePath == null &&
            next.posterPath != null;
        if (posterMatches && assetId == next.assetId) {
          final posterReference = validImageArtifactReference(reference);
          if (posterReference != null) {
            next = next.copyWith(
              posterArtifactReference: posterReference,
              clearPosterPath: true,
              clearPosterUrl: true,
            );
          }
        }
        return next.copyWith(mediaTimeline: remapTimeline(next.mediaTimeline));
      case Model3DPayload():
        var next = payload;
        final remappedModelReference = remapReference(
          payload.artifactReference,
        );
        final remappedModelStoragePath = remapReference(payload.storagePath);
        if (payload.assetId == assetId) {
          next = payload.copyWith(
            artifactReference: reference,
            modelPath: null,
            modelUrl: null,
          );
        } else {
          if (remappedModelReference != null &&
              remappedModelReference != payload.artifactReference) {
            next = next.copyWith(
              artifactReference: remappedModelReference,
              modelPath: null,
              modelUrl: null,
            );
          }
          if (remappedModelStoragePath != null &&
              remappedModelStoragePath != payload.storagePath) {
            next = next.copyWith(storagePath: remappedModelStoragePath);
          }
        }
        final snapshots = next.snapshots
            .map((snapshot) {
              final remappedReference = remapReference(
                snapshot.artifactReference,
              );
              if (snapshot.assetId == assetId) {
                return snapshot.copyWith(artifactReference: reference);
              }
              if (remappedReference != null &&
                  remappedReference != snapshot.artifactReference) {
                return snapshot.copyWith(artifactReference: remappedReference);
              }
              return snapshot;
            })
            .toList(growable: false);
        return next.copyWith(snapshots: snapshots);
      case ComponentPayload():
        final templateChildren = _replaceNodeListAssetReference(
          payload.templateChildren,
          assetId,
          reference,
          referenceRemaps: referenceRemaps,
        );
        final slots = payload.slots
            .map(
              (slot) => slot.copyWith(
                fallbackChildren: _replaceNodeListAssetReference(
                  slot.fallbackChildren,
                  assetId,
                  reference,
                  referenceRemaps: referenceRemaps,
                ),
              ),
            )
            .toList(growable: false);
        final slotContent = <String, List<CanvasNode>>{
          for (final entry in payload.slotContent.entries)
            entry.key: _replaceNodeListAssetReference(
              entry.value,
              assetId,
              reference,
              referenceRemaps: referenceRemaps,
            ),
        };
        return payload.copyWith(
          templateChildren: templateChildren,
          slots: slots,
          slotContent: slotContent,
        );
      case NestedBoardPayload():
        return payload.copyWith(
          subNodes: _replaceNodeListAssetReference(
            payload.subNodes,
            assetId,
            reference,
            referenceRemaps: referenceRemaps,
          ),
        );
      case DrawingPaperPayload():
        final remapped = remapDrawingPaper(payload);
        final pages = remapped.studioPages
            .map(
              (page) => page.copyWith(
                payload:
                    _replacePayloadAssetReference(
                          page.payload,
                          assetId,
                          reference,
                          referenceRemaps: referenceRemaps,
                        )
                        as DrawingPaperPayload,
              ),
            )
            .toList(growable: false);
        return remapped.copyWith(studioPages: pages);
      case AnnotatedImagePayload():
        if (payload.assetId != assetId) return payload;
        return AnnotatedImagePayload(
          assetId: payload.assetId,
          imageArtifactReference: reference,
          imagePath: null,
          pins: payload.pins,
          showCornerBadge: payload.showCornerBadge,
          showLeaderLines: payload.showLeaderLines,
        );
      default:
        return payload;
    }
  }

  static List<CanvasNode> _replaceNodeListAssetReference(
    Iterable<CanvasNode> nodes,
    String assetId,
    String reference, {
    Map<String, String> referenceRemaps = const {},
  }) => [
    for (final node in nodes)
      _replaceMaterializedAssetReference(
        node,
        assetId,
        reference,
        referenceRemaps: referenceRemaps,
      ),
  ];

  static MediaArtifact? _findMediaArtifactByReference(
    CanvasNode node,
    String reference,
  ) {
    MediaArtifact? findInPayload(NodePayload payload) {
      final timeline = switch (payload) {
        AudioPayload() => payload.mediaTimeline,
        VideoPayload() => payload.mediaTimeline,
        _ => null,
      };
      for (final artifact
          in timeline?.artifacts.items ?? const <MediaArtifact>[]) {
        if (artifact.reference == reference) return artifact;
      }
      return null;
    }

    MediaArtifact? findInDrawingPaper(DrawingPaperPayload paper) {
      final direct = findInPayload(paper);
      if (direct != null) return direct;
      for (final page in paper.studioPages) {
        final found = findInDrawingPaper(page.payload);
        if (found != null) return found;
      }
      return null;
    }

    final direct = findInPayload(node.payload);
    if (direct != null) return direct;
    if (node.payload case final DrawingPaperPayload paper) {
      final found = findInDrawingPaper(paper);
      if (found != null) return found;
    }
    final payload = node.payload;
    final children = switch (payload) {
      ComponentPayload() => [
        ...payload.templateChildren,
        for (final slot in payload.slots) ...slot.fallbackChildren,
        for (final content in payload.slotContent.values) ...content,
      ],
      NestedBoardPayload() => payload.subNodes,
      DrawingPaperPayload() => [
        for (final page in payload.studioPages)
          CanvasNode(
            id: page.id,
            type: NodeType.drawingPaper,
            x: page.position.dx,
            y: page.position.dy,
            width: page.payload.pixelWidth,
            height: page.payload.pixelHeight,
            payload: page.payload,
          ),
      ],
      _ => const <CanvasNode>[],
    };
    for (final child in children) {
      final found = _findMediaArtifactByReference(child, reference);
      if (found != null) return found;
    }
    return null;
  }

  static CanvasNode _replaceNodeTimelineReference(
    CanvasNode node,
    Map<String, String> referenceRemaps,
  ) => node.copyWith(
    payload: _replacePayloadAssetReference(
      node.payload,
      '',
      '',
      referenceRemaps: referenceRemaps,
    ),
  );

  static CanvasNode? _findNestedNodeById(CanvasNode node, String nodeId) {
    if (node.id == nodeId) return node;
    final payload = node.payload;
    final children = switch (payload) {
      ComponentPayload() => [
        ...payload.templateChildren,
        for (final slot in payload.slots) ...slot.fallbackChildren,
        for (final content in payload.slotContent.values) ...content,
      ],
      NestedBoardPayload() => payload.subNodes,
      DrawingPaperPayload() => [
        for (final page in payload.studioPages)
          CanvasNode(
            id: page.id,
            type: NodeType.drawingPaper,
            x: page.position.dx,
            y: page.position.dy,
            width: page.payload.pixelWidth,
            height: page.payload.pixelHeight,
            payload: page.payload,
          ),
      ],
      _ => const <CanvasNode>[],
    };
    for (final child in children) {
      final found = _findNestedNodeById(child, nodeId);
      if (found != null) return found;
    }
    return null;
  }

  static CanvasNode _replaceNestedNodeById(
    CanvasNode node,
    String nodeId,
    CanvasNode replacement,
  ) {
    if (node.id == nodeId) return replacement;
    final payload = node.payload;
    switch (payload) {
      case ComponentPayload():
        return node.copyWith(
          payload: payload.copyWith(
            templateChildren: _replaceNestedNodeListById(
              payload.templateChildren,
              nodeId,
              replacement,
            ),
            slots: payload.slots
                .map(
                  (slot) => slot.copyWith(
                    fallbackChildren: _replaceNestedNodeListById(
                      slot.fallbackChildren,
                      nodeId,
                      replacement,
                    ),
                  ),
                )
                .toList(growable: false),
            slotContent: {
              for (final entry in payload.slotContent.entries)
                entry.key: _replaceNestedNodeListById(
                  entry.value,
                  nodeId,
                  replacement,
                ),
            },
          ),
        );
      case NestedBoardPayload():
        return node.copyWith(
          payload: payload.copyWith(
            subNodes: _replaceNestedNodeListById(
              payload.subNodes,
              nodeId,
              replacement,
            ),
          ),
        );
      case DrawingPaperPayload():
        return node.copyWith(
          payload: payload.copyWith(
            studioPages: payload.studioPages
                .map(
                  (page) => page.copyWith(
                    payload:
                        _replaceNestedNodeById(
                              CanvasNode(
                                id: page.id,
                                type: NodeType.drawingPaper,
                                x: page.position.dx,
                                y: page.position.dy,
                                width: page.payload.pixelWidth,
                                height: page.payload.pixelHeight,
                                payload: page.payload,
                              ),
                              nodeId,
                              replacement,
                            ).payload
                            as DrawingPaperPayload,
                  ),
                )
                .toList(growable: false),
          ),
        );
      default:
        return node;
    }
  }

  static List<CanvasNode> _replaceNestedNodeListById(
    Iterable<CanvasNode> nodes,
    String nodeId,
    CanvasNode replacement,
  ) => [
    for (final node in nodes) _replaceNestedNodeById(node, nodeId, replacement),
  ];
}

class ImportService {
  static ImportResult importFromJson(String rawJson, {bool repair = false}) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return ImportResult(
          error: 'Invalid Canvas Document JSON: root must be an object.',
        );
      }
      final decodedMap = Map<String, dynamic>.from(decoded);
      final package = decodedMap['format'] == CanvasDocumentPackage.format
          ? CanvasDocumentPackage.fromJson(decodedMap)
          : null;
      final sourceDocument =
          package?.document ?? CanvasDocument.fromJson(decodedMap);
      final sourcePackage =
          package ??
          CanvasDocumentPackage(
            document: sourceDocument,
            assets: sourceDocument.assets,
          );
      final repairResult = repair
          ? DocumentPackageDiagnostics.repair(sourcePackage)
          : null;
      final effectivePackage = repairResult?.package ?? sourcePackage;
      final doc = effectivePackage.document;
      final rawDocument = package == null
          ? decodedMap
          : decodedMap['document'] is Map
          ? Map<String, dynamic>.from(decodedMap['document'] as Map)
          : decodedMap;
      return ImportResult(
        nodes: doc.nodes,
        edges: doc.edges,
        assets: effectivePackage.assets,
        packageHealth: package == null
            ? null
            : DocumentPackageDiagnostics.inspect(sourcePackage),
        migrationPreview: DocumentPackageMigrationPreview.fromJson(rawDocument),
        repairResult: repairResult,
      );
    } catch (e) {
      return ImportResult(error: 'Invalid Canvas Document JSON: $e');
    }
  }

  static ImportResult importFromMermaid(String mermaidCode) {
    final source = mermaidCode.trim();
    final diagnostic = MermaidSourceLimits.validate(source);
    if (diagnostic != null) {
      return ImportResult(error: diagnostic.message);
    }

    return ImportResult(
      nodes: [
        CanvasNode(
          id: const Uuid().v4(),
          type: NodeType.mermaid,
          x: 80,
          y: 80,
          width: 480,
          height: 320,
          payload: MermaidPayload(source: source),
        ),
      ],
      lossReport: const ImportLossReport(
        format: ImportSourceFormat.mermaid,
        preserved: ['Mermaid source'],
      ),
    );
  }

  static ImportResult importFromMarkdown(String markdown) {
    final source = markdown.trim();
    if (source.isEmpty) {
      return ImportResult(error: 'Markdown source is empty.');
    }
    return ImportResult(
      nodes: [
        CanvasNode(
          id: const Uuid().v4(),
          type: NodeType.text,
          x: 80,
          y: 80,
          width: 640,
          height: 420,
          payload: TextPayload(
            text: source,
            renderMode: TextRenderMode.markdown,
            sizeMode: TextSizeMode.fixed,
          ),
        ),
      ],
      lossReport: const ImportLossReport(
        format: ImportSourceFormat.markdown,
        preserved: ['Markdown source and headings'],
      ),
    );
  }

  static ImportResult importFromCsv(String csv) {
    final rows = _parseCsv(csv);
    if (rows.isEmpty ||
        rows.every((row) => row.every((cell) => cell.isEmpty))) {
      return ImportResult(error: 'CSV source is empty.');
    }
    final width = rows.map((row) => row.length).reduce(math.max);
    final header = List<String>.generate(
      width,
      (index) => rows.first.length > index && rows.first[index].isNotEmpty
          ? rows.first[index]
          : 'Column ${index + 1}',
    );
    final data = rows
        .skip(1)
        .map(
          (row) => List<String>.generate(
            width,
            (index) => row.length > index ? row[index] : '',
          ),
        )
        .toList(growable: false);
    final hadRaggedRows = rows.any((row) => row.length != width);
    return ImportResult(
      nodes: [
        CanvasNode(
          id: const Uuid().v4(),
          type: NodeType.tableGrid,
          x: 80,
          y: 80,
          width: 720,
          height: math.min(640, 96 + data.length * 36).toDouble(),
          payload: TablePayload(columns: header, rows: data),
        ),
      ],
      lossReport: ImportLossReport(
        format: ImportSourceFormat.csv,
        preserved: ['CSV header and cell values'],
        lossy: hadRaggedRows
            ? ['Ragged rows were padded to the widest row.']
            : const [],
      ),
    );
  }

  static ImportResult importFromSvg(String svg) {
    final source = svg.trim();
    if (!source.startsWith('<svg') || !source.contains('</svg>')) {
      return ImportResult(
        error: 'SVG source must contain a complete <svg> root.',
      );
    }
    final unsafe = RegExp(
      r'<\s*script\b|\bon[a-z]+\s*=|javascript\s*:',
      caseSensitive: false,
    ).hasMatch(source);
    if (unsafe) {
      return ImportResult(error: 'SVG contains active or unsafe content.');
    }
    final bytes = Uint8List.fromList(utf8.encode(source));
    final nodeId = const Uuid().v4();
    return ImportResult(
      nodes: [
        CanvasNode(
          id: nodeId,
          type: NodeType.fileCard,
          x: 80,
          y: 80,
          width: 520,
          height: 340,
          payload: FilePayload(
            assetId: nodeId,
            fileName: 'import.svg',
            fileExtension: 'SVG',
            fileSizeText: '${bytes.length} B',
            description: 'Imported SVG source',
          ),
        ),
      ],
      transientPayloadBytes: {nodeId: bytes},
      lossReport: const ImportLossReport(
        format: ImportSourceFormat.svg,
        preserved: ['Original SVG bytes'],
        lossy: [
          'SVG is preserved as a file card, not decomposed into editable vectors.',
        ],
      ),
    );
  }

  static ImportResult importFromFileBytes({
    required String fileName,
    required Uint8List bytes,
    String? password,
  }) {
    final normalizedName = fileName.trim().isEmpty
        ? 'imported-file'
        : fileName.trim();
    final extension = normalizedName.contains('.')
        ? normalizedName.split('.').last.toLowerCase()
        : '';
    final text = utf8.decode(bytes, allowMalformed: true);
    switch (extension) {
      case 'md':
      case 'markdown':
        return importFromMarkdown(text);
      case 'csv':
        return importFromCsv(text);
      case 'svg':
        return importFromSvg(text);
      case 'pdf':
        final imported = PdfEditableImporter.tryImport(bytes);
        if (imported != null) {
          return ImportResult(
            nodes: imported.nodes,
            assets: imported.assets,
            transientAssetBytes: imported.transientAssetBytes,
            lossReport: imported.lossReport,
          );
        }
        break;
      case 'pptx':
        final imported = PptxEditableImporter.tryImport(bytes);
        if (imported != null) {
          return ImportResult(
            nodes: imported.nodes,
            assets: imported.assets,
            transientAssetBytes: imported.transientAssetBytes,
            lossReport: imported.lossReport,
          );
        }
        break;
      case 'varian':
      case 'vca':
        return _importPackageArchive(bytes, password: password);
      case 'zip':
        if (bytes.length >= 4 &&
            bytes[0] == 0x56 &&
            bytes[1] == 0x43 &&
            bytes[2] == 0x41 &&
            bytes[3] == 0x31) {
          return _importPackageArchive(bytes, password: password);
        }
        return importFromImageBundle(bytes);
    }
    final format = switch (extension) {
      'pdf' => ImportSourceFormat.file,
      'pptx' => ImportSourceFormat.file,
      'zip' => ImportSourceFormat.file,
      'png' || 'jpg' || 'jpeg' || 'webp' => ImportSourceFormat.file,
      _ => ImportSourceFormat.file,
    };
    final nodeId = const Uuid().v4();
    return ImportResult(
      nodes: [
        CanvasNode(
          id: nodeId,
          type: NodeType.fileCard,
          x: 80,
          y: 80,
          width: 520,
          height: 340,
          payload: FilePayload(
            assetId: nodeId,
            fileName: normalizedName,
            fileExtension: extension.toUpperCase(),
            fileSizeText: '${bytes.length} B',
            description: 'Imported $extension file',
          ),
        ),
      ],
      transientPayloadBytes: {nodeId: bytes},
      lossReport: ImportLossReport(
        format: format,
        preserved: ['Original file bytes'],
        lossy: const [
          'File is preserved as an attachment; internal pages/elements are not decomposed.',
        ],
      ),
    );
  }

  static ImportResult _importPackageArchive(
    Uint8List bytes, {
    String? password,
  }) {
    try {
      final archive = DocumentPackageArchive.decode(bytes, password: password);
      final packageHealth = DocumentPackageDiagnostics.inspect(archive.package);
      final migrationPreview = DocumentPackageMigrationPreview.fromJson(
        archive.package.document.toJson(),
      );
      final unsupported = [
        if (archive.missingAssetIds.isNotEmpty)
          'Missing asset payloads: ${archive.missingAssetIds.join(', ')}',
        if (archive.invalidAssetIds.isNotEmpty)
          'Invalid asset checksums: ${archive.invalidAssetIds.join(', ')}',
        if (!archive.packageChecksumValid)
          'Package checksum does not match document metadata.',
      ];
      if (!archive.isPortable) {
        return ImportResult(
          error: 'Project archive is not portable: ${unsupported.join(' ')}',
          packageArchive: archive,
          packageHealth: packageHealth,
          migrationPreview: migrationPreview,
          lossReport: ImportLossReport(
            format: ImportSourceFormat.file,
            preserved: const ['Document structure and package metadata'],
            unsupported: unsupported,
          ),
        );
      }
      return ImportResult(
        nodes: archive.package.document.nodes,
        edges: archive.package.document.edges,
        assets: archive.package.document.assets,
        packageArchive: archive,
        transientAssetBytes: archive.assetBytes,
        packageHealth: packageHealth,
        migrationPreview: migrationPreview,
        lossReport: ImportLossReport(
          format: ImportSourceFormat.file,
          preserved: [
            'Document structure and package metadata',
            if (archive.assetBytes.isNotEmpty) 'Embedded asset payloads',
          ],
          unsupported: unsupported,
        ),
      );
    } catch (error) {
      return ImportResult(error: 'Invalid project archive: $error');
    }
  }

  static ImportResult importFromImageBundle(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final now = DateTime.now().toUtc();
      var assets = const DocumentAssetManifest();
      final nodes = <CanvasNode>[];
      final transientAssetBytes = <String, Uint8List>{};
      final unsupported = <String>[];
      var index = 0;
      for (final file in archive) {
        if (!file.isFile || !_isSafeArchiveEntry(file.name)) continue;
        final extension = _fileExtension(file.name);
        final mimeType = _imageMimeType(extension);
        if (mimeType == null) {
          if (extension.isNotEmpty) unsupported.add(file.name);
          continue;
        }
        final assetId = const Uuid().v4();
        final payload = Uint8List.fromList(List<int>.from(file.content));
        final asset = DocumentAsset(
          id: assetId,
          kind: DocumentAssetKind.image,
          storage: DocumentAssetStorage.embedded,
          name: _fileName(file.name),
          mimeType: mimeType,
          sizeBytes: payload.length,
          checksum: DocumentPackageArchiveChecksum.sha256(payload),
          createdAt: now,
          updatedAt: now,
        );
        assets = assets.upsert(asset);
        transientAssetBytes[assetId] = payload;
        nodes.add(
          CanvasNode(
            id: const Uuid().v4(),
            type: NodeType.image,
            x: 80 + (index % 3) * 260,
            y: 80 + (index ~/ 3) * 220,
            width: 220,
            height: 180,
            payload: ImagePayload(
              assetId: assetId,
              fit: 'contain',
              caption: asset.name,
            ),
          ),
        );
        index++;
      }
      if (nodes.isEmpty) {
        return ImportResult(
          error: 'Image bundle contains no supported images.',
        );
      }
      return ImportResult(
        nodes: nodes,
        assets: assets,
        transientAssetBytes: transientAssetBytes,
        lossReport: ImportLossReport(
          format: ImportSourceFormat.imageBundle,
          preserved: [
            'Image bytes retained transiently until artifact materialization',
          ],
          unsupported: unsupported,
        ),
      );
    } catch (error) {
      return ImportResult(error: 'Invalid image bundle ZIP: $error');
    }
  }

  static bool _isSafeArchiveEntry(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.isNotEmpty &&
        !normalized.startsWith('/') &&
        !normalized.split('/').contains('..');
  }

  static String _fileExtension(String path) {
    final name = _fileName(path);
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static String _fileName(String path) =>
      path.replaceAll('\\', '/').split('/').last;

  static String? _imageMimeType(String extension) => switch (extension) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => null,
  };

  /// Parses standard Draw.io XML or mxGraphModel XML into CanvasNodes & CanvasEdges.
  static ImportResult importFromDrawioXml(String xmlString) {
    try {
      final result = DrawioXmlCodec.importDocument(xmlString);
      return ImportResult(nodes: result.nodes, edges: result.edges);
    } on DrawioXmlException catch (error) {
      return ImportResult(error: error.message);
    } catch (_) {
      return ImportResult(error: 'Failed to parse Draw.io XML.');
    }
  }

  /// Parses PlantUML activity / state diagram into CanvasNodes & CanvasEdges
  static ImportResult importFromPlantUml(String pumlCode) {
    try {
      final lines = pumlCode.split('\n');
      final Map<String, CanvasNode> nodeMap = {};
      final List<CanvasEdge> edges = [];

      int row = 0;
      int col = 0;
      const double startX = 100.0;
      const double startY = 100.0;
      const double colSpacing = 200.0;
      const double rowSpacing = 140.0;

      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty ||
            line.startsWith('@start') ||
            line.startsWith('@end') ||
            line.startsWith("'")) {
          continue;
        }

        // Match arrows: node1 -> node2 : label or node1 --> node2
        final arrowRegex = RegExp(
          r'^([a-zA-Z0-9_]+)\s*(?:->|-->)\s*([a-zA-Z0-9_]+)(?:\s*:\s*(.*))?$',
        );
        final arrowMatch = arrowRegex.firstMatch(line);
        if (arrowMatch != null) {
          final srcId = arrowMatch.group(1)!;
          final tgtId = arrowMatch.group(2)!;
          final label = arrowMatch.group(3)?.trim();

          final srcNode = _getOrCreateNode(
            srcId,
            srcId,
            NodeType.rectangle,
            nodeMap,
            startX + col * colSpacing,
            startY + row * rowSpacing,
          );

          final tgtNode = _getOrCreateNode(
            tgtId,
            tgtId,
            NodeType.rectangle,
            nodeMap,
            startX + (col + 1) * colSpacing,
            startY + (row + 1) * rowSpacing,
          );

          edges.add(
            CanvasEdge(
              id: const Uuid().v4(),
              sourceNodeId: srcNode.id,
              targetNodeId: tgtNode.id,
              sourceAnchor: AnchorPosition.bottom,
              targetAnchor: AnchorPosition.top,
              label: (label != null && label.isNotEmpty) ? label : null,
            ),
          );

          row++;
          if (row > 5) {
            row = 0;
            col += 2;
          }
        } else {
          // Match state/class/component e.g. state "State Name" as S1 or class ClassName
          final declRegex = RegExp(
            r'^(?:state|class|node|participant|component)\s+"?(.*?)"?\s+as\s+([a-zA-Z0-9_]+)$',
          );
          final declMatch = declRegex.firstMatch(line);
          if (declMatch != null) {
            final label = declMatch.group(1)!;
            final id = declMatch.group(2)!;
            _getOrCreateNode(
              id,
              label,
              NodeType.rectangle,
              nodeMap,
              startX + col * colSpacing,
              startY + row * rowSpacing,
            );
            row++;
          }
        }
      }

      if (nodeMap.isEmpty) {
        return ImportResult(error: 'No valid PlantUML elements identified.');
      }

      return ImportResult(nodes: nodeMap.values.toList(), edges: edges);
    } catch (e) {
      return ImportResult(error: 'Failed to parse PlantUML: $e');
    }
  }

  static CanvasNode _getOrCreateNode(
    String id,
    String? label,
    NodeType type,
    Map<String, CanvasNode> map,
    double x,
    double y,
  ) {
    if (map.containsKey(id)) return map[id]!;

    final actualLabel = (label == null || label.isEmpty) ? id : label;
    CanvasNode node;

    switch (type) {
      case NodeType.diamond:
        node = CanvasNode(
          id: id,
          type: NodeType.diamond,
          x: x,
          y: y,
          width: 140,
          height: 90,
          payload: ShapePayload(
            fill: const Color(0xFFD97706),
            stroke: const Color(0xFFFBBF24),
          ),
        );
        break;

      case NodeType.ellipse:
        node = CanvasNode(
          id: id,
          type: NodeType.ellipse,
          x: x,
          y: y,
          width: 130,
          height: 65,
          payload: ShapePayload(
            fill: const Color(0xFF10B981),
            stroke: const Color(0xFF34D399),
          ),
        );
        break;

      default:
        node = CanvasNode(
          id: id,
          type: NodeType.rectangle,
          x: x,
          y: y,
          width: 140,
          height: 70,
          payload: TextPayload(
            text: actualLabel,
            fontSize: 13,
            color: Colors.white,
          ),
        );
        break;
    }

    map[id] = node;
    return node;
  }

  static List<List<String>> _parseCsv(String source) {
    final rows = <List<String>>[];
    final row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var index = 0; index < source.length; index++) {
      final character = source[index];
      if (character == '"') {
        if (quoted && index + 1 < source.length && source[index + 1] == '"') {
          cell.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (character == ',' && !quoted) {
        row.add(cell.toString().trim());
        cell.clear();
      } else if ((character == '\n' || character == '\r') && !quoted) {
        if (character == '\r' &&
            index + 1 < source.length &&
            source[index + 1] == '\n') {
          index++;
        }
        row.add(cell.toString().trim());
        cell.clear();
        if (row.any((value) => value.isNotEmpty)) {
          rows.add(List<String>.from(row));
        }
        row.clear();
      } else {
        cell.write(character);
      }
    }
    if (cell.length > 0 || row.isNotEmpty) {
      row.add(cell.toString().trim());
      if (row.any((value) => value.isNotEmpty)) {
        rows.add(List<String>.from(row));
      }
    }
    return rows;
  }
}
