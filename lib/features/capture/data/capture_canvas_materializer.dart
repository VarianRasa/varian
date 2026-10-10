import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/durable_asset_reference.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/features/ai/data/video_media_validation.dart';
import 'package:varian/features/canvas/domain/document_asset_registry.dart';
import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/assets/data/file_artifact_store_types.dart';
import 'package:varian/features/link_card/domain/link_url_policy.dart';
import 'package:varian/features/media/data/media_artifact_store_types.dart';

import '../domain/capture_item.dart';

Future<PreparedCaptureCanvasNode> materializeCaptureCanvasNode({
  required CaptureItem capture,
  required Offset center,
  required String nodeId,
  required Uint8List? bytes,
  required ImageArtifactStore imageStore,
  required FileArtifactStore fileStore,
  required MediaArtifactStore mediaStore,
}) async {
  if (capture.kind == CaptureKind.text || capture.kind == CaptureKind.link) {
    return prepareCaptureCanvasNode(
      capture: capture,
      center: center,
      nodeId: nodeId,
    );
  }
  final contentBytes = _requireBytes(bytes);
  final fileName = _fileName(capture);
  final mimeType = capture.mimeType?.trim().isNotEmpty == true
      ? capture.mimeType!.trim().toLowerCase()
      : inferAssetMimeType(fileName);

  try {
    switch (capture.kind) {
      case CaptureKind.text:
      case CaptureKind.link:
        throw const CaptureCanvasMaterializationException();
      case CaptureKind.image:
      case CaptureKind.screenshot:
        if (!mimeType.startsWith('image/') ||
            !assetBytesMatchMimeSignature(contentBytes, mimeType) ||
            !isValidImageBytes(contentBytes)) {
          throw const CaptureCanvasMaterializationException();
        }
        final artifact = await imageStore.save(
          contentBytes,
          fileName: fileName,
        );
        final reference = validImageArtifactReference(artifact.reference);
        if (reference == null) {
          throw const CaptureCanvasMaterializationException();
        }
        return prepareCaptureCanvasNode(
          capture: capture,
          center: center,
          nodeId: nodeId,
          bytes: contentBytes,
          artifactReference: reference,
          sourceMimeType: mimeType,
          ownedFileName: fileName,
        );
      case CaptureKind.audio:
        if (!mimeType.startsWith('audio/') ||
            !assetBytesMatchMimeSignature(contentBytes, mimeType)) {
          throw const CaptureCanvasMaterializationException();
        }
        final artifact = await mediaStore.save(
          contentBytes,
          kind: MediaArtifactKind.original,
          mimeType: mimeType,
          checksum: sha256.convert(contentBytes).toString(),
          fileName: fileName,
          storagePolicy: MediaStoragePolicy.durable,
        );
        final reference = validMediaArtifactReference(artifact.reference);
        if (reference == null) {
          throw const CaptureCanvasMaterializationException();
        }
        return prepareCaptureCanvasNode(
          capture: capture,
          center: center,
          nodeId: nodeId,
          bytes: contentBytes,
          artifactReference: reference,
          sourceMimeType: mimeType,
          ownedFileName: fileName,
        );
      case CaptureKind.file:
        if (!assetBytesMatchMimeSignature(contentBytes, mimeType)) {
          throw const CaptureCanvasMaterializationException();
        }
        final artifact = await fileStore.save(contentBytes, fileName: fileName);
        final reference = validFileArtifactReference(artifact.reference);
        if (reference == null) {
          throw const CaptureCanvasMaterializationException();
        }
        return prepareCaptureCanvasNode(
          capture: capture,
          center: center,
          nodeId: nodeId,
          bytes: contentBytes,
          artifactReference: reference,
          sourceMimeType: mimeType,
          ownedFileName: fileName,
        );
    }
  } on CaptureCanvasMaterializationException {
    rethrow;
  } on ImageArtifactStoreException {
    throw const CaptureCanvasMaterializationException();
  } on FileArtifactStoreException {
    throw const CaptureCanvasMaterializationException();
  } on MediaArtifactStoreException {
    throw const CaptureCanvasMaterializationException();
  }
}

class PreparedCaptureCanvasNode {
  const PreparedCaptureCanvasNode({required this.node, this.asset});

  final CanvasNode node;
  final DocumentAsset? asset;
}

/// Creates a canvas node from a local Inbox item and already-owned bytes.
/// Binary contents and capture-store references never enter canvas JSON.
PreparedCaptureCanvasNode prepareCaptureCanvasNode({
  required CaptureItem capture,
  required Offset center,
  required String nodeId,
  Uint8List? bytes,
  String? artifactReference,
  String? sourceMimeType,
  String? ownedFileName,
}) {
  final id = nodeId.trim();
  if (id.isEmpty || id != nodeId) {
    throw ArgumentError.value(nodeId, 'nodeId', 'Node ID must be non-empty.');
  }
  final title = capture.title?.trim().isNotEmpty == true
      ? capture.title!.trim()
      : switch (capture.kind) {
          CaptureKind.text => 'Captured text',
          CaptureKind.link => 'Captured link',
          CaptureKind.image || CaptureKind.screenshot => 'Captured image',
          CaptureKind.audio => 'Captured audio',
          CaptureKind.file => 'Captured file',
        };
  final content = capture.text?.trim() ?? '';

  switch (capture.kind) {
    case CaptureKind.text:
      if (content.isEmpty) throw const CaptureCanvasMaterializationException();
      final node = CanvasNode(
        id: id,
        type: NodeType.text,
        x: center.dx - 140,
        y: center.dy - 60,
        width: 280,
        height: 120,
        name: title,
        payload: TextPayload(text: content),
      );
      return PreparedCaptureCanvasNode(node: node);
    case CaptureKind.link:
      final rawUrl = capture.sourceUri ?? content;
      final Uri uri;
      try {
        uri = normalizeLinkUrl(rawUrl);
      } on LinkUrlValidationException {
        throw const CaptureCanvasMaterializationException();
      }
      final node = CanvasNode(
        id: id,
        type: NodeType.linkCard,
        x: center.dx - 150,
        y: center.dy - 80,
        width: 300,
        height: 160,
        name: title,
        payload: LinkPayload(
          title: title,
          url: uri.toString(),
          description: capture.linkMetadata?.description,
          siteName: capture.linkMetadata?.siteName,
          mediaType: capture.linkMetadata?.mediaType ?? 'webpage',
        ),
      );
      return PreparedCaptureCanvasNode(node: node);
    case CaptureKind.image:
    case CaptureKind.screenshot:
      final contentBytes = _requireBytes(bytes);
      final reference = validImageArtifactReference(artifactReference);
      if (reference == null) {
        throw const CaptureCanvasMaterializationException();
      }
      final mimeType = sourceMimeType ?? _imageMimeType(capture);
      if (!mimeType.startsWith('image/') ||
          !assetBytesMatchMimeSignature(contentBytes, mimeType)) {
        throw const CaptureCanvasMaterializationException();
      }
      final asset = _asset(
        id: id,
        kind: DocumentAssetKind.image,
        name:
            ownedFileName ??
            capture.title ??
            'capture.${_extension(capture, 'png')}',
        mimeType: mimeType,
        reference: reference,
        bytes: contentBytes,
      );
      return PreparedCaptureCanvasNode(
        asset: asset,
        node: CanvasNode(
          id: id,
          type: NodeType.image,
          x: center.dx - 160,
          y: center.dy - 120,
          width: 320,
          height: 240,
          name: title,
          payload: ImagePayload(
            assetId: id,
            imageArtifactReference: reference,
            mimeType: mimeType,
            byteLength: contentBytes.length,
            caption: capture.title,
          ),
        ),
      );
    case CaptureKind.audio:
      final contentBytes = _requireBytes(bytes);
      final reference = validMediaArtifactReference(artifactReference);
      final mimeType = sourceMimeType ?? _audioMimeType(capture);
      if (!mimeType.startsWith('audio/') ||
          !assetBytesMatchMimeSignature(contentBytes, mimeType)) {
        throw const CaptureCanvasMaterializationException();
      }
      if (reference == null ||
          mediaStoragePolicyFromReference(reference) !=
              MediaStoragePolicy.durable ||
          mediaArtifactKindFromReference(reference) !=
              MediaArtifactKind.original) {
        throw const CaptureCanvasMaterializationException();
      }
      final asset = _asset(
        id: id,
        kind: DocumentAssetKind.audio,
        name:
            ownedFileName ??
            capture.title ??
            'capture.${_extension(capture, 'mp3')}',
        mimeType: mimeType,
        reference: reference,
        bytes: contentBytes,
      );
      return PreparedCaptureCanvasNode(
        asset: asset,
        node: CanvasNode(
          id: id,
          type: NodeType.audioCard,
          x: center.dx - 120,
          y: center.dy - 40,
          width: 240,
          height: 80,
          name: title,
          payload: AudioPayload(
            trackName: title,
            assetId: id,
            audioArtifactReference: reference,
          ),
        ),
      );
    case CaptureKind.file:
      final contentBytes = _requireBytes(bytes);
      final reference = validFileArtifactReference(artifactReference);
      if (reference == null) {
        throw const CaptureCanvasMaterializationException();
      }
      final fileName = ownedFileName ?? _fileName(capture);
      final mimeType =
          sourceMimeType ?? capture.mimeType ?? inferAssetMimeType(fileName);
      final asset = _asset(
        id: id,
        kind: DocumentAssetKind.document,
        name: fileName,
        mimeType: mimeType,
        reference: reference,
        bytes: contentBytes,
      );
      return PreparedCaptureCanvasNode(
        asset: asset,
        node: CanvasNode(
          id: id,
          type: NodeType.fileCard,
          x: center.dx - 140,
          y: center.dy - 90,
          width: 280,
          height: 180,
          name: title,
          payload: FilePayload(
            fileName: fileName,
            fileExtension: _extension(capture, 'FILE').toUpperCase(),
            fileSizeText: _sizeLabel(contentBytes.length),
            assetId: id,
            artifactReference: reference,
          ),
        ),
      );
  }
}

DocumentAsset _asset({
  required String id,
  required DocumentAssetKind kind,
  required String name,
  required String mimeType,
  required String reference,
  required Uint8List bytes,
}) {
  final asset = buildDocumentAsset(
    id: id,
    kind: kind,
    name: name,
    mimeType: mimeType,
    artifactReference: reference,
    storagePath: null,
    declaredSize: bytes.lengthInBytes,
    bytes: bytes,
  );
  if (asset == null || asset.durableReference == null) {
    throw const CaptureCanvasMaterializationException();
  }
  return asset;
}

Uint8List _requireBytes(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) {
    throw const CaptureCanvasMaterializationException();
  }
  return bytes;
}

String _fileName(CaptureItem capture) {
  final candidate = capture.title?.trim().isNotEmpty == true
      ? capture.title!.trim()
      : 'capture.${_extension(capture, 'bin')}';
  return sanitizeFileArtifactName(candidate);
}

String _extension(CaptureItem capture, String fallback) {
  final value = capture.extension?.trim().replaceFirst(RegExp(r'^\.'), '');
  if (value != null && RegExp(r'^[A-Za-z0-9]{1,16}$').hasMatch(value)) {
    return value.toLowerCase();
  }
  final title = capture.title?.trim() ?? '';
  final dot = title.lastIndexOf('.');
  if (dot > 0 && dot < title.length - 1) {
    final extension = title.substring(dot + 1);
    if (RegExp(r'^[A-Za-z0-9]{1,16}$').hasMatch(extension)) {
      return extension.toLowerCase();
    }
  }
  return fallback;
}

String _imageMimeType(CaptureItem capture) {
  final value = capture.mimeType?.trim().toLowerCase();
  if (value != null && value.startsWith('image/')) return value;
  final name = capture.title ?? 'capture.${_extension(capture, 'png')}';
  return inferAssetMimeType(name, fallback: 'image/png');
}

String _audioMimeType(CaptureItem capture) {
  final value = capture.mimeType?.trim().toLowerCase();
  if (value != null && value.startsWith('audio/')) return value;
  return inferAssetMimeType(
    capture.title ?? 'capture.${_extension(capture, 'mp3')}',
    fallback: 'audio/mpeg',
  );
}

String _sizeLabel(int size) {
  if (size < 1024) return '$size B';
  if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
  return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class CaptureCanvasMaterializationException implements Exception {
  const CaptureCanvasMaterializationException();

  @override
  String toString() => 'Capture cannot be added to this canvas.';
}

/// Convenience for generating a fresh canvas identity at the commit boundary.
String newCaptureCanvasNodeId() => const Uuid().v4();
