import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/features/templates/data/diagram_templates.dart';

void main() {
  test('registry aliases expose the same named entries', () {
    final listedIds = DiagramTemplates.listTemplates()
        .map((template) => template.id)
        .toList();

    expect(
      DiagramTemplates.templates.map((template) => template.id).toList(),
      listedIds,
    );
    expect(
      DiagramTemplates.registry.map((template) => template.id).toList(),
      listedIds,
    );
    expect(
      DiagramTemplates.instantiateTemplate('flowchart').nodes,
      hasLength(4),
    );
  });

  test('instantiation remaps IDs, endpoints, and origin independently', () {
    final first = DiagramTemplates.instantiate(
      'flowchart',
      origin: const Offset(240, 80),
    );
    final firstNodeIds = first.nodes.map((node) => node.id).toSet();
    final firstEdgeIds = first.edges.map((edge) => edge.id).toSet();

    expect(first.nodes.first.x, 240);
    expect(first.nodes.first.y, 80);
    expect(firstNodeIds, hasLength(first.nodes.length));
    expect(firstEdgeIds, hasLength(first.edges.length));
    expect(
      first.edges.every(
        (edge) =>
            firstNodeIds.contains(edge.sourceNodeId) &&
            firstNodeIds.contains(edge.targetNodeId),
      ),
      isTrue,
    );

    final second = DiagramTemplates.instantiate(
      'flowchart',
      origin: const Offset(-30, 12),
      existingNodeIds: firstNodeIds,
      existingEdgeIds: firstEdgeIds,
    );
    final secondIds = second.nodes.map((node) => node.id).toSet();

    expect(second.nodes.first.x, -30);
    expect(second.nodes.first.y, 12);
    expect(secondIds.intersection(firstNodeIds), isEmpty);
    expect(
      second.edges.map((edge) => edge.id).toSet().intersection(firstEdgeIds),
      isEmpty,
    );
    expect(
      second.edges.every(
        (edge) =>
            secondIds.contains(edge.sourceNodeId) &&
            secondIds.contains(edge.targetNodeId),
      ),
      isTrue,
    );
  });

  test('reusable kit returns remapped, independent component payloads', () {
    final first = DiagramTemplates.instantiate(
      'primary-button',
      origin: const Offset(20, 30),
    );
    final firstComponent = first.nodes.single;
    final firstPayload = firstComponent.payload as ComponentPayload;
    final firstChildIds = firstPayload.templateChildren
        .map((child) => child.id)
        .toSet();

    final second = DiagramTemplates.instantiate(
      'primary-button',
      origin: const Offset(220, 30),
      existingNodeIds: {firstComponent.id, ...firstChildIds},
    );
    final secondComponent = second.nodes.single;
    final secondPayload = secondComponent.payload as ComponentPayload;
    final secondChildIds = secondPayload.templateChildren
        .map((child) => child.id)
        .toSet();

    expect(firstComponent.x, 20);
    expect(firstComponent.y, 30);
    expect(secondComponent.x, 220);
    expect(secondComponent.y, 30);
    expect(firstPayload.masterComponentId, firstComponent.id);
    expect(secondPayload.masterComponentId, secondComponent.id);
    expect(firstChildIds.intersection(secondChildIds), isEmpty);
    expect(
      secondChildIds.every((id) => id != 'primary_button_background'),
      isTrue,
    );
  });
}
