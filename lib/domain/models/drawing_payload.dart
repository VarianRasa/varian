import 'dart:ui';
import 'package:flutter/material.dart';
import 'node_payload.dart';

enum BrushType {
  ink,
  marker,
  airbrush,
  highlighter,
  calligraphy,
  pencil,
  eraser,
}

enum EraserMode { stroke, segment }

class EraserCutout {
  final Offset position;
  final double radius;

  const EraserCutout({required this.position, required this.radius});

  Map<String, dynamic> toJson() => {
    'x': position.dx,
    'y': position.dy,
    'r': radius,
  };

  factory EraserCutout.fromJson(Map<String, dynamic> json) => EraserCutout(
    position: Offset(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    ),
    radius: (json['r'] as num).toDouble(),
  );
}

class DrawingPayload extends NodePayload {
  final List<Offset> points;
  final Color strokeColor;
  final double strokeWidth;
  final BrushType brushType;
  final double opacity;
  final bool isSmoothed;
  final List<EraserCutout> cutouts;
  final List<int> controlPointIndices;

  DrawingPayload({
    this.points = const [],
    this.strokeColor = const Color(0xFFF97316), // Retro Signal Orange
    this.strokeWidth = 3.0,
    this.brushType = BrushType.ink,
    this.opacity = 1.0,
    this.isSmoothed = true,
    this.cutouts = const [],
    this.controlPointIndices = const [],
  });

  factory DrawingPayload.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List<dynamic>? ?? [];
    final rawCutouts = json['cutouts'] as List<dynamic>? ?? [];
    final rawIndices = json['controlPointIndices'] as List<dynamic>? ?? [];
    final brushName = json['brushType'] as String? ?? 'ink';
    return DrawingPayload(
      points: rawPoints
          .map(
            (p) =>
                Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
          )
          .toList(),
      strokeColor: Color((json['strokeColor'] as num?)?.toInt() ?? 0xFF6366F1),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 3.0,
      brushType: BrushType.values.firstWhere(
        (b) => b.name == brushName,
        orElse: () => BrushType.ink,
      ),
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      isSmoothed: json['isSmoothed'] as bool? ?? true,
      cutouts: rawCutouts
          .map((c) => EraserCutout.fromJson(c as Map<String, dynamic>))
          .toList(),
      controlPointIndices: rawIndices.map((i) => (i as num).toInt()).toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
    'strokeColor': strokeColor.toARGB32(),
    'strokeWidth': strokeWidth,
    'brushType': brushType.name,
    'opacity': opacity,
    'isSmoothed': isSmoothed,
    'cutouts': cutouts.map((c) => c.toJson()).toList(),
    'controlPointIndices': controlPointIndices,
  };

  @override
  DrawingPayload clone() => DrawingPayload(
    points: List.of(points),
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
    brushType: brushType,
    opacity: opacity,
    isSmoothed: isSmoothed,
    cutouts: List.of(cutouts),
    controlPointIndices: List.of(controlPointIndices),
  );

  DrawingPayload copyWith({
    List<Offset>? points,
    Color? strokeColor,
    double? strokeWidth,
    BrushType? brushType,
    double? opacity,
    bool? isSmoothed,
    List<EraserCutout>? cutouts,
    List<int>? controlPointIndices,
  }) {
    return DrawingPayload(
      points: points ?? this.points,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      brushType: brushType ?? this.brushType,
      opacity: opacity ?? this.opacity,
      isSmoothed: isSmoothed ?? this.isSmoothed,
      cutouts: cutouts ?? this.cutouts,
      controlPointIndices: controlPointIndices ?? this.controlPointIndices,
    );
  }
}
