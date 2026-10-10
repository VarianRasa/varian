import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

enum DiagramShapeCategory {
  basic,
  flowchart,
  uml,
  bpmn,
  network,
  database,
  people,
  container,
  notes,
  arrows,
}

typedef DiagramShapePathBuilder = Path Function(Size size);

enum DiagramShapeNodeKind {
  rectangle,
  ellipse,
  diamond,
  cylinder,
  parallelogram,
}

class DiagramShapeDefinition {
  final String id;
  final String name;
  final DiagramShapeCategory category;
  final DiagramShapePathBuilder builder;
  final bool isFallback;

  const DiagramShapeDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.builder,
    this.isFallback = false,
  });

  Path buildPath(Size size, {double? cornerRadius}) {
    if (!supportsCornerRadius) return builder(size);
    final radius = cornerRadius ?? defaultCornerRadius;
    return DiagramShapeCatalog._buildRoundedPath(id, size, radius) ??
        builder(size);
  }

  bool get supportsCornerRadius =>
      DiagramShapeCatalog._genericCornerRadiusIds.contains(id);

  Offset? cornerRadiusHandlePosition(Size size, double radius) {
    if (!supportsCornerRadius) return null;
    final points = DiagramShapeCatalog._cornerPoints(id, size);
    if (points == null || points.isEmpty) return null;
    final effectiveRadius = radius
        .clamp(0.0, math.min(size.width, size.height) / 2)
        .toDouble();
    if (DiagramShapeCatalog._rectangularCornerRadiusIds.contains(id)) {
      final maxInset = math.min(size.width, size.height) / 2;
      final inset = (effectiveRadius + 14.0)
          .clamp(math.min(14.0, maxInset), maxInset)
          .toDouble();
      return Offset(inset, inset);
    }
    final direction = DiagramShapeCatalog._cornerBisector(points, 0);
    return points.first + direction * (effectiveRadius + 12.0);
  }

  double cornerRadiusFromHandle(Size size, Offset localPosition) {
    if (!supportsCornerRadius) return 0.0;
    final points = DiagramShapeCatalog._cornerPoints(id, size);
    if (points == null || points.isEmpty) return 0.0;
    final anchor = points.first;
    final maxRadius = math.min(size.width, size.height) / 2;
    if (DiagramShapeCatalog._rectangularCornerRadiusIds.contains(id)) {
      final distance = (localPosition - anchor).distance;
      return (distance * 0.7071 - 14.0).clamp(0.0, maxRadius).toDouble();
    }
    final direction = DiagramShapeCatalog._cornerBisector(points, 0);
    final offset = localPosition - anchor;
    final projected = offset.dx * direction.dx + offset.dy * direction.dy;
    return (projected - 12.0).clamp(0.0, maxRadius).toDouble();
  }

  DiagramShapeNodeKind get nodeKind => switch (id) {
    'ellipse' ||
    'circle' ||
    'flowchart.start' ||
    'uml.useCase' ||
    'uml.entity' ||
    'mxgraph.bpmn.event' ||
    'mxgraph.bpmn.timer' => DiagramShapeNodeKind.ellipse,
    'rhombus' ||
    'flowchart.decision' ||
    'mxgraph.bpmn.gateway' => DiagramShapeNodeKind.diamond,
    'cylinder' ||
    'database' ||
    'flowchart.storedData' => DiagramShapeNodeKind.cylinder,
    'parallelogram' || 'flowchart.data' => DiagramShapeNodeKind.parallelogram,
    _ => DiagramShapeNodeKind.rectangle,
  };

  Size get defaultSize =>
      id == 'circle' ? const Size.square(100) : const Size(160, 100);

  double get defaultCornerRadius =>
      DiagramShapeCatalog._intrinsicRoundedIds.contains(id) ? 12.0 : 0.0;
}

/// Native shape registry used by both the canvas palette and Draw.io import.
///
/// The registry deliberately stores shape families rather than embedding
/// draw.io's JavaScript editor or its external stencil assets. Unknown style
/// IDs use [fallback] and retain their original XML metadata in ShapePayload.
class DiagramShapeCatalog {
  DiagramShapeCatalog._();

  static const fallback = DiagramShapeDefinition(
    id: 'fallback',
    name: 'Imported shape',
    category: DiagramShapeCategory.basic,
    builder: _roundedRectangle,
    isFallback: true,
  );

  static final List<DiagramShapeDefinition> entries = List.unmodifiable([
    _shape('rectangle', 'Rectangle', DiagramShapeCategory.basic, _rectangle),
    _shape(
      'roundedRectangle',
      'Rounded rectangle',
      DiagramShapeCategory.basic,
      _roundedRectangle,
    ),
    _shape('ellipse', 'Ellipse', DiagramShapeCategory.basic, _ellipse),
    _shape('circle', 'Circle', DiagramShapeCategory.basic, _circle),
    _shape('triangle', 'Triangle', DiagramShapeCategory.basic, _triangle),
    _shape(
      'invertedTriangle',
      'Inverted triangle',
      DiagramShapeCategory.basic,
      _invertedTriangle,
    ),
    _shape('hexagon', 'Hexagon', DiagramShapeCategory.basic, _hexagon),
    _shape('pentagon', 'Pentagon', DiagramShapeCategory.basic, _pentagon),
    _shape('octagon', 'Octagon', DiagramShapeCategory.basic, _octagon),
    _shape(
      'parallelogram',
      'Parallelogram',
      DiagramShapeCategory.basic,
      _parallelogram,
    ),
    _shape('trapezoid', 'Trapezoid', DiagramShapeCategory.basic, _trapezoid),
    _shape(
      'rightTriangle',
      'Right triangle',
      DiagramShapeCategory.basic,
      _rightTriangle,
    ),
    _shape('rhombus', 'Rhombus', DiagramShapeCategory.flowchart, _rhombus),
    _shape(
      'flowchart.process',
      'Process',
      DiagramShapeCategory.flowchart,
      _rectangle,
    ),
    _shape(
      'flowchart.decision',
      'Decision',
      DiagramShapeCategory.flowchart,
      _rhombus,
    ),
    _shape(
      'flowchart.terminator',
      'Terminator',
      DiagramShapeCategory.flowchart,
      _roundedRectangle,
    ),
    _shape(
      'flowchart.start',
      'Start / end',
      DiagramShapeCategory.flowchart,
      _ellipse,
    ),
    _shape(
      'flowchart.predefinedProcess',
      'Predefined process',
      DiagramShapeCategory.flowchart,
      _predefinedProcess,
    ),
    _shape(
      'flowchart.document',
      'Document',
      DiagramShapeCategory.flowchart,
      _document,
    ),
    _shape(
      'flowchart.documents',
      'Multiple documents',
      DiagramShapeCategory.flowchart,
      _multiDocument,
    ),
    _shape(
      'flowchart.data',
      'Data',
      DiagramShapeCategory.flowchart,
      _parallelogram,
    ),
    _shape(
      'flowchart.manualInput',
      'Manual input',
      DiagramShapeCategory.flowchart,
      _manualInput,
    ),
    _shape(
      'flowchart.manualOperation',
      'Manual operation',
      DiagramShapeCategory.flowchart,
      _manualOperation,
    ),
    _shape('flowchart.delay', 'Delay', DiagramShapeCategory.flowchart, _delay),
    _shape(
      'flowchart.preparation',
      'Preparation',
      DiagramShapeCategory.flowchart,
      _preparation,
    ),
    _shape(
      'flowchart.internalStorage',
      'Internal storage',
      DiagramShapeCategory.flowchart,
      _internalStorage,
    ),
    _shape(
      'flowchart.offPageConnector',
      'Off-page connector',
      DiagramShapeCategory.flowchart,
      _offPageConnector,
    ),
    _shape(
      'flowchart.display',
      'Display',
      DiagramShapeCategory.flowchart,
      _display,
    ),
    _shape(
      'flowchart.merge',
      'Merge',
      DiagramShapeCategory.flowchart,
      _triangle,
    ),
    _shape(
      'flowchart.extract',
      'Extract',
      DiagramShapeCategory.flowchart,
      _invertedTriangle,
    ),
    _shape('flowchart.or', 'Or', DiagramShapeCategory.flowchart, _or),
    _shape(
      'flowchart.summing',
      'Summing junction',
      DiagramShapeCategory.flowchart,
      _summing,
    ),
    _shape(
      'flowchart.storedData',
      'Stored data',
      DiagramShapeCategory.flowchart,
      _cylinder,
    ),
    _shape('cylinder', 'Cylinder', DiagramShapeCategory.database, _cylinder),
    _shape('database', 'Database', DiagramShapeCategory.database, _cylinder),
    _shape(
      'internalStorage',
      'Internal storage',
      DiagramShapeCategory.database,
      _internalStorage,
    ),
    _shape('uml.class', 'UML class', DiagramShapeCategory.uml, _umlClass),
    _shape(
      'uml.interface',
      'UML interface',
      DiagramShapeCategory.uml,
      _umlInterface,
    ),
    _shape(
      'uml.component',
      'UML component',
      DiagramShapeCategory.uml,
      _umlComponent,
    ),
    _shape('uml.package', 'UML package', DiagramShapeCategory.uml, _umlPackage),
    _shape('uml.object', 'UML object', DiagramShapeCategory.uml, _umlObject),
    _shape('uml.useCase', 'UML use case', DiagramShapeCategory.uml, _ellipse),
    _shape('uml.actor', 'UML actor', DiagramShapeCategory.people, _actor),
    _shape(
      'uml.boundary',
      'UML boundary',
      DiagramShapeCategory.uml,
      _roundedRectangle,
    ),
    _shape('uml.control', 'UML control', DiagramShapeCategory.uml, _control),
    _shape('uml.entity', 'UML entity', DiagramShapeCategory.uml, _entity),
    _shape(
      'mxgraph.bpmn.event',
      'BPMN event',
      DiagramShapeCategory.bpmn,
      _bpmnEvent,
    ),
    _shape(
      'mxgraph.bpmn.gateway',
      'BPMN gateway',
      DiagramShapeCategory.bpmn,
      _rhombus,
    ),
    _shape(
      'mxgraph.bpmn.task',
      'BPMN task',
      DiagramShapeCategory.bpmn,
      _roundedRectangle,
    ),
    _shape(
      'mxgraph.bpmn.subprocess',
      'BPMN subprocess',
      DiagramShapeCategory.bpmn,
      _subprocess,
    ),
    _shape('mxgraph.bpmn.pool', 'BPMN pool', DiagramShapeCategory.bpmn, _pool),
    _shape('mxgraph.bpmn.lane', 'BPMN lane', DiagramShapeCategory.bpmn, _pool),
    _shape(
      'mxgraph.bpmn.dataObject',
      'BPMN data object',
      DiagramShapeCategory.bpmn,
      _document,
    ),
    _shape(
      'mxgraph.bpmn.message',
      'BPMN message',
      DiagramShapeCategory.bpmn,
      _message,
    ),
    _shape(
      'mxgraph.bpmn.timer',
      'BPMN timer',
      DiagramShapeCategory.bpmn,
      _timer,
    ),
    _shape(
      'mxgraph.network.server',
      'Server',
      DiagramShapeCategory.network,
      _server,
    ),
    _shape(
      'mxgraph.network.router',
      'Router',
      DiagramShapeCategory.network,
      _router,
    ),
    _shape(
      'mxgraph.network.cloud',
      'Cloud',
      DiagramShapeCategory.network,
      _cloud,
    ),
    _shape(
      'mxgraph.network.client',
      'Client',
      DiagramShapeCategory.network,
      _client,
    ),
    _shape(
      'mxgraph.network.mobile',
      'Mobile device',
      DiagramShapeCategory.network,
      _mobile,
    ),
    _shape(
      'mxgraph.network.firewall',
      'Firewall',
      DiagramShapeCategory.network,
      _firewall,
    ),
    _shape(
      'mxgraph.network.switch',
      'Network switch',
      DiagramShapeCategory.network,
      _switch,
    ),
    _shape(
      'mxgraph.network.internet',
      'Internet cloud',
      DiagramShapeCategory.network,
      _cloud,
    ),
    _shape(
      'mxgraph.basic.person',
      'Person',
      DiagramShapeCategory.people,
      _person,
    ),
    _shape('mxgraph.basic.user', 'User', DiagramShapeCategory.people, _person),
    _shape('mxgraph.basic.actor', 'Actor', DiagramShapeCategory.people, _actor),
    _shape('note', 'Note', DiagramShapeCategory.notes, _note),
    _shape('callout', 'Callout', DiagramShapeCategory.notes, _callout),
    _shape(
      'speechBubble',
      'Speech bubble',
      DiagramShapeCategory.notes,
      _speechBubble,
    ),
    _shape('cloud', 'Cloud', DiagramShapeCategory.network, _cloud),
    _shape('frame', 'Container', DiagramShapeCategory.container, _container),
    _shape('swimlane', 'Swimlane', DiagramShapeCategory.container, _pool),
    _shape('folder', 'Folder', DiagramShapeCategory.container, _folder),
    _shape('package', 'Package', DiagramShapeCategory.container, _umlPackage),
    _shape('arrow', 'Arrow', DiagramShapeCategory.arrows, _arrow),
    _shape(
      'doubleArrow',
      'Double arrow',
      DiagramShapeCategory.arrows,
      _doubleArrow,
    ),
    _shape(
      'leftRightArrow',
      'Left-right arrow',
      DiagramShapeCategory.arrows,
      _leftRightArrow,
    ),
    _shape(
      'upDownArrow',
      'Up-down arrow',
      DiagramShapeCategory.arrows,
      _upDownArrow,
    ),
  ]);

  static final Map<String, DiagramShapeDefinition> _byId = {
    for (final entry in entries) entry.id: entry,
  };

  static const Set<String> _genericCornerRadiusIds = {
    'rectangle',
    'roundedRectangle',
    'triangle',
    'invertedTriangle',
    'hexagon',
    'pentagon',
    'octagon',
    'parallelogram',
    'trapezoid',
    'rightTriangle',
    'rhombus',
    'flowchart.process',
    'flowchart.decision',
    'mxgraph.bpmn.gateway',
    'flowchart.terminator',
    'flowchart.predefinedProcess',
    'flowchart.document',
    'flowchart.documents',
    'flowchart.data',
    'flowchart.manualInput',
    'flowchart.manualOperation',
    'flowchart.preparation',
    'flowchart.internalStorage',
    'flowchart.offPageConnector',
    'flowchart.merge',
    'flowchart.extract',
    'internalStorage',
    'uml.class',
    'uml.interface',
    'uml.component',
    'uml.package',
    'uml.object',
    'uml.boundary',
    'uml.control',
    'mxgraph.bpmn.task',
    'mxgraph.bpmn.subprocess',
    'mxgraph.bpmn.pool',
    'mxgraph.bpmn.lane',
    'mxgraph.bpmn.dataObject',
    'mxgraph.bpmn.message',
    'mxgraph.network.server',
    'mxgraph.network.router',
    'mxgraph.network.client',
    'mxgraph.network.mobile',
    'mxgraph.network.firewall',
    'mxgraph.network.switch',
    'note',
    'callout',
    'speechBubble',
    'frame',
    'swimlane',
    'folder',
    'package',
    'arrow',
    'doubleArrow',
    'leftRightArrow',
    'upDownArrow',
  };

  static const Set<String> _rectangularCornerRadiusIds = {
    'rectangle',
    'roundedRectangle',
    'flowchart.process',
    'flowchart.terminator',
    'flowchart.predefinedProcess',
    'flowchart.internalStorage',
    'internalStorage',
    'uml.class',
    'uml.interface',
    'uml.component',
    'uml.object',
    'uml.boundary',
    'uml.control',
    'mxgraph.bpmn.task',
    'mxgraph.bpmn.subprocess',
    'mxgraph.bpmn.pool',
    'mxgraph.bpmn.lane',
    'mxgraph.network.server',
    'mxgraph.network.client',
    'mxgraph.network.mobile',
    'frame',
    'swimlane',
  };

  static const Set<String> _intrinsicRoundedIds = {
    'roundedRectangle',
    'flowchart.predefinedProcess',
    'flowchart.terminator',
    'mxgraph.bpmn.task',
    'mxgraph.bpmn.subprocess',
    'uml.component',
    'uml.interface',
    'uml.boundary',
    'uml.control',
    'mxgraph.network.server',
    'mxgraph.network.mobile',
    'callout',
    'speechBubble',
    'frame',
  };

  static DiagramShapeDefinition? byId(String? id) {
    final value = id?.trim();
    if (value == null || value.isEmpty) return null;
    return _byId[value];
  }

  static DiagramShapeDefinition resolve(String? id) => byId(id) ?? fallback;

  static Rect normalizeCreationRect(String? id, Rect rect) {
    if (id != 'circle') return rect;
    final size = math.min(rect.width, rect.height);
    return Rect.fromLTWH(rect.left, rect.top, size, size);
  }

  static Path? _buildRoundedPath(String id, Size size, double radius) {
    final safeRadius = radius
        .clamp(0.0, math.min(size.width, size.height) / 2)
        .toDouble();
    switch (id) {
      case 'rectangle':
      case 'roundedRectangle':
      case 'flowchart.process':
      case 'flowchart.terminator':
      case 'uml.class':
      case 'uml.interface':
      case 'uml.object':
      case 'uml.boundary':
      case 'uml.control':
      case 'mxgraph.bpmn.task':
      case 'mxgraph.bpmn.pool':
      case 'mxgraph.bpmn.lane':
      case 'mxgraph.network.server':
      case 'mxgraph.network.client':
      case 'frame':
      case 'swimlane':
        return _roundedRectWithRadius(size, safeRadius);
      case 'flowchart.predefinedProcess':
        return _predefinedProcessWithRadius(size, safeRadius);
      case 'flowchart.document':
      case 'mxgraph.bpmn.dataObject':
        return _documentWithRadius(size, safeRadius);
      case 'flowchart.documents':
        return _multiDocumentWithRadius(size, safeRadius);
      case 'flowchart.internalStorage':
      case 'internalStorage':
        return _internalStorageWithRadius(size, safeRadius);
      case 'uml.component':
        return _umlComponentWithRadius(size, safeRadius);
      case 'mxgraph.network.mobile':
        return _mobileWithRadius(size, safeRadius);
      case 'note':
        return _noteWithRadius(size, safeRadius);
      case 'callout':
      case 'speechBubble':
        return _calloutWithRadius(size, safeRadius);
      case 'mxgraph.bpmn.message':
        return _messageWithRadius(size, safeRadius);
      case 'doubleArrow':
      case 'leftRightArrow':
        return _doubleArrowWithRadius(size, safeRadius);
      case 'upDownArrow':
        return _doubleArrowWithRadius(
          Size(size.height, size.width),
          safeRadius,
        );
      default:
        final points = _cornerPoints(id, size);
        return points == null ? null : _roundedPolygon(points, safeRadius);
    }
  }

  static List<Offset>? _cornerPoints(String id, Size size) {
    final w = size.width;
    final h = size.height;
    switch (id) {
      case 'rectangle':
      case 'roundedRectangle':
      case 'flowchart.process':
      case 'flowchart.terminator':
      case 'flowchart.predefinedProcess':
      case 'flowchart.internalStorage':
      case 'internalStorage':
      case 'uml.class':
      case 'uml.interface':
      case 'uml.component':
      case 'uml.object':
      case 'uml.boundary':
      case 'uml.control':
      case 'mxgraph.bpmn.task':
      case 'mxgraph.bpmn.subprocess':
      case 'mxgraph.bpmn.pool':
      case 'mxgraph.bpmn.lane':
      case 'mxgraph.network.server':
      case 'mxgraph.network.client':
      case 'mxgraph.network.mobile':
      case 'frame':
      case 'swimlane':
        return [Offset.zero, Offset(w, 0), Offset(w, h), Offset(0, h)];
      case 'triangle':
      case 'flowchart.merge':
        return _polygonPoints(size, 3);
      case 'invertedTriangle':
      case 'flowchart.extract':
        return _polygonPoints(size, 3, rotation: math.pi / 2);
      case 'hexagon':
      case 'mxgraph.network.router':
      case 'mxgraph.network.switch':
      case 'flowchart.preparation':
        return _polygonPoints(size, 6, rotation: 0);
      case 'pentagon':
        return _polygonPoints(size, 5);
      case 'octagon':
        return _polygonPoints(size, 8, rotation: math.pi / 8);
      case 'rhombus':
      case 'flowchart.decision':
      case 'mxgraph.bpmn.gateway':
        return [
          Offset(w / 2, 0),
          Offset(w, h / 2),
          Offset(w / 2, h),
          Offset(0, h / 2),
        ];
      case 'parallelogram':
      case 'flowchart.data':
        final skew = w * 0.18;
        return [
          Offset(skew, 0),
          Offset(w, 0),
          Offset(w - skew, h),
          Offset(0, h),
        ];
      case 'trapezoid':
      case 'mxgraph.network.firewall':
        final inset = w * 0.18;
        return [
          Offset(inset, 0),
          Offset(w - inset, 0),
          Offset(w, h),
          Offset(0, h),
        ];
      case 'rightTriangle':
        return [Offset(0, h), Offset.zero, Offset(w, h)];
      case 'flowchart.manualInput':
        return [Offset(0, h * 0.2), Offset(w, 0), Offset(w, h), Offset(0, h)];
      case 'flowchart.manualOperation':
        return [
          Offset(w * 0.18, 0),
          Offset(w * 0.82, 0),
          Offset(w, h),
          Offset(0, h),
        ];
      case 'flowchart.offPageConnector':
        return [
          Offset.zero,
          Offset(w, 0),
          Offset(w, h * 0.72),
          Offset(w / 2, h),
          Offset(0, h * 0.72),
        ];
      case 'folder':
        return [
          Offset(0, h * 0.18),
          Offset(w * 0.38, h * 0.18),
          Offset(w * 0.48, 0),
          Offset(w * 0.82, 0),
          Offset(w, h * 0.18),
          Offset(w, h),
          Offset(0, h),
        ];
      case 'uml.package':
      case 'package':
        final tab = math.min(w * 0.35, 60.0);
        return [
          Offset(0, h * 0.16),
          Offset(tab, h * 0.16),
          Offset(tab + 8, 0),
          Offset(w, 0),
          Offset(w, h),
          Offset(0, h),
        ];
      case 'arrow':
      case 'doubleArrow':
      case 'leftRightArrow':
        return _arrowPoints(size);
      case 'upDownArrow':
        return _arrowPoints(
          Size(h, w),
        ).map((point) => Offset(point.dy, point.dx)).toList();
      case 'flowchart.document':
      case 'flowchart.documents':
      case 'mxgraph.bpmn.dataObject':
        return [
          Offset.zero,
          Offset(w, 0),
          Offset(w, h * 0.82),
          Offset(0, h * 0.82),
        ];
      case 'note':
        return [
          Offset.zero,
          Offset(w * 0.78, 0),
          Offset(w, h * 0.22),
          Offset(w, h),
          Offset(0, h),
        ];
      case 'callout':
      case 'speechBubble':
        return [
          Offset.zero,
          Offset(w, 0),
          Offset(w, h * 0.8),
          Offset(0, h * 0.8),
        ];
      case 'mxgraph.bpmn.message':
        return [
          Offset(w * 0.08, h * 0.2),
          Offset(w * 0.92, h * 0.2),
          Offset(w * 0.92, h * 0.8),
          Offset(w * 0.08, h * 0.8),
        ];
      default:
        return null;
    }
  }

  static Offset _cornerBisector(List<Offset> points, int index) {
    final point = points[index];
    final previous = points[(index - 1 + points.length) % points.length];
    final next = points[(index + 1) % points.length];
    final toPrevious = previous - point;
    final toNext = next - point;
    final previousLength = toPrevious.distance;
    final nextLength = toNext.distance;
    if (previousLength == 0 || nextLength == 0) return const Offset(1, 1);
    final direction = Offset(
      toPrevious.dx / previousLength + toNext.dx / nextLength,
      toPrevious.dy / previousLength + toNext.dy / nextLength,
    );
    final length = direction.distance;
    return length == 0
        ? const Offset(1, 1)
        : Offset(direction.dx / length, direction.dy / length);
  }

  static Path _roundedPolygon(List<Offset> points, double radius) {
    final path = Path();
    if (points.length < 3) return path;
    if (radius <= 0) {
      path.moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      return path..close();
    }

    final starts = <Offset>[];
    final ends = <Offset>[];
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final previous = points[(index - 1 + points.length) % points.length];
      final next = points[(index + 1) % points.length];
      final distance = math.min(
        radius,
        math.min((previous - point).distance, (next - point).distance) / 2,
      );
      final fromPrevious = (previous - point) / (previous - point).distance;
      final toNext = (next - point) / (next - point).distance;
      starts.add(point + fromPrevious * distance);
      ends.add(point + toNext * distance);
    }

    path.moveTo(starts.first.dx, starts.first.dy);
    for (var index = 0; index < points.length; index++) {
      final nextIndex = (index + 1) % points.length;
      path.lineTo(ends[index].dx, ends[index].dy);
      path.quadraticBezierTo(
        points[nextIndex].dx,
        points[nextIndex].dy,
        starts[nextIndex].dx,
        starts[nextIndex].dy,
      );
    }
    return path..close();
  }

  static List<Offset> _polygonPoints(
    Size size,
    int count, {
    double rotation = -math.pi / 2,
  }) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    return [
      for (var index = 0; index < count; index++)
        Offset(
          center.dx + math.cos(rotation + index * math.pi * 2 / count) * radius,
          center.dy + math.sin(rotation + index * math.pi * 2 / count) * radius,
        ),
    ];
  }

  static List<Offset> _arrowPoints(Size size) => [
    Offset(0, size.height * 0.3),
    Offset(size.width * 0.62, size.height * 0.3),
    Offset(size.width * 0.62, 0),
    Offset(size.width, size.height / 2),
    Offset(size.width * 0.62, size.height),
    Offset(size.width * 0.62, size.height * 0.7),
    Offset(0, size.height * 0.7),
  ];

  static Path _doubleArrowWithRadius(Size size, double radius) {
    final path = _roundedPolygon(_arrowPoints(size), radius);
    path.addPath(
      _roundedPolygon(_arrowPoints(size), radius),
      Offset(-size.width * 0.35, 0),
    );
    return path;
  }

  static Path _roundedRectWithRadius(Size size, double radius) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
    );

  static Path _predefinedProcessWithRadius(Size size, double radius) {
    final path = _roundedRectWithRadius(size, radius);
    path
      ..moveTo(size.width * 0.14, 0)
      ..lineTo(size.width * 0.14, size.height)
      ..moveTo(size.width * 0.86, 0)
      ..lineTo(size.width * 0.86, size.height);
    return path;
  }

  static Path _documentWithRadius(Size size, double radius) {
    final topRadius = math.min(
      radius,
      math.min(size.width, size.height * 0.82) / 2,
    );
    return Path()
      ..moveTo(topRadius, 0)
      ..lineTo(size.width - topRadius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, topRadius)
      ..lineTo(size.width, size.height * 0.82)
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height,
        size.width * 0.5,
        size.height * 0.82,
      )
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.64,
        0,
        size.height * 0.82,
      )
      ..lineTo(0, topRadius)
      ..quadraticBezierTo(0, 0, topRadius, 0)
      ..close();
  }

  static Path _multiDocumentWithRadius(Size size, double radius) {
    final path = Path();
    for (var offset = 0; offset < 3; offset++) {
      final dx = offset * size.width * 0.06;
      final dy = offset * size.height * 0.04;
      path.addPath(
        _documentWithRadius(Size(size.width - dx, size.height - dy), radius),
        Offset(dx, dy),
      );
    }
    return path;
  }

  static Path _internalStorageWithRadius(Size size, double radius) {
    final path = _roundedRectWithRadius(size, radius);
    path
      ..moveTo(size.width * 0.22, 0)
      ..lineTo(size.width * 0.22, size.height)
      ..moveTo(size.width * 0.44, 0)
      ..lineTo(size.width * 0.44, size.height);
    return path;
  }

  static Path _umlComponentWithRadius(Size size, double radius) {
    final path = _roundedRectWithRadius(size, radius);
    path
      ..addRect(Rect.fromLTWH(8, 8, size.width * 0.2, size.height * 0.16))
      ..addRect(
        Rect.fromLTWH(
          8,
          size.height * 0.32,
          size.width * 0.2,
          size.height * 0.16,
        ),
      );
    return path;
  }

  static Path _mobileWithRadius(Size size, double radius) {
    final path = _roundedRectWithRadius(size, radius);
    path.addOval(
      Rect.fromCircle(
        center: Offset(size.width / 2, size.height * 0.93),
        radius: math.min(size.width, size.height) * 0.035,
      ),
    );
    return path;
  }

  static Path _noteWithRadius(Size size, double radius) {
    final points = _cornerPoints('note', size)!;
    final path = _roundedPolygon(points, radius);
    path
      ..moveTo(size.width * 0.78, 0)
      ..lineTo(size.width * 0.78, size.height * 0.22)
      ..lineTo(size.width, size.height * 0.22);
    return path;
  }

  static Path _calloutWithRadius(Size size, double radius) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height * 0.8),
          Radius.circular(radius),
        ),
      )
      ..moveTo(size.width * 0.28, size.height * 0.8)
      ..lineTo(size.width * 0.2, size.height)
      ..lineTo(size.width * 0.5, size.height * 0.8);
    return path;
  }

  static Path _messageWithRadius(Size size, double radius) {
    final rect = Rect.fromLTWH(
      size.width * 0.08,
      size.height * 0.2,
      size.width * 0.84,
      size.height * 0.6,
    );
    return Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)))
      ..moveTo(rect.left, rect.top)
      ..lineTo(size.width / 2, size.height * 0.58)
      ..lineTo(rect.right, rect.top);
  }

  static DiagramShapeDefinition _shape(
    String id,
    String name,
    DiagramShapeCategory category,
    DiagramShapePathBuilder builder,
  ) => DiagramShapeDefinition(
    id: id,
    name: name,
    category: category,
    builder: builder,
  );

  static Path _rect(Size size) => Path()..addRect(Offset.zero & size);

  static Path _rectangle(Size size) => _rect(size);

  static Path _roundedRectangle(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(math.min(size.width, size.height) * 0.12),
      ),
    );

  static Path _ellipse(Size size) => Path()..addOval(Offset.zero & size);

  static Path _circle(Size size) {
    final diameter = math.min(size.width, size.height);
    final offset = Offset(
      (size.width - diameter) / 2,
      (size.height - diameter) / 2,
    );
    return Path()..addOval(offset & Size.square(diameter));
  }

  static Path _polygon(Size size, int count, {double rotation = -math.pi / 2}) {
    final path = Path();
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    for (var index = 0; index < count; index++) {
      final angle = rotation + index * math.pi * 2 / count;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  static Path _triangle(Size size) => _polygon(size, 3);

  static Path _invertedTriangle(Size size) =>
      _polygon(size, 3, rotation: math.pi / 2);

  static Path _hexagon(Size size) => _polygon(size, 6, rotation: 0);

  static Path _pentagon(Size size) => _polygon(size, 5);

  static Path _octagon(Size size) => _polygon(size, 8, rotation: math.pi / 8);

  static Path _rhombus(Size size) => Path()
    ..moveTo(size.width / 2, 0)
    ..lineTo(size.width, size.height / 2)
    ..lineTo(size.width / 2, size.height)
    ..lineTo(0, size.height / 2)
    ..close();

  static Path _parallelogram(Size size) {
    final skew = size.width * 0.18;
    return Path()
      ..moveTo(skew, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - skew, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  static Path _trapezoid(Size size) {
    final inset = size.width * 0.18;
    return Path()
      ..moveTo(inset, 0)
      ..lineTo(size.width - inset, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  static Path _rightTriangle(Size size) => Path()
    ..moveTo(0, size.height)
    ..lineTo(0, 0)
    ..lineTo(size.width, size.height)
    ..close();

  static Path _predefinedProcess(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height * 0.08),
      ),
    )
    ..moveTo(size.width * 0.14, 0)
    ..lineTo(size.width * 0.14, size.height)
    ..moveTo(size.width * 0.86, 0)
    ..lineTo(size.width * 0.86, size.height);

  static Path _document(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height * 0.82)
    ..quadraticBezierTo(
      size.width * 0.75,
      size.height,
      size.width * 0.5,
      size.height * 0.82,
    )
    ..quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.64,
      0,
      size.height * 0.82,
    )
    ..close();

  static Path _multiDocument(Size size) {
    final path = Path();
    for (var offset = 0; offset < 3; offset++) {
      final dx = offset * size.width * 0.06;
      final dy = offset * size.height * 0.04;
      path.addPath(
        _document(Size(size.width - dx, size.height - dy)),
        Offset(dx, dy),
      );
    }
    return path;
  }

  static Path _manualInput(Size size) {
    return Path()
      ..moveTo(0, size.height * 0.2)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  static Path _manualOperation(Size size) => Path()
    ..moveTo(size.width * 0.18, 0)
    ..lineTo(size.width * 0.82, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  static Path _delay(Size size) => Path()
    ..moveTo(size.height * 0.5, 0)
    ..lineTo(size.width - size.height * 0.5, 0)
    ..arcToPoint(
      Offset(size.width - size.height * 0.5, size.height),
      radius: Radius.circular(size.height * 0.5),
      clockwise: true,
    )
    ..lineTo(size.height * 0.5, size.height)
    ..close();

  static Path _preparation(Size size) {
    final inset = size.width * 0.16;
    return Path()
      ..moveTo(inset, 0)
      ..lineTo(size.width - inset, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width - inset, size.height)
      ..lineTo(inset, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
  }

  static Path _internalStorage(Size size) => Path()
    ..addRect(Offset.zero & size)
    ..moveTo(size.width * 0.22, 0)
    ..lineTo(size.width * 0.22, size.height)
    ..moveTo(size.width * 0.44, 0)
    ..lineTo(size.width * 0.44, size.height);

  static Path _offPageConnector(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height * 0.72)
    ..lineTo(size.width / 2, size.height)
    ..lineTo(0, size.height * 0.72)
    ..close();

  static Path _display(Size size) => Path()
    ..moveTo(size.width * 0.16, 0)
    ..lineTo(size.width * 0.84, 0)
    ..quadraticBezierTo(
      size.width,
      size.height / 2,
      size.width * 0.84,
      size.height,
    )
    ..lineTo(size.width * 0.16, size.height)
    ..quadraticBezierTo(0, size.height / 2, size.width * 0.16, 0)
    ..close();

  static Path _or(Size size) => Path()
    ..addOval(Offset.zero & size)
    ..moveTo(0, size.height / 2)
    ..lineTo(size.width, size.height / 2);

  static Path _summing(Size size) {
    final path = Path()..addOval(Offset.zero & size);
    path
      ..moveTo(size.width * 0.25, size.height * 0.25)
      ..lineTo(size.width * 0.75, size.height * 0.75)
      ..moveTo(size.width * 0.75, size.height * 0.25)
      ..lineTo(size.width * 0.25, size.height * 0.75);
    return path;
  }

  static Path _cylinder(Size size) {
    final cap = size.height * 0.18;
    return Path()
      ..moveTo(0, cap)
      ..cubicTo(0, 0, size.width, 0, size.width, cap)
      ..lineTo(size.width, size.height - cap)
      ..cubicTo(size.width, size.height, 0, size.height, 0, size.height - cap)
      ..close();
  }

  static Path _umlClass(Size size) => _rectangle(size);

  static Path _umlInterface(Size size) => _roundedRectangle(size);

  static Path _umlComponent(Size size) {
    final path = _roundedRectangle(size);
    path
      ..addRect(Rect.fromLTWH(8, 8, size.width * 0.2, size.height * 0.16))
      ..addRect(
        Rect.fromLTWH(
          8,
          size.height * 0.32,
          size.width * 0.2,
          size.height * 0.16,
        ),
      );
    return path;
  }

  static Path _umlPackage(Size size) {
    final tab = math.min(size.width * 0.35, 60.0);
    return Path()
      ..moveTo(0, size.height * 0.16)
      ..lineTo(tab, size.height * 0.16)
      ..lineTo(tab + 8, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  static Path _umlObject(Size size) => _rectangle(size);

  static Path _actor(Size size) {
    final path = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width / 2, size.height * 0.18),
          radius: math.min(size.width, size.height) * 0.12,
        ),
      )
      ..moveTo(size.width / 2, size.height * 0.3)
      ..lineTo(size.width / 2, size.height * 0.7)
      ..moveTo(size.width * 0.22, size.height * 0.46)
      ..lineTo(size.width * 0.78, size.height * 0.46)
      ..moveTo(size.width / 2, size.height * 0.7)
      ..lineTo(size.width * 0.24, size.height)
      ..moveTo(size.width / 2, size.height * 0.7)
      ..lineTo(size.width * 0.76, size.height);
    return path;
  }

  static Path _control(Size size) => _roundedRectangle(size);

  static Path _entity(Size size) => _ellipse(size);

  static Path _bpmnEvent(Size size) {
    final path = Path()..addOval(Offset.zero & size);
    final inner = Rect.fromLTWH(
      size.width * 0.14,
      size.height * 0.14,
      size.width * 0.72,
      size.height * 0.72,
    );
    return path..addOval(inner);
  }

  static Path _subprocess(Size size) => _predefinedProcess(size);

  static Path _pool(Size size) => _rectangle(size);

  static Path _message(Size size) => Path()
    ..moveTo(size.width * 0.08, size.height * 0.2)
    ..lineTo(size.width * 0.92, size.height * 0.2)
    ..lineTo(size.width * 0.92, size.height * 0.8)
    ..lineTo(size.width * 0.08, size.height * 0.8)
    ..close()
    ..moveTo(size.width * 0.08, size.height * 0.2)
    ..lineTo(size.width / 2, size.height * 0.58)
    ..lineTo(size.width * 0.92, size.height * 0.2);

  static Path _timer(Size size) => _ellipse(size);

  static Path _server(Size size) => _roundedRectangle(size);

  static Path _router(Size size) => _hexagon(size);

  static Path _cloud(Size size) {
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.75)
      ..cubicTo(
        size.width * 0.02,
        size.height * 0.75,
        size.width * 0.02,
        size.height * 0.35,
        size.width * 0.25,
        size.height * 0.35,
      )
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.02,
        size.width * 0.72,
        size.height * 0.02,
        size.width * 0.76,
        size.height * 0.35,
      )
      ..cubicTo(
        size.width * 1.05,
        size.height * 0.3,
        size.width * 1.02,
        size.height * 0.75,
        size.width * 0.8,
        size.height * 0.75,
      )
      ..close();
    return path;
  }

  static Path _client(Size size) => _rectangle(size);

  static Path _mobile(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(math.min(size.width, size.height) * 0.12),
      ),
    )
    ..addOval(
      Rect.fromCircle(
        center: Offset(size.width / 2, size.height * 0.93),
        radius: math.min(size.width, size.height) * 0.035,
      ),
    );

  static Path _firewall(Size size) => _trapezoid(size);

  static Path _switch(Size size) => _hexagon(size);

  static Path _person(Size size) => _actor(size);

  static Path _note(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width * 0.78, 0)
    ..lineTo(size.width, size.height * 0.22)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close()
    ..moveTo(size.width * 0.78, 0)
    ..lineTo(size.width * 0.78, size.height * 0.22)
    ..lineTo(size.width, size.height * 0.22);

  static Path _callout(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height * 0.8),
        const Radius.circular(10),
      ),
    )
    ..moveTo(size.width * 0.28, size.height * 0.8)
    ..lineTo(size.width * 0.2, size.height)
    ..lineTo(size.width * 0.5, size.height * 0.8);

  static Path _speechBubble(Size size) => _callout(size);

  static Path _container(Size size) => _roundedRectangle(size);

  static Path _folder(Size size) => Path()
    ..moveTo(0, size.height * 0.18)
    ..lineTo(size.width * 0.38, size.height * 0.18)
    ..lineTo(size.width * 0.48, 0)
    ..lineTo(size.width * 0.82, 0)
    ..lineTo(size.width, size.height * 0.18)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  static Path _arrow(Size size) => Path()
    ..moveTo(0, size.height * 0.3)
    ..lineTo(size.width * 0.62, size.height * 0.3)
    ..lineTo(size.width * 0.62, 0)
    ..lineTo(size.width, size.height / 2)
    ..lineTo(size.width * 0.62, size.height)
    ..lineTo(size.width * 0.62, size.height * 0.7)
    ..lineTo(0, size.height * 0.7)
    ..close();

  static Path _doubleArrow(Size size) => Path()
    ..addPath(_arrow(size), Offset.zero)
    ..addPath(_arrow(size), Offset(-size.width * 0.35, 0));

  static Path _leftRightArrow(Size size) => _doubleArrow(size);

  static Path _upDownArrow(Size size) =>
      _doubleArrow(Size(size.height, size.width));
}
