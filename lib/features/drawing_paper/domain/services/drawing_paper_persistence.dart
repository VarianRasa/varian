import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/node.dart';

import 'drawing_paper_renderer.dart';
import 'raster_asset_store.dart';

class DrawingPaperPersistence {
  final RasterAssetStore assetStore;

  DrawingPaperPersistence({RasterAssetStore? assetStore})
    : assetStore = assetStore ?? createDefaultRasterAssetStore();

  Future<CanvasDocument> prepareDocument(CanvasDocument document) async {
    final nodes = <CanvasNode>[];
    for (final node in document.nodes) {
      final payload = node.payload;
      if (payload is! DrawingPaperPayload) {
        nodes.add(node);
        continue;
      }
      final prepared = await preparePayload(payload, nodeId: node.id);
      nodes.add(node.copyWith(payload: prepared));
    }
    return document.copyWith(nodes: nodes);
  }

  Future<DrawingPaperPayload> preparePayload(
    DrawingPaperPayload payload, {
    required String nodeId,
  }) async {
    final documentId = payload.rasterDocumentId.isEmpty
        ? nodeId
        : payload.rasterDocumentId;
    final reference = previewReferenceForPayload(payload, nodeId: nodeId);
    try {
      if (payload.compositePreviewRef == reference &&
          await assetStore.contains(reference)) {
        return payload.rasterDocumentId == documentId
            ? payload
            : payload.copyWith(rasterDocumentId: documentId);
      }

      final bytes = await DrawingPaperRenderer.renderPng(payload);
      if (bytes == null) {
        return payload.copyWith(
          rasterDocumentId: documentId,
          compositePreviewRef: null,
        );
      }
      await assetStore.write(reference, bytes);
      return payload.copyWith(
        rasterDocumentId: documentId,
        compositePreviewRef: reference,
      );
    } catch (_) {
      return payload.copyWith(
        rasterDocumentId: documentId,
        compositePreviewRef: null,
      );
    }
  }

  Future<Uint8List?> readPreview(DrawingPaperPayload payload) async {
    final reference = payload.compositePreviewRef;
    if (reference == null || reference.isEmpty) return null;
    try {
      return await assetStore.read(reference);
    } catch (_) {
      return null;
    }
  }

  static String previewReferenceForPayload(
    DrawingPaperPayload payload, {
    required String nodeId,
  }) {
    final documentId = payload.rasterDocumentId.isEmpty
        ? nodeId
        : payload.rasterDocumentId;
    final fingerprint = _fingerprint(
      payload.copyWith(rasterDocumentId: documentId, compositePreviewRef: null),
    );
    return previewReference(documentId, payload.rasterRevision, fingerprint);
  }

  static String _fingerprint(DrawingPaperPayload payload) => sha256
      .convert(utf8.encode(jsonEncode(payload.toJson())))
      .toString()
      .substring(0, 16);

  static String previewReference(
    String documentId,
    int revision,
    String fingerprint,
  ) => 'raster://$documentId/$revision/$fingerprint/preview.png';
}
