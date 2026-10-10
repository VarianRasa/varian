import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/document_package.dart';
import 'package:varian/domain/models/document_package_diagnostics.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';

void main() {
  CanvasNode node(String id, {double width = 100}) => CanvasNode(
    id: id,
    type: NodeType.rectangle,
    x: 10,
    y: 20,
    width: width,
    height: 80,
    payload: ShapePayload(),
  );

  CanvasDocument document({List<CanvasNode>? nodes, List<CanvasEdge>? edges}) =>
      CanvasDocument(
        projectId: 'project',
        nodes: nodes ?? [node('a')],
        edges: edges ?? const [],
        updatedAt: DateTime.utc(2026, 9, 13),
      );

  test('reports duplicate IDs, dangling edges, and stable checksum', () {
    final package = CanvasDocumentPackage(
      document: document(
        nodes: [node('a'), node('a')],
        edges: [
          const CanvasEdge(
            id: 'edge',
            sourceNodeId: 'a',
            targetNodeId: 'missing',
          ),
        ],
      ),
    );

    final report = DocumentPackageDiagnostics.inspect(package);

    expect(report.isHealthy, isFalse);
    expect(report.canRepair, isTrue);
    expect(
      report.issues.map((issue) => issue.code),
      contains('duplicate_node_id'),
    );
    expect(
      report.issues.map((issue) => issue.code),
      contains('dangling_edge_target'),
    );
    expect(
      DocumentPackageDiagnostics.inspect(
        package,
        expectedChecksum: report.checksum,
      ).issues.where((issue) => issue.code == 'package_checksum_mismatch'),
      isEmpty,
    );
  });

  test('repairs duplicate nodes, dangling edges, and invalid geometry', () {
    final package = CanvasDocumentPackage(
      document: document(
        nodes: [node('a'), node('a', width: -20)],
        edges: [
          const CanvasEdge(
            id: 'edge',
            sourceNodeId: 'a',
            targetNodeId: 'missing',
          ),
        ],
      ),
    );

    final result = DocumentPackageDiagnostics.repair(package);

    expect(result.changed, isTrue);
    expect(result.package.document.nodes, hasLength(1));
    expect(result.package.document.edges, isEmpty);
    expect(result.health.errors, isEmpty);
    expect(result.actions, isNotEmpty);
  });

  test('diagnoses and repairs manifest key and asset ID mismatches', () {
    final now = DateTime.utc(2026, 9, 27);
    final asset = DocumentAsset(
      id: 'asset-id',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.local,
      name: 'image.png',
      mimeType: 'image/png',
      createdAt: now,
      updatedAt: now,
    );
    final package = CanvasDocumentPackage(
      document:
          document(
            nodes: [
              CanvasNode(
                id: 'image-node',
                type: NodeType.image,
                x: 0,
                y: 0,
                width: 100,
                height: 100,
                payload: ImagePayload(assetId: 'manifest-key'),
              ),
            ],
          ).copyWith(
            assets: DocumentAssetManifest(entries: {'manifest-key': asset}),
          ),
      assets: DocumentAssetManifest(entries: {'manifest-key': asset}),
    );

    final report = DocumentPackageDiagnostics.inspect(package);

    expect(
      report.issues.map((issue) => issue.code),
      containsAll([
        'asset_manifest_key_mismatch',
        'invalid_asset_manifest_identity',
      ]),
    );
    expect(
      report.issues
          .where((issue) => issue.code == 'missing_asset_reference')
          .map((issue) => issue.message),
      contains('Asset manifest-key is not present in the manifest.'),
    );
    final repaired = DocumentPackageDiagnostics.repair(package);
    expect(repaired.package.assets.entries.keys, ['asset-id']);
    expect(repaired.package.assets['asset-id']!.id, 'asset-id');
    expect(repaired.health.issues, isEmpty);
  });

  test('previews migrations without mutating the source map', () {
    final source = <String, dynamic>{
      'schemaVersion': 1,
      'projectId': 'legacy',
      'nodes': const [],
      'edges': const [],
    };

    final preview = DocumentPackageMigrationPreview.fromJson(source);

    expect(preview.canApply, isTrue);
    expect(preview.sourceVersion, 1);
    expect(preview.targetVersion, 4);
    expect(preview.appliedMigrations, contains('v1_to_v2'));
    expect(source['schemaVersion'], 1);
  });

  test('duplicates a document with remapped node and edge references', () {
    final source = document(
      nodes: [
        node('frame'),
        node('child').copyWith(parentId: 'frame'),
      ],
      edges: [
        const CanvasEdge(
          id: 'edge',
          sourceNodeId: 'frame',
          targetNodeId: 'child',
          parentId: 'frame',
        ),
      ],
    );

    final copy = DocumentPackageDiagnostics.duplicateDocument(
      source,
      prefix: 'duplicate',
    );

    expect(copy.projectId, 'project-copy');
    expect(
      copy.nodes.map((item) => item.id),
      containsAll(['duplicate-frame', 'duplicate-child']),
    );
    expect(copy.nodes.last.parentId, 'duplicate-frame');
    expect(copy.edges.single.sourceNodeId, 'duplicate-frame');
    expect(copy.edges.single.targetNodeId, 'duplicate-child');
    expect(copy.edges.single.parentId, 'duplicate-frame');
  });
}
