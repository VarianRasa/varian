import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';

void main() {
  group('Component Engine & Figma Properties Tests', () {
    test('ComponentPayload default initialization has correct values', () {
      final payload = ComponentPayload(
        masterComponentId: 'comp_1',
        componentName: 'Primary Button',
        isMaster: true,
      );

      expect(payload.masterComponentId, 'comp_1');
      expect(payload.componentName, 'Primary Button');
      expect(payload.isMaster, isTrue);
      expect(payload.properties, isEmpty);
      expect(payload.propertyValues, isEmpty);
      expect(payload.templateChildren, isEmpty);
      expect(payload.showBadge, isTrue);
    });

    test(
      'ComponentPayload serializes and deserializes properties and variants',
      () {
        const prop1 = ComponentProperty(
          id: 'p1',
          name: 'label',
          type: ComponentPropType.text,
          defaultValue: 'Click Me',
        );

        const prop2 = ComponentProperty(
          id: 'p2',
          name: 'hasIcon',
          type: ComponentPropType.boolean,
          defaultValue: true,
        );

        const prop3 = ComponentProperty(
          id: 'p3',
          name: 'variant',
          type: ComponentPropType.variant,
          defaultValue: 'Primary',
          options: ['Primary', 'Secondary', 'Danger'],
        );

        final childNode = CanvasNode(
          id: 'child_1',
          type: NodeType.text,
          name: 'Label Layer',
          x: 10,
          y: 10,
          width: 80,
          height: 20,
          payload: TextPayload(text: 'Button Text'),
        );

        final payload = ComponentPayload(
          masterComponentId: 'master_100',
          componentName: 'ActionButton',
          description: 'Design system primary button',
          isMaster: true,
          properties: [prop1, prop2, prop3],
          propertyValues: {
            'label': 'Submit Form',
            'hasIcon': false,
            'variant': 'Danger',
          },
          templateChildren: [childNode],
          themeColor: const Color(0xFF9333EA),
        );

        final json = payload.toJson();
        expect(json['componentName'], 'ActionButton');
        expect(json['isMaster'], isTrue);
        expect((json['properties'] as List).length, 3);
        expect((json['templateChildren'] as List).length, 1);
        expect(json['propertyValues']['label'], 'Submit Form');

        final deserialized = ComponentPayload.fromJson(json);
        expect(deserialized.componentName, 'ActionButton');
        expect(deserialized.properties.length, 3);
        expect(deserialized.properties[2].type, ComponentPropType.variant);
        expect(deserialized.properties[2].options, contains('Danger'));
        expect(deserialized.templateChildren.length, 1);
        expect(deserialized.templateChildren.first.name, 'Label Layer');
      },
    );

    test('Component clone and copyWith maintain property values', () {
      final original = ComponentPayload(
        masterComponentId: 'orig_1',
        componentName: 'Card Component',
        isMaster: false,
        propertyValues: {'title': 'Hero Title'},
      );

      final cloned = original.clone();
      expect(cloned.componentName, 'Card Component');
      expect(cloned.isMaster, isFalse);
      expect(cloned.propertyValues['title'], 'Hero Title');

      final updated = original.copyWith(
        componentName: 'Updated Card',
        isMaster: true,
      );
      expect(updated.componentName, 'Updated Card');
      expect(updated.isMaster, isTrue);
      expect(updated.propertyValues['title'], 'Hero Title');
    });
  });

  group('Component Painter Visual Tests', () {
    testWidgets(
      'NodePainter paints Master Component with nested child shapes (Rectangle, Ellipse, Text)',
      (tester) async {
        final rectLayer = CanvasNode(
          id: 'layer_rect',
          type: NodeType.rectangle,
          name: 'Btn Box',
          x: 0,
          y: 0,
          width: 140,
          height: 50,
          payload: ShapePayload(fill: const Color(0xFF4F46E5)),
        );

        final circleLayer = CanvasNode(
          id: 'layer_circle',
          type: NodeType.ellipse,
          name: 'Btn Icon',
          x: 10,
          y: 10,
          width: 30,
          height: 30,
          payload: ShapePayload(fill: const Color(0xFFEAB308)),
        );

        final textLayer = CanvasNode(
          id: 'layer_text',
          type: NodeType.text,
          name: 'Btn Label',
          x: 50,
          y: 15,
          width: 80,
          height: 20,
          payload: TextPayload(text: 'Submit', color: Colors.white),
        );

        final richCompNode = CanvasNode(
          id: 'rich_comp',
          type: NodeType.component,
          name: 'Action Button Master',
          x: 0,
          y: 0,
          width: 140,
          height: 50,
          payload: ComponentPayload(
            masterComponentId: 'rich_comp',
            componentName: 'Action Button',
            isMaster: true,
            templateChildren: [rectLayer, circleLayer, textLayer],
            propertyValues: {'label': 'Submit'},
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestComponentPainterWidget(node: richCompNode),
            ),
          ),
        );

        expect(find.byType(_TestComponentPainterWidget), findsOneWidget);
      },
    );
  });
}

class _TestComponentPainterWidget extends StatelessWidget {
  final CanvasNode node;
  const _TestComponentPainterWidget({required this.node});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(200, 100),
      painter: _TestComponentPainter(node: node),
    );
  }
}

class _TestComponentPainter extends CustomPainter {
  final CanvasNode node;
  _TestComponentPainter({required this.node});

  @override
  void paint(Canvas canvas, Size size) {
    NodePainter.paint(canvas, node);
  }

  @override
  bool shouldRepaint(covariant _TestComponentPainter oldDelegate) => true;
}
