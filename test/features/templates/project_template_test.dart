import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/templates/domain/project_template.dart';

void main() {
  test('catalog includes built-ins and searches by tags', () {
    final catalog = ProjectTemplateCatalog.withBuiltIns();
    final results = catalog.search(tags: const ['template']);

    expect(catalog.templates, isNotEmpty);
    expect(results, isNotEmpty);
  });

  test('catalog favorites and restores custom templates', () {
    final now = DateTime.utc(2026, 9, 11);
    final template = ProjectTemplate(
      id: 'personal:brand',
      name: 'Brand board',
      description: 'Personal starter',
      scope: ProjectTemplateScope.personal,
      tags: const ['brand'],
      createdAt: now,
      updatedAt: now,
    );
    final catalog = ProjectTemplateCatalog.withBuiltIns(custom: [template]);
    final favorite = catalog.toggleFavorite(template.id);
    final restored = ProjectTemplate.fromJson(
      favorite.templates.firstWhere((item) => item.id == template.id).toJson(),
    );

    expect(restored.favorite, isTrue);
    expect(favorite.search(scope: ProjectTemplateScope.personal), hasLength(1));
  });

  test('selection template round-trips nodes and edges through JSON', () {
    final now = DateTime.utc(2026, 9, 11);
    final template = ProjectTemplate(
      id: 'personal:selection',
      name: 'Selection',
      description: 'A reusable selection',
      scope: ProjectTemplateScope.personal,
      selectionNodes: [
        CanvasNode(
          id: 'parent',
          type: NodeType.frame,
          x: 10,
          y: 20,
          width: 320,
          height: 180,
          name: 'Parent',
          payload: FramePayload(),
        ),
        CanvasNode(
          id: 'child',
          type: NodeType.rectangle,
          x: 30,
          y: 50,
          width: 100,
          height: 60,
          parentId: 'parent',
          payload: ShapePayload(),
        ),
      ],
      selectionEdges: [
        const CanvasEdge(
          id: 'edge',
          sourceNodeId: 'parent',
          targetNodeId: 'child',
          parentId: 'parent',
          strokeColor: Color(0xFF112233),
        ),
      ],
      tags: const ['layout', 'reusable'],
      createdAt: now,
      updatedAt: now,
    );

    final restored = ProjectTemplate.fromJson(template.toJson());

    expect(restored.id, template.id);
    expect(restored.selectionNodes, hasLength(2));
    expect(restored.selectionNodes[1].parentId, 'parent');
    expect(restored.selectionEdges, hasLength(1));
    expect(restored.selectionEdges.single.sourceNodeId, 'parent');
    expect(restored.selectionEdges.single.targetNodeId, 'child');
    expect(restored.selectionEdges.single.strokeColor, const Color(0xFF112233));
    expect(restored.tags, template.tags);
  });

  test(
    'selection template remaps internal references and avoids existing IDs',
    () {
      final template = ProjectTemplate(
        id: 'personal:selection',
        name: 'Selection',
        description: '',
        scope: ProjectTemplateScope.personal,
        selectionNodes: [
          CanvasNode(
            id: 'parent',
            type: NodeType.frame,
            x: 0,
            y: 0,
            width: 100,
            height: 100,
            payload: FramePayload(),
          ),
          CanvasNode(
            id: 'child',
            type: NodeType.rectangle,
            x: 10,
            y: 10,
            width: 20,
            height: 20,
            parentId: 'parent',
            variantOfNodeId: 'parent',
            mermaidSourceId: 'parent',
            payload: ShapePayload(),
          ),
        ],
        selectionEdges: [
          const CanvasEdge(
            id: 'edge',
            sourceNodeId: 'parent',
            targetNodeId: 'child',
            parentId: 'parent',
            mermaidSourceId: 'parent',
          ),
        ],
        createdAt: DateTime.utc(2026, 9, 11),
        updatedAt: DateTime.utc(2026, 9, 11),
      );

      final instance = template.instantiate(
        existingNodeIds: const ['already-used-node'],
        existingEdgeIds: const ['already-used-edge'],
      );
      final parent = instance.nodes.firstWhere((node) => node.width == 100);
      final child = instance.nodes.firstWhere((node) => node.width == 20);
      final edge = instance.edges.single;

      expect(instance.nodes.map((node) => node.id).toSet(), hasLength(2));
      expect(instance.edges.map((item) => item.id).toSet(), hasLength(1));
      expect(instance.nodes.map((node) => node.id), isNot(contains('parent')));
      expect(instance.nodes.map((node) => node.id), isNot(contains('child')));
      expect(instance.edges.single.id, isNot('edge'));
      expect(child.parentId, parent.id);
      expect(child.variantOfNodeId, parent.id);
      expect(child.mermaidSourceId, parent.id);
      expect(edge.sourceNodeId, parent.id);
      expect(edge.targetNodeId, child.id);
      expect(edge.parentId, parent.id);
      expect(edge.mermaidSourceId, parent.id);
    },
  );
}
