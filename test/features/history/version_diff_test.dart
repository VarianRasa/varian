import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/history/version_diff.dart';

void main() {
  CanvasDocument document({
    List<CanvasNode> nodes = const [],
    Map<String, dynamic> navigation = const {},
  }) => CanvasDocument(
    projectId: 'project-1',
    nodes: nodes,
    navigation: navigation,
    updatedAt: DateTime.utc(2026, 9, 13),
  );

  CanvasNode node(String id, {double x = 0}) => CanvasNode(
    id: id,
    type: NodeType.rectangle,
    x: x,
    y: 0,
    width: 100,
    height: 80,
    payload: ShapePayload(),
  );

  test('counts added, removed, changed, and structural document fields', () {
    final before = document(nodes: [node('a'), node('removed')]);
    final after = document(
      nodes: [node('a', x: 20), node('added')],
      navigation: const {'activePageId': 'page-2'},
    );

    final diff = DocumentVersionDiff.compare(before, after);

    expect(diff.addedNodes, 1);
    expect(diff.removedNodes, 1);
    expect(diff.changedNodes, 1);
    expect(diff.navigationChanged, isTrue);
    expect(diff.isEmpty, isFalse);
    expect(diff.summaryLines(), contains('1 node diubah'));
  });

  test('returns an empty diff for equivalent documents', () {
    final first = document(nodes: [node('a')]);
    final second = document(nodes: [node('a')]);

    final diff = DocumentVersionDiff.compare(first, second);

    expect(diff.isEmpty, isTrue);
    expect(diff.totalChanges, 0);
    expect(diff.toJson()['totalChanges'], 0);
  });

  test('serializes a diff for export and audit surfaces', () {
    final before = document(nodes: [node('a')]);
    final after = document(nodes: [node('a', x: 10), node('b')]);

    final json = DocumentVersionDiff.compare(before, after).toJson();

    expect(json['addedNodes'], 1);
    expect(json['changedNodes'], 1);
    expect(json['totalChanges'], greaterThan(0));
  });
}
