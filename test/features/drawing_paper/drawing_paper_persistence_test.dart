import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_persistence.dart';
import 'package:varian/features/drawing_paper/domain/services/raster_asset_store.dart';

class _MemoryRasterAssetStore implements RasterAssetStore {
  final assets = <String, Uint8List>{};
  int writes = 0;
  bool failWrites = false;
  bool failReads = false;

  @override
  Future<bool> contains(String reference) async =>
      assets.containsKey(reference);

  @override
  Future<void> delete(String reference) async {
    assets.remove(reference);
  }

  @override
  Future<Uint8List?> read(String reference) async {
    if (failReads) throw StateError('read failed');
    final bytes = assets[reference];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> write(String reference, Uint8List bytes) async {
    writes++;
    if (failWrites) throw StateError('write failed');
    assets[reference] = Uint8List.fromList(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'local document save stores a revisioned Drawing Paper preview ref',
    () async {
      final assets = _MemoryRasterAssetStore();
      final storage = LocalStorageService(
        drawingPaperPersistence: DrawingPaperPersistence(assetStore: assets),
      );
      final payload = DrawingPaperPayload(
        pixelWidth: 32,
        pixelHeight: 24,
        layers: const [
          DrawingLayer(
            id: 'ink',
            name: 'Ink',
            shapes: [
              VectorShapeObject(
                id: 'shape',
                kind: ShapeKind.rectangle,
                points: [Offset(4, 4), Offset(16, 16)],
                fill: Colors.red,
              ),
            ],
          ),
        ],
        studioPages: [
          DrawingPaperPage(
            id: 'child-page',
            position: const Offset(32, 0),
            payload: DrawingPaperPayload(
              pixelWidth: 32,
              pixelHeight: 24,
              layers: const [
                DrawingLayer(
                  id: 'child-ink',
                  name: 'Child ink',
                  shapes: [
                    VectorShapeObject(
                      id: 'child-shape',
                      kind: ShapeKind.rectangle,
                      points: [Offset(4, 4), Offset(16, 16)],
                      fill: Colors.blue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
      final document = CanvasDocument(
        projectId: 'persistence-test',
        nodes: [
          CanvasNode(
            id: 'paper_node',
            type: NodeType.drawingPaper,
            x: 0,
            y: 0,
            width: 320,
            height: 240,
            payload: payload,
          ),
        ],
        updatedAt: DateTime.now(),
      );

      expect(await storage.saveDocument(document), LocalSaveResult.full);

      final loaded = await storage.loadDocument(document.projectId);
      final loadedPayload = loaded!.nodes.single.payload as DrawingPaperPayload;
      expect(loadedPayload.rasterDocumentId, 'paper_node');
      // Raster cache references are local runtime metadata and are not part
      // of the portable document envelope. Editable content remains durable.
      expect(loadedPayload.compositePreviewRef, isNull);
      expect(assets.assets.keys.single, startsWith('raster://paper_node/0/'));
      expect(loadedPayload.studioPages, hasLength(1));
      expect(
        loadedPayload.studioPages.single.payload.layers.single.shapes.single.id,
        'child-shape',
      );
    },
  );

  test(
    'rebuilds a missing or stale preview cache from editable content',
    () async {
      final assets = _MemoryRasterAssetStore();
      final persistence = DrawingPaperPersistence(assetStore: assets);
      final payload = DrawingPaperPayload(pixelWidth: 20, pixelHeight: 20);

      final first = await persistence.preparePayload(payload, nodeId: 'paper');
      final firstReference = first.compositePreviewRef!;
      expect(firstReference, startsWith('raster://paper/0/'));
      expect(assets.writes, 1);

      await persistence.preparePayload(first, nodeId: 'paper');
      expect(assets.writes, 1);

      await assets.delete(first.compositePreviewRef!);
      await persistence.preparePayload(first, nodeId: 'paper');
      expect(assets.writes, 2);

      final next = await persistence.preparePayload(
        first.copyWith(rasterRevision: 1),
        nodeId: 'paper',
      );
      expect(next.compositePreviewRef, startsWith('raster://paper/1/'));
      expect(next.compositePreviewRef, isNot(firstReference));
      expect(assets.writes, 3);
    },
  );

  test('invalidates the preview reference when a child page changes', () async {
    final assets = _MemoryRasterAssetStore();
    final persistence = DrawingPaperPersistence(assetStore: assets);
    final payload = DrawingPaperPayload(
      pixelWidth: 20,
      pixelHeight: 20,
      layers: const [DrawingLayer(id: 'root', name: 'Root')],
      studioPages: [
        DrawingPaperPage(
          id: 'child',
          position: const Offset(20, 0),
          payload: DrawingPaperPayload(
            pixelWidth: 20,
            pixelHeight: 20,
            layers: const [DrawingLayer(id: 'child-layer', name: 'Child')],
          ),
        ),
      ],
    );

    final first = await persistence.preparePayload(payload, nodeId: 'paper');
    final changed = first.copyWith(
      studioPages: [
        first.studioPages.single.copyWith(
          payload: first.studioPages.single.payload.copyWith(
            layers: const [
              DrawingLayer(
                id: 'child-layer',
                name: 'Child',
                shapes: [
                  VectorShapeObject(
                    id: 'child-shape',
                    kind: ShapeKind.rectangle,
                    points: [Offset(2, 2), Offset(18, 18)],
                    fill: Colors.blue,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final second = await persistence.preparePayload(changed, nodeId: 'paper');

    expect(second.compositePreviewRef, isNot(first.compositePreviewRef));
    expect(assets.writes, 2);
  });

  test('keeps editable content when preview storage fails', () async {
    final assets = _MemoryRasterAssetStore()..failWrites = true;
    final persistence = DrawingPaperPersistence(assetStore: assets);
    final prepared = await persistence.preparePayload(
      DrawingPaperPayload(pixelWidth: 20, pixelHeight: 20),
      nodeId: 'paper',
    );

    expect(prepared.rasterDocumentId, 'paper');
    expect(prepared.compositePreviewRef, isNull);
  });

  test(
    'local save falls back to editable JSON when preview storage fails',
    () async {
      final assets = _MemoryRasterAssetStore()..failWrites = true;
      final storage = LocalStorageService(
        drawingPaperPersistence: DrawingPaperPersistence(assetStore: assets),
      );
      final document = CanvasDocument(
        projectId: 'fallback-test',
        nodes: [
          CanvasNode(
            id: 'paper',
            type: NodeType.drawingPaper,
            x: 0,
            y: 0,
            width: 20,
            height: 20,
            payload: DrawingPaperPayload(pixelWidth: 20, pixelHeight: 20),
          ),
        ],
        updatedAt: DateTime.now(),
      );

      expect(await storage.saveDocument(document), LocalSaveResult.full);

      final loaded = await storage.loadDocument(document.projectId);
      final loadedPayload = loaded!.nodes.single.payload as DrawingPaperPayload;
      expect(loadedPayload.rasterDocumentId, 'paper');
      expect(loadedPayload.compositePreviewRef, isNull);
    },
  );

  test('preview reads return null when the cache adapter fails', () async {
    final assets = _MemoryRasterAssetStore();
    final persistence = DrawingPaperPersistence(assetStore: assets);
    final prepared = await persistence.preparePayload(
      DrawingPaperPayload(pixelWidth: 20, pixelHeight: 20),
      nodeId: 'paper',
    );
    assets.failReads = true;

    expect(await persistence.readPreview(prepared), isNull);
  });
}
