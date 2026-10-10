import 'dart:ui';
import 'node_payload.dart';
import 'prototype_interaction.dart';
import '../../features/canvas/domain/canvas_precision.dart';

class CanvasNode {
  final String id;
  final NodeType type;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final double opacity;
  final int zIndex;
  final bool visible;
  final bool locked;
  final int? layerColor;
  final String? parentId;
  final String? pageId;
  final String? variantOfNodeId;
  final String? mermaidSourceId;
  final String? name;
  final List<ImageAnnotationPin> pins;
  final CanvasNodeConstraints? constraints;
  final List<PrototypeInteraction> prototypeInteractions;
  final String? prototypeStateId;
  final NodePayload payload;

  const CanvasNode({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.zIndex = 0,
    this.visible = true,
    this.locked = false,
    this.layerColor,
    this.parentId,
    this.pageId,
    this.variantOfNodeId,
    this.mermaidSourceId,
    this.name,
    this.pins = const [],
    this.constraints,
    this.prototypeInteractions = const [],
    this.prototypeStateId,
    required this.payload,
  });

  Rect get bounds => Rect.fromLTWH(x, y, width, height);

  CanvasNode copyWith({
    String? id,
    NodeType? type,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    double? opacity,
    int? zIndex,
    bool? visible,
    bool? locked,
    Object? layerColor = _sentinel,
    Object? parentId = _sentinel,
    Object? pageId = _sentinel,
    Object? variantOfNodeId = _sentinel,
    Object? mermaidSourceId = _sentinel,
    Object? name = _sentinel,
    List<ImageAnnotationPin>? pins,
    Object? constraints = _sentinel,
    List<PrototypeInteraction>? prototypeInteractions,
    Object? prototypeStateId = _sentinel,
    NodePayload? payload,
  }) {
    return CanvasNode(
      id: id ?? this.id,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      zIndex: zIndex ?? this.zIndex,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      layerColor: layerColor == _sentinel
          ? this.layerColor
          : layerColor as int?,
      parentId: parentId == _sentinel ? this.parentId : parentId as String?,
      pageId: pageId == _sentinel ? this.pageId : pageId as String?,
      variantOfNodeId: variantOfNodeId == _sentinel
          ? this.variantOfNodeId
          : variantOfNodeId as String?,
      mermaidSourceId: mermaidSourceId == _sentinel
          ? this.mermaidSourceId
          : mermaidSourceId as String?,
      name: name == _sentinel ? this.name : name as String?,
      pins: pins ?? this.pins,
      constraints: constraints == _sentinel
          ? this.constraints
          : constraints as CanvasNodeConstraints?,
      prototypeInteractions:
          prototypeInteractions ?? this.prototypeInteractions,
      prototypeStateId: prototypeStateId == _sentinel
          ? this.prototypeStateId
          : prototypeStateId as String?,
      payload: payload ?? this.payload,
    );
  }

  static const Object _sentinel = Object();

  Map<String, dynamic> toJson() => _toJson(payload.toJson());

  /// Durable node envelope. Runtime delivery paths, URLs, object URLs, and
  /// provider output are removed by the payload persistence projection.
  Map<String, dynamic> toPersistenceJson() =>
      _toJson(payload.toPersistenceJson());

  Map<String, dynamic> _toJson(Map<String, dynamic> payloadJson) => {
    'id': id,
    'type': type.name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': rotation,
    'opacity': opacity,
    'zIndex': zIndex,
    'visible': visible,
    'locked': locked,
    if (layerColor != null) 'layerColor': layerColor,
    'parentId': parentId,
    'pageId': pageId,
    'variantOfNodeId': variantOfNodeId,
    if (mermaidSourceId != null) 'mermaidSourceId': mermaidSourceId,
    'name': name,
    'pins': pins.map((p) => p.toJson()).toList(),
    if (constraints != null) 'constraints': constraints!.toJson(),
    'prototypeInteractions': prototypeInteractions
        .map((interaction) => interaction.toJson())
        .toList(),
    'prototypeStateId': prototypeStateId,
    'payload': payloadJson,
  };

  factory CanvasNode.fromJson(Map<String, dynamic> json) {
    final type = NodeType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => NodeType.rectangle,
    );

    return CanvasNode(
      id: json['id'] as String,
      type: type,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      visible: json['visible'] as bool? ?? true,
      locked: json['locked'] as bool? ?? false,
      layerColor: (json['layerColor'] as num?)?.toInt(),
      parentId: json['parentId'] as String?,
      pageId: json['pageId'] as String?,
      variantOfNodeId: json['variantOfNodeId'] as String?,
      mermaidSourceId: json['mermaidSourceId'] as String?,
      name: json['name'] as String?,
      pins:
          (json['pins'] as List<dynamic>?)
              ?.map(
                (e) => ImageAnnotationPin.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      constraints: json['constraints'] == null
          ? null
          : CanvasNodeConstraints.fromJson(json['constraints']),
      prototypeInteractions:
          (json['prototypeInteractions'] as List<dynamic>?)
              ?.map(
                (item) => PrototypeInteraction.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList() ??
          const [],
      prototypeStateId: json['prototypeStateId'] as String?,
      payload: NodePayload.fromJson(
        type,
        json['payload'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}
