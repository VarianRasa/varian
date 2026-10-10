import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/model3d_studio.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/domain/document_asset_registry.dart';

void main() {
  test(
    'replacing an existing byte-backed asset advances its manifest version',
    () {
      final now = DateTime.utc(2026, 9, 25);
      final existing = DocumentAsset(
        id: 'asset-1',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'old.png',
        mimeType: 'image/png',
        sizeBytes: 8,
        checksum: 'a' * 64,
        durableReference: 'varian-image://oldasset',
        createdAt: now,
        updatedAt: now,
      );

      final replacement = buildDocumentAsset(
        id: existing.id,
        kind: DocumentAssetKind.image,
        name: 'new.png',
        mimeType: 'image/png',
        artifactReference: 'varian-image://newasset',
        storagePath: null,
        declaredSize: 8,
        bytes: Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
        existing: existing,
      );

      expect(replacement, isNotNull);
      expect(replacement!.id, existing.id);
      expect(replacement.version, 2);
      expect(replacement.createdAt, existing.createdAt);
      expect(replacement.durableReference, 'varian-image://newasset');
    },
  );

  test(
    'stable identity does not mutate an asset referenced by another node',
    () {
      final asset = DocumentAsset(
        id: 'shared-image',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'shared.png',
        mimeType: 'image/png',
        durableReference: 'varian-image://shared',
        createdAt: DateTime.utc(2026, 9, 25),
        updatedAt: DateTime.utc(2026, 9, 25),
      );
      final manifest = DocumentAssetManifest(entries: {asset.id: asset});
      final nodes = <CanvasNode>[
        CanvasNode(
          id: 'other-node',
          type: NodeType.image,
          x: 0,
          y: 0,
          width: 100,
          height: 100,
          payload: ImagePayload(assetId: 'shared-image'),
        ),
      ];

      final id = stableDocumentAssetId(
        candidate: asset.id,
        manifest: manifest,
        nodes: nodes,
        ownerNodeId: 'replacement-node',
      );

      expect(id, isNot(asset.id));
      expect(id, isNotEmpty);
    },
  );

  test(
    'stable identity protects an asset referenced only by durable reference',
    () {
      final asset = DocumentAsset(
        id: 'shared-image',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'shared.png',
        mimeType: 'image/png',
        durableReference: 'varian-image://shared-reference',
        createdAt: DateTime.utc(2026, 9, 25),
        updatedAt: DateTime.utc(2026, 9, 25),
      );
      final otherNode = CanvasNode(
        id: 'other-node',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(
          imageArtifactReference: 'varian-image://shared-reference',
        ),
      );

      final id = stableDocumentAssetId(
        candidate: asset.id,
        manifest: DocumentAssetManifest(entries: {asset.id: asset}),
        nodes: [otherNode],
        ownerNodeId: 'replacement-node',
      );

      expect(id, isNot(asset.id));
    },
  );

  test(
    'fallback identity does not reuse an ID referenced while the manifest is incomplete',
    () {
      final otherNode = CanvasNode(
        id: 'other-node',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(assetId: 'fallback-id'),
      );

      final id = stableDocumentAssetId(
        candidate: null,
        fallback: 'fallback-id',
        manifest: const DocumentAssetManifest(),
        nodes: [otherNode],
        ownerNodeId: 'replacement-node',
      );

      expect(id, isNot('fallback-id'));
    },
  );

  test(
    'does not reuse an ID referenced through remoteUrl-only durable identity',
    () {
      final asset = DocumentAsset(
        id: 'shared-image',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.remote,
        name: 'shared.png',
        mimeType: 'image/png',
        remoteUrl: 'varian-image://remoteonly',
        createdAt: DateTime.utc(2026, 9, 26),
        updatedAt: DateTime.utc(2026, 9, 26),
      );
      final otherNode = CanvasNode(
        id: 'other-node',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(
          imageArtifactReference: 'varian-image://remoteonly',
        ),
      );

      final id = stableDocumentAssetId(
        candidate: asset.id,
        manifest: DocumentAssetManifest(entries: {asset.id: asset}),
        nodes: [otherNode],
        ownerNodeId: 'replacement-node',
      );

      expect(id, isNot(asset.id));
    },
  );

  test(
    'buildDocumentAsset applies the requested identity when replacing an existing record',
    () {
      final existing = DocumentAsset(
        id: 'old-id',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'old.png',
        mimeType: 'image/png',
        durableReference: 'varian-image://old-reference',
        createdAt: DateTime.utc(2026, 9, 25),
        updatedAt: DateTime.utc(2026, 9, 25),
      );

      final replacement = buildDocumentAsset(
        id: 'new-id',
        kind: DocumentAssetKind.image,
        name: 'new.png',
        mimeType: 'image/png',
        artifactReference: 'varian-image://new-reference',
        storagePath: null,
        declaredSize: 0,
        bytes: null,
        existing: existing,
      );

      expect(replacement, isNotNull);
      expect(replacement!.id, 'new-id');
      expect(replacement.version, existing.version + 1);
    },
  );

  test(
    'does not remove a staged asset referenced only by durable reference',
    () {
      final staged = DocumentAsset(
        id: 'staged-model',
        kind: DocumentAssetKind.model3d,
        storage: DocumentAssetStorage.local,
        name: 'replacement.glb',
        mimeType: 'model/gltf-binary',
        durableReference: 'varian-model3d://staged-reference',
        createdAt: DateTime.utc(2026, 9, 25),
        updatedAt: DateTime.utc(2026, 9, 25),
      );
      final node = CanvasNode(
        id: 'model-node',
        type: NodeType.model3d,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: Model3DPayload(artifactReference: staged.durableReference),
      );

      final next = removeUnreferencedDocumentAsset(
        DocumentAssetManifest(entries: {staged.id: staged}),
        stagedAssetId: staged.id,
        nodes: [node],
      );

      expect(next[staged.id], same(staged));
    },
  );

  test(
    'does not remove a staged remote-only asset still referenced by a node',
    () {
      final staged = DocumentAsset(
        id: 'staged-image',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.remote,
        name: 'staged.png',
        mimeType: 'image/png',
        remoteUrl: 'varian-image://stagedremote',
        createdAt: DateTime.utc(2026, 9, 26),
        updatedAt: DateTime.utc(2026, 9, 26),
      );
      final node = CanvasNode(
        id: 'image-node',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(
          imageArtifactReference: 'varian-image://stagedremote',
        ),
      );

      final next = removeUnreferencedDocumentAsset(
        DocumentAssetManifest(entries: {staged.id: staged}),
        stagedAssetId: staged.id,
        nodes: [node],
      );

      expect(next[staged.id], same(staged));
    },
  );

  test('asset identity scanning includes nested component references', () {
    final asset = DocumentAsset(
      id: 'shared-image',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'shared.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://sharednested',
      createdAt: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25),
    );
    final nested = CanvasNode(
      id: 'nested-image',
      type: NodeType.image,
      x: 0,
      y: 0,
      width: 80,
      height: 80,
      payload: ImagePayload(assetId: asset.id),
    );
    final component = CanvasNode(
      id: 'component-node',
      type: NodeType.component,
      x: 0,
      y: 0,
      width: 120,
      height: 120,
      payload: ComponentPayload(
        masterComponentId: 'master-component',
        componentName: 'Nested component',
        templateChildren: [nested],
      ),
    );

    final id = stableDocumentAssetId(
      candidate: asset.id,
      manifest: DocumentAssetManifest(entries: {asset.id: asset}),
      nodes: [component],
      ownerNodeId: 'replacement-node',
    );

    expect(id, isNot(asset.id));
  });

  test(
    'asset identity scanning includes model snapshot manifest references',
    () {
      final asset = DocumentAsset(
        id: 'snapshot-asset',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'snapshot.png',
        mimeType: 'image/png',
        durableReference: 'varian-image://snapshotasset',
        createdAt: DateTime.utc(2026, 9, 25),
        updatedAt: DateTime.utc(2026, 9, 25),
      );
      final node = CanvasNode(
        id: 'model-node',
        type: NodeType.model3d,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: Model3DPayload(
          assetId: 'model-asset',
          snapshots: const [
            Model3DSnapshot(
              id: 'snapshot-1',
              assetId: 'snapshot-asset',
              artifactReference: 'varian-image://snapshotasset',
            ),
          ],
        ),
      );

      final id = stableDocumentAssetId(
        candidate: asset.id,
        manifest: DocumentAssetManifest(entries: {asset.id: asset}),
        nodes: [node],
        ownerNodeId: 'replacement-node',
      );

      expect(id, isNot(asset.id));
    },
  );

  test(
    'staged replacement assets are removed when no node references them',
    () {
      final staged = DocumentAsset(
        id: 'staged-model',
        kind: DocumentAssetKind.model3d,
        storage: DocumentAssetStorage.local,
        name: 'replacement.glb',
        mimeType: 'model/gltf-binary',
        durableReference: 'varian-model3d://replacementasset',
        createdAt: DateTime.utc(2026, 9, 25),
        updatedAt: DateTime.utc(2026, 9, 25),
      );
      final retained = DocumentAsset(
        id: 'current-model',
        kind: DocumentAssetKind.model3d,
        storage: DocumentAssetStorage.local,
        name: 'current.glb',
        mimeType: 'model/gltf-binary',
        durableReference: 'varian-model3d://currentasset',
        createdAt: DateTime.utc(2026, 9, 25),
        updatedAt: DateTime.utc(2026, 9, 25),
      );

      final next = removeUnreferencedDocumentAsset(
        DocumentAssetManifest(
          entries: {staged.id: staged, retained.id: retained},
        ),
        stagedAssetId: staged.id,
        nodes: const [],
      );

      expect(next[staged.id], isNull);
      expect(next[retained.id], same(retained));
    },
  );

  test('rolls back an uncommitted staged Model3D replacement asset', () {
    final staged = DocumentAsset(
      id: 'staged-model',
      kind: DocumentAssetKind.model3d,
      storage: DocumentAssetStorage.local,
      name: 'replacement.glb',
      mimeType: 'model/gltf-binary',
      durableReference: 'varian-model3d://replacementasset',
      createdAt: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25),
    );
    final retained = DocumentAsset(
      id: 'current-model',
      kind: DocumentAssetKind.model3d,
      storage: DocumentAssetStorage.local,
      name: 'current.glb',
      mimeType: 'model/gltf-binary',
      durableReference: 'varian-model3d://currentasset',
      createdAt: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25),
    );

    final next = settleModel3DReplacementManifest(
      manifest: DocumentAssetManifest(
        entries: {staged.id: staged, retained.id: retained},
      ),
      stagedAssetId: staged.id,
      committedAssetId: null,
      nodes: const [],
    );

    expect(next[staged.id], isNull);
    expect(next[retained.id], same(retained));
  });

  test('does not roll back a staged asset still referenced by a node', () {
    final staged = DocumentAsset(
      id: 'staged-model',
      kind: DocumentAssetKind.model3d,
      storage: DocumentAssetStorage.local,
      name: 'replacement.glb',
      mimeType: 'model/gltf-binary',
      durableReference: 'varian-model3d://replacementasset',
      createdAt: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25),
    );
    final node = CanvasNode(
      id: 'replacement-node',
      type: NodeType.model3d,
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      payload: Model3DPayload(assetId: staged.id),
    );

    final next = settleModel3DReplacementManifest(
      manifest: DocumentAssetManifest(entries: {staged.id: staged}),
      stagedAssetId: staged.id,
      committedAssetId: null,
      nodes: [node],
    );

    expect(next[staged.id], same(staged));
  });

  test('keeps the staged ID when it is the committed replacement ID', () {
    final staged = DocumentAsset(
      id: 'staged-model',
      kind: DocumentAssetKind.model3d,
      storage: DocumentAssetStorage.local,
      name: 'replacement.glb',
      mimeType: 'model/gltf-binary',
      durableReference: 'varian-model3d://replacementasset',
      createdAt: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25),
    );

    final next = settleModel3DReplacementManifest(
      manifest: DocumentAssetManifest(entries: {staged.id: staged}),
      stagedAssetId: staged.id,
      committedAssetId: staged.id,
      nodes: const [],
    );

    expect(next[staged.id], same(staged));
  });

  test(
    'commits a replacement with a fresh identity when the current asset is shared',
    () {
      final now = DateTime.utc(2026, 9, 25);
      final staged = DocumentAsset(
        id: 'staged-model',
        kind: DocumentAssetKind.model3d,
        storage: DocumentAssetStorage.local,
        name: 'replacement.glb',
        mimeType: 'model/gltf-binary',
        durableReference: 'varian-model3d://replacementasset',
        createdAt: now,
        updatedAt: now,
      );
      final current = staged.copyWith(
        id: 'current-model',
        name: 'current.glb',
        durableReference: 'varian-model3d://currentasset',
      );
      final otherNode = CanvasNode(
        id: 'other-node',
        type: NodeType.model3d,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: Model3DPayload(assetId: current.id),
      );

      final committed = commitModel3DReplacement(
        manifest: DocumentAssetManifest(
          entries: {staged.id: staged, current.id: current},
        ),
        stagedAssetId: staged.id,
        currentAssetId: current.id,
        nodes: [otherNode],
      );

      expect(committed.assetId, isNot(current.id));
      expect(
        committed.manifest[committed.assetId]?.durableReference,
        staged.durableReference,
      );
      expect(committed.manifest[staged.id], isNull);
      expect(committed.manifest[current.id], same(current));
    },
  );

  test(
    'reuses the current asset identity when only the replaced node references it',
    () {
      final now = DateTime.utc(2026, 9, 25);
      final staged = DocumentAsset(
        id: 'staged-model',
        kind: DocumentAssetKind.model3d,
        storage: DocumentAssetStorage.local,
        name: 'replacement.glb',
        mimeType: 'model/gltf-binary',
        durableReference: 'varian-model3d://replacementasset',
        createdAt: now,
        updatedAt: now,
      );
      final current = staged.copyWith(
        id: 'current-model',
        name: 'current.glb',
        durableReference: 'varian-model3d://currentasset',
      );
      final ownerNode = CanvasNode(
        id: 'owner-node',
        type: NodeType.model3d,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: Model3DPayload(assetId: current.id),
      );

      final committed = commitModel3DReplacement(
        manifest: DocumentAssetManifest(
          entries: {staged.id: staged, current.id: current},
        ),
        stagedAssetId: staged.id,
        currentAssetId: current.id,
        ownerNodeId: ownerNode.id,
        nodes: [ownerNode],
      );

      expect(committed.assetId, current.id);
      expect(
        committed.manifest[current.id]?.durableReference,
        staged.durableReference,
      );
      expect(committed.manifest[current.id]?.createdAt, current.createdAt);
      expect(committed.manifest[staged.id], isNull);
    },
  );

  test('rolls back a prepared replacement when node publication fails', () {
    final now = DateTime.utc(2026, 9, 25);
    final staged = DocumentAsset(
      id: 'staged-model',
      kind: DocumentAssetKind.model3d,
      storage: DocumentAssetStorage.local,
      name: 'replacement.glb',
      mimeType: 'model/gltf-binary',
      durableReference: 'varian-model3d://replacementasset',
      createdAt: now,
      updatedAt: now,
    );
    final current = staged.copyWith(
      id: 'current-model',
      name: 'current.glb',
      durableReference: 'varian-model3d://currentasset',
    );
    final otherNode = CanvasNode(
      id: 'other-node',
      type: NodeType.model3d,
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      payload: Model3DPayload(assetId: current.id),
    );
    final originalManifest = DocumentAssetManifest(
      entries: {staged.id: staged, current.id: current},
    );
    final committed = commitModel3DReplacement(
      manifest: originalManifest,
      stagedAssetId: staged.id,
      currentAssetId: current.id,
      nodes: [otherNode],
    );
    var activeManifest = originalManifest;

    expect(
      () => publishModel3DReplacement(
        originalManifest: originalManifest,
        stagedAssetId: staged.id,
        committedManifest: committed.manifest,
        nodes: [otherNode],
        setManifest: (next) => activeManifest = next,
        publishNode: () => throw StateError('node publication failed'),
      ),
      throwsStateError,
    );

    expect(activeManifest[staged.id], isNull);
    expect(activeManifest[current.id], same(current));
    expect(activeManifest[committed.assetId], isNull);
  });

  test('snapshot completion is rejected when the model source changed', () {
    final captured = CanvasNode(
      id: 'model-node',
      type: NodeType.model3d,
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      payload: Model3DPayload(
        assetId: 'old-model',
        artifactReference: 'varian-model3d://oldmodel',
      ),
    );
    final current = captured.copyWith(
      payload: (captured.payload as Model3DPayload).copyWith(
        assetId: 'new-model',
        artifactReference: 'varian-model3d://newmodel',
      ),
    );

    expect(
      canCommitModel3DSnapshot(capturedNode: captured, currentNode: current),
      isFalse,
    );
  });

  test(
    'asset replacement completion requires the original source and session',
    () {
      final captured = CanvasNode(
        id: 'image-node',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(
          assetId: 'old-image',
          imageArtifactReference: 'varian-image://oldimage',
        ),
      );

      expect(
        canCommitDocumentAssetReplacement(
          capturedNode: captured,
          currentNode: captured,
          operationProjectId: 'project-1',
          currentProjectId: 'project-1',
          expectedAccountId: 'account-1',
          currentAccountId: 'account-1',
        ),
        isTrue,
      );
      expect(
        canCommitDocumentAssetReplacement(
          capturedNode: captured,
          currentNode: captured.copyWith(
            payload: (captured.payload as ImagePayload).copyWith(
              caption: 'edited while picker was open',
            ),
          ),
          operationProjectId: 'project-1',
          currentProjectId: 'project-1',
          expectedAccountId: 'account-1',
          currentAccountId: 'account-1',
        ),
        isFalse,
      );
      expect(
        canCommitDocumentAssetReplacement(
          capturedNode: captured,
          currentNode: captured,
          operationProjectId: 'project-1',
          currentProjectId: 'project-2',
          expectedAccountId: 'account-1',
          currentAccountId: 'account-1',
        ),
        isFalse,
      );
      expect(
        canCommitDocumentAssetReplacement(
          capturedNode: captured,
          currentNode: captured,
          operationProjectId: 'project-1',
          currentProjectId: 'project-1',
          expectedAccountId: 'account-1',
          currentAccountId: 'account-2',
        ),
        isFalse,
      );
    },
  );

  test(
    'dropped image producer keeps node, payload, and manifest identity fenced',
    () {
      final bytes = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
      final node = CanvasNode(
        id: 'dropped-image',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(
          assetId: 'dropped-image',
          imageArtifactReference: 'varian-image://droppedimage',
        ),
      );
      final asset = buildDocumentAsset(
        id: node.id,
        kind: DocumentAssetKind.image,
        name: 'dropped.png',
        mimeType: 'image/png',
        artifactReference:
            (node.payload as ImagePayload).imageArtifactReference,
        storagePath: null,
        declaredSize: bytes.length,
        bytes: bytes,
      );

      expect(asset, isNotNull);
      expect(asset!.id, node.id);
      expect((node.payload as ImagePayload).assetId, asset.id);
      expect(
        canCommitArtifactProducer(
          operationGeneration: 4,
          currentGeneration: 4,
          operationProjectId: 'project-1',
          currentProjectId: 'project-1',
          expectedAccountId: 'account-1',
          currentAccountId: 'account-1',
        ),
        isTrue,
      );
      expect(
        canCommitArtifactProducer(
          operationGeneration: 4,
          currentGeneration: 5,
          operationProjectId: 'project-1',
          currentProjectId: 'project-1',
          expectedAccountId: 'account-1',
          currentAccountId: 'account-1',
        ),
        isFalse,
      );
      expect(
        canCommitArtifactProducer(
          operationGeneration: 4,
          currentGeneration: 4,
          operationProjectId: 'project-1',
          currentProjectId: 'project-2',
          expectedAccountId: 'account-1',
          currentAccountId: 'account-1',
        ),
        isFalse,
      );
    },
  );

  test('rolls back a producer manifest when node publication fails', () {
    final original = DocumentAssetManifest(
      entries: {
        'existing': DocumentAsset(
          id: 'existing',
          kind: DocumentAssetKind.image,
          storage: DocumentAssetStorage.local,
          name: 'existing.png',
          mimeType: 'image/png',
          durableReference: 'varian-image://existingasset',
          createdAt: DateTime.utc(2026, 9, 25),
          updatedAt: DateTime.utc(2026, 9, 25),
        ),
      },
    );
    final produced = DocumentAsset(
      id: 'produced',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'produced.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://producedasset',
      createdAt: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25),
    );
    var activeManifest = original;

    expect(
      () => publishDocumentAssetAndNode(
        originalManifest: original,
        committedManifest: original.upsert(produced),
        setManifest: (next) => activeManifest = next,
        publishNode: () => throw StateError('node publication failed'),
      ),
      throwsStateError,
    );

    expect(activeManifest, same(original));
    expect(activeManifest['produced'], isNull);
    expect(activeManifest['existing'], same(original['existing']));
  });

  test('prepared model producers carry the byte-backed manifest asset', () {
    final bytes = Uint8List.fromList(<int>[0, 1, 2, 3]);
    final node = CanvasNode(
      id: 'prepared-model',
      type: NodeType.model3d,
      x: 0,
      y: 0,
      width: 320,
      height: 240,
      payload: Model3DPayload(
        fileName: 'scene.glb',
        assetId: 'prepared-model',
        artifactReference: 'varian-model3d://preparedmodel',
      ),
    );
    final asset = buildDocumentAsset(
      id: node.id,
      kind: DocumentAssetKind.model3d,
      name: 'scene.glb',
      mimeType: 'model/gltf-binary',
      artifactReference: 'varian-model3d://preparedmodel',
      storagePath: null,
      declaredSize: bytes.length,
      bytes: bytes,
    );

    final prepared = PreparedDocumentAssetNode(node: node, asset: asset!);

    expect(prepared.node.id, prepared.asset.id);
    expect(prepared.asset.sizeBytes, bytes.length);
    expect(prepared.asset.checksum, isNotNull);
  });

  test('buildDocumentAsset preserves safe catalog metadata', () {
    final asset = buildDocumentAsset(
      id: 'catalog-node',
      kind: DocumentAssetKind.image,
      name: 'catalog.png',
      mimeType: 'image/png',
      artifactReference: 'varian-image://catalogimage',
      storagePath: null,
      declaredSize: 8,
      bytes: Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
      metadata: const {
        'libraryItemId': 'catalog-item',
        'scopeId': 'project-1',
        'source': 'openverse',
        'attribution': 'Artist',
        'width': 640,
        'height': 480,
        'durationMs': 0,
        'providerAssetId': 'provider-1',
      },
    );

    expect(asset, isNotNull);
    expect(asset!.metadata, {
      'libraryItemId': 'catalog-item',
      'scopeId': 'project-1',
      'source': 'openverse',
      'attribution': 'Artist',
      'width': 640,
      'height': 480,
      'durationMs': 0,
      'providerAssetId': 'provider-1',
    });
  });
}
