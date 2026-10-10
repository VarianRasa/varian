import 'package:flutter/material.dart';
import 'node_payload.dart';

enum AnchorPosition { top, right, bottom, left }

enum ConnectorRouting { straight, orthogonal, curved }

class CanvasEdge {
  static const maxWaypoints = 64;

  final String id;
  final String? sourceNodeId;
  final AnchorPosition sourceAnchor;
  final Offset? sourcePoint;
  final String? targetNodeId;
  final AnchorPosition targetAnchor;
  final Offset? targetPoint;
  final ConnectorRouting routing;
  final Color strokeColor;
  final double strokeWidth;
  final StrokeStyle strokeStyle;
  final LineMarker startMarker;
  final LineMarker endMarker;
  final bool isAnimated;
  final String? label;
  final double _labelPosition;
  final List<Offset> waypoints;
  final String? mermaidSourceId;
  final String? parentId;
  final String? rawDrawioStyle;
  final String? rawDrawioCellXml;

  const CanvasEdge({
    required this.id,
    this.sourceNodeId,
    this.sourceAnchor = AnchorPosition.right,
    this.sourcePoint,
    this.targetNodeId,
    this.targetAnchor = AnchorPosition.left,
    this.targetPoint,
    this.routing = ConnectorRouting.orthogonal,
    this.strokeColor = const Color(0xFF94A3B8),
    this.strokeWidth = 2.0,
    this.strokeStyle = StrokeStyle.solid,
    this.startMarker = LineMarker.none,
    this.endMarker = LineMarker.arrow,
    this.isAnimated = false,
    this.label,
    double labelPosition = 0.5,
    this.waypoints = const [],
    this.mermaidSourceId,
    this.parentId,
    this.rawDrawioStyle,
    this.rawDrawioCellXml,
  }) : _labelPosition = labelPosition; // ignore: prefer_initializing_formals

  CanvasEdge copyWith({
    String? id,
    Object? sourceNodeId = _sentinel,
    AnchorPosition? sourceAnchor,
    Object? sourcePoint = _sentinel,
    Object? targetNodeId = _sentinel,
    AnchorPosition? targetAnchor,
    Object? targetPoint = _sentinel,
    ConnectorRouting? routing,
    Color? strokeColor,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    LineMarker? startMarker,
    LineMarker? endMarker,
    bool? isAnimated,
    Object? label = _sentinel,
    double? labelPosition,
    List<Offset>? waypoints,
    Object? mermaidSourceId = _sentinel,
    Object? parentId = _sentinel,
    Object? rawDrawioStyle = _sentinel,
    Object? rawDrawioCellXml = _sentinel,
  }) {
    return CanvasEdge(
      id: id ?? this.id,
      sourceNodeId: sourceNodeId == _sentinel
          ? this.sourceNodeId
          : sourceNodeId as String?,
      sourceAnchor: sourceAnchor ?? this.sourceAnchor,
      sourcePoint: sourcePoint == _sentinel
          ? this.sourcePoint
          : sourcePoint as Offset?,
      targetNodeId: targetNodeId == _sentinel
          ? this.targetNodeId
          : targetNodeId as String?,
      targetAnchor: targetAnchor ?? this.targetAnchor,
      targetPoint: targetPoint == _sentinel
          ? this.targetPoint
          : targetPoint as Offset?,
      routing: routing ?? this.routing,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeStyle: strokeStyle ?? this.strokeStyle,
      startMarker: startMarker ?? this.startMarker,
      endMarker: endMarker ?? this.endMarker,
      isAnimated: isAnimated ?? this.isAnimated,
      label: label == _sentinel ? this.label : label as String?,
      labelPosition: labelPosition == null
          ? this.labelPosition
          : _normalizeLabelPosition(labelPosition),
      waypoints: waypoints ?? this.waypoints,
      mermaidSourceId: mermaidSourceId == _sentinel
          ? this.mermaidSourceId
          : mermaidSourceId as String?,
      parentId: parentId == _sentinel ? this.parentId : parentId as String?,
      rawDrawioStyle: rawDrawioStyle == _sentinel
          ? this.rawDrawioStyle
          : rawDrawioStyle as String?,
      rawDrawioCellXml: rawDrawioCellXml == _sentinel
          ? this.rawDrawioCellXml
          : rawDrawioCellXml as String?,
    );
  }

  static const Object _sentinel = Object();

  double get labelPosition => _normalizeLabelPosition(_labelPosition);

  double get normalizedLabelPosition => labelPosition;

  static double _normalizeLabelPosition(double value) {
    if (!value.isFinite) return 0.5;
    return value.clamp(0.0, 1.0).toDouble();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceNodeId': sourceNodeId,
    'sourceAnchor': sourceAnchor.name,
    'sourcePoint': _pointToJson(sourcePoint),
    'targetNodeId': targetNodeId,
    'targetAnchor': targetAnchor.name,
    'targetPoint': _pointToJson(targetPoint),
    'routing': routing.name,
    'strokeColor': strokeColor.toARGB32(),
    'strokeWidth': strokeWidth,
    'strokeStyle': strokeStyle.name,
    'startMarker': startMarker.name,
    'endMarker': endMarker.name,
    'isAnimated': isAnimated,
    'label': label,
    'labelPosition': normalizedLabelPosition,
    'waypoints': waypoints
        .take(maxWaypoints)
        .where((point) => point.dx.isFinite && point.dy.isFinite)
        .map(_pointToJson)
        .toList(growable: false),
    if (mermaidSourceId != null) 'mermaidSourceId': mermaidSourceId,
    if (parentId != null) 'parentId': parentId,
    if (rawDrawioStyle != null) 'rawDrawioStyle': rawDrawioStyle,
    if (rawDrawioCellXml != null) 'rawDrawioCellXml': rawDrawioCellXml,
  };

  Map<String, dynamic> toPersistenceJson() => toJson();

  factory CanvasEdge.fromJson(Map<String, dynamic> json) {
    return CanvasEdge(
      id: json['id'] as String,
      sourceNodeId: json['sourceNodeId'] as String?,
      sourceAnchor: AnchorPosition.values.firstWhere(
        (e) => e.name == json['sourceAnchor'],
        orElse: () => AnchorPosition.right,
      ),
      sourcePoint: _pointFromJson(json['sourcePoint']),
      targetNodeId: json['targetNodeId'] as String?,
      targetAnchor: AnchorPosition.values.firstWhere(
        (e) => e.name == json['targetAnchor'],
        orElse: () => AnchorPosition.left,
      ),
      targetPoint: _pointFromJson(json['targetPoint']),
      routing: ConnectorRouting.values.firstWhere(
        (e) => e.name == json['routing'],
        orElse: () => ConnectorRouting.orthogonal,
      ),
      strokeColor: Color((json['strokeColor'] as num?)?.toInt() ?? 0xFF94A3B8),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      strokeStyle: StrokeStyle.values.firstWhere(
        (e) => e.name == json['strokeStyle'],
        orElse: () => StrokeStyle.solid,
      ),
      startMarker: LineMarker.values.firstWhere(
        (e) => e.name == json['startMarker'],
        orElse: () => LineMarker.none,
      ),
      endMarker: LineMarker.values.firstWhere(
        (e) => e.name == json['endMarker'],
        orElse: () => LineMarker.arrow,
      ),
      isAnimated: json['isAnimated'] as bool? ?? false,
      label: json['label'] as String?,
      labelPosition: _labelPositionFromJson(json['labelPosition']),
      waypoints: _waypointsFromJson(json['waypoints']),
      mermaidSourceId: json['mermaidSourceId'] as String?,
      parentId: json['parentId'] as String?,
      rawDrawioStyle: json['rawDrawioStyle'] as String?,
      rawDrawioCellXml: json['rawDrawioCellXml'] as String?,
    );
  }

  static Map<String, double>? _pointToJson(Offset? point) =>
      point == null ? null : {'x': point.dx, 'y': point.dy};

  static Offset? _pointFromJson(Object? raw) {
    if (raw is! Map) return null;
    final x = (raw['x'] as num?)?.toDouble();
    final y = (raw['y'] as num?)?.toDouble();
    if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
    return Offset(x, y);
  }

  static double _labelPositionFromJson(Object? raw) {
    final value = raw is num ? raw.toDouble() : null;
    return value == null ? 0.5 : _normalizeLabelPosition(value);
  }

  static List<Offset> _waypointsFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .take(maxWaypoints)
        .map(_pointFromJson)
        .whereType<Offset>()
        .toList(growable: false);
  }
}
