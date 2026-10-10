import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/import/import_merge_planner.dart';

void main() {
  test('filters dangling edges and remaps conflicting IDs', () {
    final plan = ImportMergePlanner.plan(
      importedNodes: [_node('shape'), _node('other')],
      importedEdges: const [
        CanvasEdge(id: 'edge', sourceNodeId: 'shape', targetNodeId: 'other'),
        CanvasEdge(
          id: 'dangling',
          sourceNodeId: 'shape',
          targetNodeId: 'missing',
        ),
      ],
      existingNodeIds: const ['shape'],
      existingEdgeIds: const ['edge'],
      collisionPrefix: 'copy',
    );

    expect(plan.skippedDanglingEdges, 1);
    expect(plan.remappedConflicts, isTrue);
    expect(plan.nodes.map((node) => node.id), ['copy-shape', 'copy-other']);
    expect(plan.edges.single.id, 'copy-edge');
    expect(plan.edges.single.sourceNodeId, 'copy-shape');
    expect(plan.edges.single.targetNodeId, 'copy-other');
  });

  test('remaps colliding imported asset IDs and rewrites node references', () {
    final now = DateTime.utc(2026, 9, 26);
    final existing = DocumentAsset(
      id: 'shared',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'existing.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://existing',
      createdAt: now,
      updatedAt: now,
    );
    final imported = existing.copyWith(
      name: 'imported.png',
      durableReference: 'varian-image://imported',
    );
    final plan = ImportMergePlanner.plan(
      importedNodes: [_imageNode('image-node', assetId: 'shared')],
      importedEdges: const [],
      existingNodeIds: const [],
      existingEdgeIds: const [],
      existingAssets: DocumentAssetManifest(entries: {existing.id: existing}),
      importedAssets: DocumentAssetManifest(entries: {imported.id: imported}),
      collisionPrefix: 'copy',
    );

    expect(plan.assets['shared']!.name, 'existing.png');
    expect(plan.assets['copy-asset-shared']!.name, 'imported.png');
    expect(
      (plan.nodes.single.payload as ImagePayload).assetId,
      'copy-asset-shared',
    );
  });

  test('rejects imported manifests whose keys disagree with asset IDs', () {
    final now = DateTime.utc(2026, 9, 26);
    final asset = DocumentAsset(
      id: 'asset-id',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'image.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://assetidentity',
      createdAt: now,
      updatedAt: now,
    );

    expect(
      () => ImportMergePlanner.plan(
        importedNodes: [_imageNode('image-node', assetId: 'manifest-key')],
        importedEdges: const [],
        existingNodeIds: const [],
        existingEdgeIds: const [],
        importedAssets: DocumentAssetManifest(entries: {'manifest-key': asset}),
      ),
      throwsFormatException,
    );
  });

  test('rejects asset dependency checks on malformed manifest identities', () {
    final now = DateTime.utc(2026, 9, 26);
    final asset = DocumentAsset(
      id: 'asset-id',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'image.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://assetidentity',
      createdAt: now,
      updatedAt: now,
    );

    expect(
      () => ImportMergePlanner.unresolvedDependencies(
        nodes: [_imageNode('image-node', assetId: 'manifest-key')],
        assets: DocumentAssetManifest(entries: {'manifest-key': asset}),
      ),
      throwsFormatException,
    );
  });

  test('remaps duplicateOf when its imported asset ID collides', () {
    final now = DateTime.utc(2026, 9, 26);
    final existing = DocumentAsset(
      id: 'shared',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'existing.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://existing',
      createdAt: now,
      updatedAt: now,
    );
    final importedShared = existing.copyWith(
      name: 'imported.png',
      durableReference: 'varian-image://imported',
    );
    final importedChild = existing.copyWith(
      id: 'child',
      name: 'child.png',
      durableReference: 'varian-image://child',
      duplicateOf: 'shared',
    );

    final plan = ImportMergePlanner.plan(
      importedNodes: const [],
      importedEdges: const [],
      existingNodeIds: const [],
      existingEdgeIds: const [],
      existingAssets: DocumentAssetManifest(entries: {existing.id: existing}),
      importedAssets: DocumentAssetManifest(
        entries: {
          importedShared.id: importedShared,
          importedChild.id: importedChild,
        },
      ),
      collisionPrefix: 'copy',
    );

    expect(plan.assets['child']!.duplicateOf, 'copy-asset-shared');
  });

  test('remaps duplicateOf independently of imported asset order', () {
    final now = DateTime.utc(2026, 9, 26);
    final existing = DocumentAsset(
      id: 'shared',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'existing.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://existing',
      createdAt: now,
      updatedAt: now,
    );
    final importedShared = existing.copyWith(
      name: 'imported.png',
      durableReference: 'varian-image://imported',
    );
    final importedChild = existing.copyWith(
      id: 'child',
      name: 'child.png',
      durableReference: 'varian-image://child',
      duplicateOf: 'shared',
    );

    final plan = ImportMergePlanner.plan(
      importedNodes: const [],
      importedEdges: const [],
      existingNodeIds: const [],
      existingEdgeIds: const [],
      existingAssets: DocumentAssetManifest(entries: {existing.id: existing}),
      importedAssets: DocumentAssetManifest(
        entries: {
          importedChild.id: importedChild,
          importedShared.id: importedShared,
        },
      ),
      collisionPrefix: 'copy',
    );

    expect(plan.assets['child']!.duplicateOf, 'copy-asset-shared');
  });

  test('rejects unresolved and ambiguous unkeyed durable references', () {
    final now = DateTime.utc(2026, 9, 26);
    final first = DocumentAsset(
      id: 'first-asset',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'first.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://sharedref',
      createdAt: now,
      updatedAt: now,
    );
    final node = _imageNodeWithReference(
      'image-node',
      reference: first.durableReference!,
    );

    expect(
      ImportMergePlanner.unresolvedDependencies(
        nodes: [node],
        assets: const DocumentAssetManifest(),
      ),
      {'varian-image://sharedref'},
    );
    expect(
      ImportMergePlanner.unresolvedDependencies(
        nodes: [node],
        assets: DocumentAssetManifest(entries: {first.id: first}),
      ),
      isEmpty,
    );

    final second = first.copyWith(id: 'second-asset', name: 'second.png');
    expect(
      ImportMergePlanner.unresolvedDependencies(
        nodes: [node],
        assets: DocumentAssetManifest(
          entries: {first.id: first, second.id: second},
        ),
      ),
      {'varian-image://sharedref'},
    );
  });

  test('keeps non-colliding imported asset IDs and references intact', () {
    final now = DateTime.utc(2026, 9, 26);
    final imported = DocumentAsset(
      id: 'new-image',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'new.png',
      mimeType: 'image/png',
      durableReference: 'varian-image://new',
      createdAt: now,
      updatedAt: now,
    );
    final plan = ImportMergePlanner.plan(
      importedNodes: [_imageNode('image-node', assetId: imported.id)],
      importedEdges: const [],
      existingNodeIds: const [],
      existingEdgeIds: const [],
      importedAssets: DocumentAssetManifest(entries: {imported.id: imported}),
    );

    expect(plan.assets[imported.id], same(imported));
    expect((plan.nodes.single.payload as ImagePayload).assetId, imported.id);
  });
}

CanvasNode _imageNodeWithReference(String id, {required String reference}) =>
    CanvasNode(
      id: id,
      type: NodeType.image,
      x: 0,
      y: 0,
      width: 100,
      height: 80,
      payload: ImagePayload(imageArtifactReference: reference),
    );

CanvasNode _imageNode(String id, {required String assetId}) => CanvasNode(
  id: id,
  type: NodeType.image,
  x: 0,
  y: 0,
  width: 100,
  height: 80,
  payload: ImagePayload(assetId: assetId),
);

CanvasNode _node(String id) => CanvasNode(
  id: id,
  type: NodeType.rectangle,
  x: 0,
  y: 0,
  width: 100,
  height: 80,
  payload: ShapePayload(),
);
