import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/assets/data/asset_library_node_factory.dart';
import 'package:varian/features/assets/domain/asset_library.dart';

void main() {
  final now = DateTime.utc(2026, 9, 15);

  test('creates a centered image node with the catalog item ID', () {
    final item = AssetLibraryItem(
      id: 'openverse:hero',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.openverse,
      name: 'Hero',
      downloadUrl: 'https://cdn.example.org/hero.jpg',
      width: 1600,
      height: 900,
      metadata: const {
        'imageArtifactReference': 'varian-image://hero-artifact',
      },
      createdAt: now,
      updatedAt: now,
    );

    final node = AssetLibraryNodeFactory.create(
      item: item,
      nodeId: 'node-1',
      position: const Offset(500, 400),
    );

    expect(node.type, NodeType.image);
    expect(node.bounds.center, const Offset(500, 400));
    expect((node.payload as ImagePayload).assetId, item.id);
    expect(
      (node.payload as ImagePayload).imageArtifactReference,
      'varian-image://hero-artifact',
    );
    expect((node.payload as ImagePayload).url, isNull);
  });

  test('uses the caller-owned manifest identity for a shared catalog item', () {
    final item = AssetLibraryItem(
      id: 'openverse:shared',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.openverse,
      name: 'Shared image',
      downloadUrl: 'https://cdn.example.org/shared.jpg',
      metadata: const {
        'imageArtifactReference': 'varian-image://shared-artifact',
      },
      createdAt: now,
      updatedAt: now,
    );

    final node = AssetLibraryNodeFactory.create(
      item: item,
      nodeId: 'node-1',
      assetId: 'fresh-manifest-id',
      position: const Offset(500, 400),
    );

    expect((node.payload as ImagePayload).assetId, 'fresh-manifest-id');
  });

  test('uses the caller-owned identity in the manifest asset', () {
    final item = AssetLibraryItem(
      id: 'openverse:shared-manifest',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.openverse,
      name: 'Shared image',
      downloadUrl: 'https://cdn.example.org/shared-manifest.jpg',
      metadata: const {
        'imageArtifactReference': 'varian-image://shared-manifest-artifact',
      },
      createdAt: now,
      updatedAt: now,
    );

    final asset = item.toDocumentAsset(
      assetId: 'fresh-manifest-id',
      imageArtifactReference: 'varian-image://shared-manifest-artifact',
    );

    expect(asset.id, 'fresh-manifest-id');
  });

  test('rejects provider and native path sources without materialization', () {
    final item = AssetLibraryItem(
      id: 'upload:portable',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Portable image',
      localPath: 'C:/assets/local.png',
      downloadUrl: 'https://cdn.example.org/portable.png',
      createdAt: now,
      updatedAt: now,
    );

    expect(
      () => AssetLibraryNodeFactory.create(
        item: item,
        nodeId: 'node-1',
        position: const Offset(500, 400),
      ),
      throwsStateError,
    );
  });

  test('maps stable Storage metadata without runtime delivery values', () {
    final item = AssetLibraryItem(
      id: 'upload:storage',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.file,
      source: AssetLibrarySource.upload,
      name: 'Portable file.pdf',
      storagePath: 'project-1/files/file.pdf',
      downloadUrl: 'https://cdn.example.org/file.pdf',
      localPath: 'C:/assets/file.pdf',
      createdAt: now,
      updatedAt: now,
    );

    final node = AssetLibraryNodeFactory.create(
      item: item,
      nodeId: 'node-1',
      position: const Offset(500, 400),
    );
    final payload = node.payload as FilePayload;

    expect(payload.assetId, item.id);
    expect(payload.storagePath, item.storagePath);
    expect(payload.localPath, isNull);
    expect(payload.remoteUrl, isNull);
  });

  test('keeps catalog IDs on every media payload', () {
    final items = [
      AssetLibraryItem(
        id: 'upload:video',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.video,
        source: AssetLibrarySource.upload,
        name: 'Demo.mp4',
        storagePath: 'project-1/media/demo.mp4',
        createdAt: now,
        updatedAt: now,
      ),
      AssetLibraryItem(
        id: 'upload:audio',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.audio,
        source: AssetLibrarySource.upload,
        name: 'Demo.mp3',
        storagePath: 'project-1/media/demo.mp3',
        createdAt: now,
        updatedAt: now,
      ),
      AssetLibraryItem(
        id: 'upload:model',
        scopeId: 'project-1',
        kind: AssetLibraryItemKind.model3d,
        source: AssetLibrarySource.upload,
        name: 'Demo.glb',
        storagePath: 'project-1/models/demo.glb',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final nodes = [
      for (var index = 0; index < items.length; index++)
        AssetLibraryNodeFactory.create(
          item: items[index],
          nodeId: 'node-$index',
          position: const Offset(500, 400),
        ),
    ];

    expect((nodes[0].payload as VideoPayload).assetId, items[0].id);
    expect((nodes[1].payload as AudioPayload).assetId, items[1].id);
    expect((nodes[2].payload as Model3DPayload).assetId, items[2].id);
  });

  test('maps bundled shapes without requiring a binary source', () {
    final item = AssetLibraryItem(
      id: 'bundled:shape-rectangle',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.graphic,
      source: AssetLibrarySource.bundled,
      name: 'Rectangle',
      createdAt: now,
      updatedAt: now,
      metadata: const {'insertNodeType': 'rectangle'},
    );

    final node = AssetLibraryNodeFactory.create(
      item: item,
      nodeId: 'node-1',
      position: const Offset(100, 100),
    );

    expect(node.type, NodeType.rectangle);
    expect((node.payload as ShapePayload).label, 'Rectangle');
  });

  test('rejects missing media sources instead of creating a broken node', () {
    final item = AssetLibraryItem(
      id: 'missing',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.video,
      source: AssetLibrarySource.upload,
      name: 'Missing video',
      status: AssetLibraryItemStatus.missing,
      createdAt: now,
      updatedAt: now,
    );

    expect(
      () => AssetLibraryNodeFactory.create(
        item: item,
        nodeId: 'node-1',
        position: const Offset(100, 100),
      ),
      throwsStateError,
    );
  });

  test('rejects non-ready items even when a stale URL remains', () {
    final item = AssetLibraryItem(
      id: 'syncing',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.remote,
      name: 'Still syncing',
      status: AssetLibraryItemStatus.syncing,
      sourceUrl: 'https://example.org/stale.png',
      createdAt: now,
      updatedAt: now,
    );

    expect(
      () => AssetLibraryNodeFactory.create(
        item: item,
        nodeId: 'node-1',
        position: const Offset(100, 100),
      ),
      throwsStateError,
    );
  });
}
