import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/domain/ai_copilot_context.dart';

CanvasNode _node({required String id, String? parentId, String? pageId}) =>
    CanvasNode(
      id: id,
      type: NodeType.rectangle,
      x: 10,
      y: 20,
      width: 120,
      height: 80,
      parentId: parentId,
      pageId: pageId,
      payload: ShapePayload(label: 'Private label'),
    );

void main() {
  test(
    'captures frame context and excludes binary or sensitive payload data',
    () {
      final snapshot = AICopilotContextSnapshot.fromCanvas(
        projectId: 'project-1',
        scope: AICopilotContextScope.frame,
        allNodes: [
          _node(id: 'frame-1', pageId: 'page-1'),
          _node(id: 'child-1', parentId: 'frame-1', pageId: 'page-1'),
          _node(id: 'other-1', pageId: 'page-1'),
        ],
        selectedNodeIds: const ['child-1'],
        frameId: 'frame-1',
        capturedAt: DateTime.utc(2026, 9, 13),
      );

      expect(
        snapshot.nodes.map((node) => node['id']),
        containsAll(<String>['frame-1', 'child-1']),
      );
      expect(
        snapshot.nodes.map((node) => node['id']),
        isNot(contains('other-1')),
      );
      expect(snapshot.selectedNodeIds, ['child-1']);
      expect(snapshot.toPrompt(), isNot(contains('Private label')));
      expect(snapshot.capturedAt, DateTime.utc(2026, 9, 13));
    },
  );

  test('captures asset collection with durable metadata only', () {
    final snapshot = AICopilotContextSnapshot.fromCanvas(
      projectId: 'project-1',
      scope: AICopilotContextScope.assetCollection,
      allNodes: const [],
      assets: [
        DocumentAsset(
          id: 'asset-1',
          kind: DocumentAssetKind.image,
          storage: DocumentAssetStorage.remote,
          name: 'Reference',
          mimeType: 'image/png',
          sizeBytes: 1024,
          remoteUrl: 'https://example.invalid/private.png',
          metadata: {'apiToken': 'secret'},
          createdAt: DateTime.utc(2026, 9, 13),
          updatedAt: DateTime.utc(2026, 9, 13),
        ),
      ],
    );

    expect(snapshot.nodes, isEmpty);
    expect(snapshot.assets, hasLength(1));
    expect(snapshot.assets.single['name'], 'Reference');
    expect(snapshot.assets.single.containsKey('remoteUrl'), isFalse);
    expect(snapshot.assets.single.toString(), isNot(contains('secret')));
  });

  test('round-trips context and bounds prompt size', () {
    final snapshot = AICopilotContextSnapshot.fromCanvas(
      projectId: 'project-1',
      scope: AICopilotContextScope.project,
      allNodes: List.generate(
        200,
        (index) => _node(id: 'node-$index', pageId: 'page-1'),
      ),
    );
    final restored = AICopilotContextSnapshot.fromJson(snapshot.toJson());

    expect(restored.projectId, 'project-1');
    expect(restored.scope, AICopilotContextScope.project);
    expect(restored.nodes, hasLength(200));
    expect(restored.toPrompt().length, lessThanOrEqualTo(12020));
  });
}
