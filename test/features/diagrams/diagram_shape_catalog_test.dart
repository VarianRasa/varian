import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/diagrams/domain/diagram_shape_catalog.dart';

void main() {
  test('catalog exposes broad draw.io-compatible diagram families', () {
    final entries = DiagramShapeCatalog.entries;
    final categories = entries.map((entry) => entry.category).toSet();

    expect(entries.length, greaterThanOrEqualTo(50));
    expect(categories, contains(DiagramShapeCategory.flowchart));
    expect(categories, contains(DiagramShapeCategory.uml));
    expect(categories, contains(DiagramShapeCategory.bpmn));
    expect(categories, contains(DiagramShapeCategory.network));
    expect(categories, contains(DiagramShapeCategory.database));
    expect(DiagramShapeCatalog.byId('rhombus'), isNotNull);
    expect(DiagramShapeCatalog.byId('mxgraph.bpmn.event'), isNotNull);
  });

  test('catalog builds bounded paths for native and fallback shapes', () {
    final known = DiagramShapeCatalog.byId('hexagon')!;
    final fallback =
        DiagramShapeCatalog.byId('mxgraph.custom.unknown') ??
        DiagramShapeCatalog.fallback;

    final knownPath = known.buildPath(const Size(160, 100));
    final fallbackPath = fallback.buildPath(const Size(160, 100));

    expect(knownPath.computeMetrics().isNotEmpty, isTrue);
    expect(fallbackPath.computeMetrics().isNotEmpty, isTrue);
  });

  test('primitive shapes keep their geometry contract', () {
    final rectangle = DiagramShapeCatalog.resolve('rectangle');
    final rounded = DiagramShapeCatalog.resolve('roundedRectangle');
    final ellipse = DiagramShapeCatalog.resolve('ellipse');
    final circle = DiagramShapeCatalog.resolve('circle');

    expect(rectangle.nodeKind, DiagramShapeNodeKind.rectangle);
    expect(rectangle.defaultCornerRadius, 0);
    expect(rounded.defaultCornerRadius, greaterThan(0));
    expect(ellipse.nodeKind, DiagramShapeNodeKind.ellipse);
    expect(circle.nodeKind, DiagramShapeNodeKind.ellipse);

    final ellipseBounds = ellipse.buildPath(const Size(42, 24)).getBounds();
    final circleBounds = circle.buildPath(const Size(42, 24)).getBounds();
    expect(ellipseBounds.width, closeTo(42, 0.001));
    expect(ellipseBounds.height, closeTo(24, 0.001));
    expect(circleBounds.width, closeTo(24, 0.001));
    expect(circleBounds.height, closeTo(24, 0.001));

    expect(
      DiagramShapeCatalog.normalizeCreationRect(
        'circle',
        const Rect.fromLTWH(10, 20, 160, 100),
      ),
      const Rect.fromLTWH(10, 20, 100, 100),
    );
  });

  test(
    'generic corner-radius shapes round their perimeter and expose handle math',
    () {
      const size = Size(160, 100);
      const radius = 18.0;
      final ids = [
        'triangle',
        'rhombus',
        'parallelogram',
        'flowchart.document',
        'uml.package',
        'mxgraph.network.router',
        'arrow',
      ];

      double pathLength(Path path) {
        var length = 0.0;
        for (final metric in path.computeMetrics()) {
          length += metric.length;
        }
        return length;
      }

      for (final definition in DiagramShapeCatalog.entries.where(
        (entry) => entry.supportsCornerRadius,
      )) {
        expect(
          definition.cornerRadiusHandlePosition(size, radius),
          isNotNull,
          reason: definition.id,
        );
      }

      for (final id in ids) {
        final definition = DiagramShapeCatalog.resolve(id);
        expect(definition.supportsCornerRadius, isTrue, reason: id);
        final handle = definition.cornerRadiusHandlePosition(size, radius);
        expect(handle, isNotNull, reason: id);
        expect(
          definition.cornerRadiusFromHandle(size, handle!),
          closeTo(radius, 0.01),
          reason: id,
        );
        expect(
          pathLength(definition.buildPath(size, cornerRadius: radius)),
          isNot(
            closeTo(
              pathLength(definition.buildPath(size, cornerRadius: 0)),
              0.01,
            ),
          ),
          reason: id,
        );
      }
    },
  );

  test(
    'intrinsic curves and composite controls do not expose generic radius',
    () {
      for (final id in [
        'ellipse',
        'circle',
        'cylinder',
        'database',
        'cloud',
        'mxgraph.network.cloud',
        'uml.actor',
        'mxgraph.basic.actor',
        'mxgraph.basic.person',
      ]) {
        final definition = DiagramShapeCatalog.resolve(id);
        expect(definition.supportsCornerRadius, isFalse, reason: id);
        expect(
          definition.cornerRadiusHandlePosition(const Size(160, 100), 18),
          isNull,
          reason: id,
        );
      }
    },
  );

  test('shape payload preserves catalog and raw Draw.io style metadata', () {
    final payload = ShapePayload(
      diagramShapeId: 'mxgraph.bpmn.event',
      rawDrawioStyle: 'shape=mxgraph.bpmn.event;html=1;',
      label: 'Start',
    );

    final restored = ShapePayload.fromJson(payload.toJson());

    expect(restored.diagramShapeId, payload.diagramShapeId);
    expect(restored.rawDrawioStyle, payload.rawDrawioStyle);
    expect(restored.label, 'Start');
  });
}
