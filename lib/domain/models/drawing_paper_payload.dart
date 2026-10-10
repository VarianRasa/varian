import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'node_payload.dart';
import '../../features/drawing_paper/domain/models/manga_frame.dart';
import '../../features/drawing_paper/domain/models/raster_edit_operation.dart';
import '../../features/drawing_paper/domain/models/ruler_guide.dart';
import '../../features/drawing_paper/domain/models/selection_mask.dart';
import 'durable_asset_reference.dart';

enum PaperPresetType {
  a4,
  a5,
  b5,
  mangaPage,
  comicStandard,
  screen4k,
  screen1080p,
  square,
  custom,
}

enum PaperTextureType {
  none,
  roughGrain,
  coldPressWatercolor,
  mangaScreenTone,
  canvasFabric,
}

class PaperPresetSpec {
  final String name;
  final double widthMm;
  final double heightMm;
  final int pixelWidth;
  final int pixelHeight;
  final double defaultDpi;
  final String description;

  const PaperPresetSpec({
    required this.name,
    required this.widthMm,
    required this.heightMm,
    required this.pixelWidth,
    required this.pixelHeight,
    this.defaultDpi = 300.0,
    required this.description,
  });

  static const List<PaperPresetSpec> presets = [
    PaperPresetSpec(
      name: 'A4 Portrait',
      widthMm: 210,
      heightMm: 297,
      pixelWidth: 2480,
      pixelHeight: 3508,
      defaultDpi: 300,
      description: 'Standard print document (210 x 297 mm)',
    ),
    PaperPresetSpec(
      name: 'A4 Landscape',
      widthMm: 297,
      heightMm: 210,
      pixelWidth: 3508,
      pixelHeight: 2480,
      defaultDpi: 300,
      description: 'Standard horizontal print (297 x 210 mm)',
    ),
    PaperPresetSpec(
      name: 'A5 Notebook',
      widthMm: 148,
      heightMm: 210,
      pixelWidth: 1748,
      pixelHeight: 2480,
      defaultDpi: 300,
      description: 'Compact sketchbook format (148 x 210 mm)',
    ),
    PaperPresetSpec(
      name: 'B5 Manga/Doujin',
      widthMm: 182,
      heightMm: 257,
      pixelWidth: 2150,
      pixelHeight: 3035,
      defaultDpi: 300,
      description: 'Standard Japanese comic tankobon (182 x 257 mm)',
    ),
    PaperPresetSpec(
      name: 'Manga B4 (Commercial)',
      widthMm: 250,
      heightMm: 353,
      pixelWidth: 2953,
      pixelHeight: 4170,
      defaultDpi: 300,
      description: 'Professional commercial manga manuscript page',
    ),
    PaperPresetSpec(
      name: '4K Ultra HD',
      widthMm: 0,
      heightMm: 0,
      pixelWidth: 3840,
      pixelHeight: 2160,
      defaultDpi: 150,
      description: 'High-resolution digital illustration (16:9)',
    ),
    PaperPresetSpec(
      name: '1080p Full HD',
      widthMm: 0,
      heightMm: 0,
      pixelWidth: 1920,
      pixelHeight: 1080,
      defaultDpi: 150,
      description: 'Standard screen canvas (1920 x 1080)',
    ),
    PaperPresetSpec(
      name: 'Square 1:1 Art',
      widthMm: 0,
      heightMm: 0,
      pixelWidth: 2048,
      pixelHeight: 2048,
      defaultDpi: 300,
      description: 'Social media / Album cover square format',
    ),
  ];
}

enum LayerType { raster, vector, folder, adjustment }

enum AdjustmentFilterType {
  brightnessContrast,
  hueSaturation,
  invert,
  colorBalance,
  curves,
}

class DrawingStrokePoint {
  final double x;
  final double y;
  final double pressure;
  final double tilt;
  final int timestamp;

  const DrawingStrokePoint({
    required this.x,
    required this.y,
    this.pressure = 1.0,
    this.tilt = 0.0,
    this.timestamp = 0,
  });

  Offset get offset => Offset(x, y);

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'p': pressure,
    't': tilt,
    'ts': timestamp,
  };

  factory DrawingStrokePoint.fromJson(Map<String, dynamic> json) =>
      DrawingStrokePoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        pressure: (json['p'] as num?)?.toDouble() ?? 1.0,
        tilt: (json['t'] as num?)?.toDouble() ?? 0.0,
        timestamp: (json['ts'] as num?)?.toInt() ?? 0,
      );

  DrawingStrokePoint copyWith({
    double? x,
    double? y,
    double? pressure,
    double? tilt,
    int? timestamp,
  }) => DrawingStrokePoint(
    x: x ?? this.x,
    y: y ?? this.y,
    pressure: pressure ?? this.pressure,
    tilt: tilt ?? this.tilt,
    timestamp: timestamp ?? this.timestamp,
  );
}

enum StudioBrushCategory {
  inkPen,
  gPen,
  maruPen,
  fudeBrush,
  marker,
  airbrush,
  pencilRough,
  oilPastel,
  watercolor,
  screentoneBrush,
  specialPen,
  eraserHard,
  eraserSoft,
  eraserVector,
  smudge,
  blurTool,
  bucketFill,
  lassoFill,
}

enum ScreenToneType { none, dot, line, cross, wave }

enum ShapeKind {
  line,
  rectangle,
  roundedRectangle,
  ellipse,
  polygon,
  star,
  arrow,
}

class VectorShapeObject {
  final String id;
  final ShapeKind kind;
  final List<Offset> points;
  final Color fill;
  final Color stroke;
  final double strokeWidth;
  final double rotation;
  final ScreenToneType toneType;
  final double toneFrequency; // LPI-like
  final double toneAngle;

  const VectorShapeObject({
    required this.id,
    required this.kind,
    this.points = const [],
    this.fill = const Color(0x00000000),
    this.stroke = const Color(0xFF000000),
    this.strokeWidth = 2.0,
    this.rotation = 0.0,
    this.toneType = ScreenToneType.none,
    this.toneFrequency = 24.0,
    this.toneAngle = 45.0,
  });

  Rect? get bounds => points.isEmpty ? null : boundsOf(points);

  static Rect boundsOf(List<Offset> pts) {
    double l = double.infinity,
        t = double.infinity,
        r = -double.infinity,
        b = -double.infinity;
    for (final p in pts) {
      if (p.dx < l) l = p.dx;
      if (p.dy < t) t = p.dy;
      if (p.dx > r) r = p.dx;
      if (p.dy > b) b = p.dy;
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  Path toPath() {
    final path = Path();
    if (points.isEmpty) return path;

    switch (kind) {
      case ShapeKind.line:
        path.moveTo(points.first.dx, points.first.dy);
        path.lineTo(points.last.dx, points.last.dy);
        break;
      case ShapeKind.rectangle:
      case ShapeKind.roundedRectangle:
        final rect = boundsOf(points);
        if (kind == ShapeKind.roundedRectangle) {
          path.addRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(10)),
          );
        } else {
          path.addRect(rect);
        }
        break;
      case ShapeKind.ellipse:
        path.addOval(boundsOf(points));
        break;
      case ShapeKind.polygon:
      case ShapeKind.star:
        if (points.length >= 2) {
          final rect = boundsOf(points);
          final center = rect.center;
          final radius = math.min(rect.width, rect.height) / 2;
          final vertexCount = kind == ShapeKind.star ? 10 : 6;
          for (int i = 0; i < vertexCount; i++) {
            final angle = -math.pi / 2 + i * 2 * math.pi / vertexCount;
            final vertexRadius = kind == ShapeKind.star && i.isOdd
                ? radius * 0.45
                : radius;
            final vertex = Offset(
              center.dx + math.cos(angle) * vertexRadius,
              center.dy + math.sin(angle) * vertexRadius,
            );
            if (i == 0) {
              path.moveTo(vertex.dx, vertex.dy);
            } else {
              path.lineTo(vertex.dx, vertex.dy);
            }
          }
          path.close();
        }
        break;
      case ShapeKind.arrow:
        if (points.length >= 2) {
          final start = points.first;
          final end = points.last;
          final delta = end - start;
          final distance = delta.distance;
          if (distance > 0) {
            final unit = delta / distance;
            final normal = Offset(-unit.dy, unit.dx);
            final headLength = math.min(28.0, distance * 0.35);
            final headWidth = headLength * 0.55;
            final base = end - unit * headLength;
            path
              ..moveTo(start.dx, start.dy)
              ..lineTo(end.dx, end.dy)
              ..moveTo(
                (base + normal * headWidth).dx,
                (base + normal * headWidth).dy,
              )
              ..lineTo(end.dx, end.dy)
              ..lineTo(
                (base - normal * headWidth).dx,
                (base - normal * headWidth).dy,
              );
          }
        }
        break;
    }
    return path;
  }

  Offset arrowHeadPoint() {
    if (points.length < 2) return Offset.zero;
    return points.last;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
    'fill': fill.toARGB32(),
    'stroke': stroke.toARGB32(),
    'strokeWidth': strokeWidth,
    'rotation': rotation,
    'toneType': toneType.name,
    'toneFrequency': toneFrequency,
    'toneAngle': toneAngle,
  };

  factory VectorShapeObject.fromJson(Map<String, dynamic> json) =>
      VectorShapeObject(
        id:
            json['id'] as String? ??
            'shape_${DateTime.now().microsecondsSinceEpoch}',
        kind: ShapeKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => ShapeKind.rectangle,
        ),
        points:
            (json['points'] as List<dynamic>?)
                ?.map(
                  (p) => Offset(
                    (p['x'] as num).toDouble(),
                    (p['y'] as num).toDouble(),
                  ),
                )
                .toList() ??
            const [],
        fill: Color((json['fill'] as num?)?.toInt() ?? 0x00000000),
        stroke: Color((json['stroke'] as num?)?.toInt() ?? 0xFF000000),
        strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
        toneType: ScreenToneType.values.firstWhere(
          (t) => t.name == json['toneType'],
          orElse: () => ScreenToneType.none,
        ),
        toneFrequency: (json['toneFrequency'] as num?)?.toDouble() ?? 24.0,
        toneAngle: (json['toneAngle'] as num?)?.toDouble() ?? 45.0,
      );

  VectorShapeObject copyWith({
    String? id,
    ShapeKind? kind,
    List<Offset>? points,
    Color? fill,
    Color? stroke,
    double? strokeWidth,
    double? rotation,
    ScreenToneType? toneType,
    double? toneFrequency,
    double? toneAngle,
  }) => VectorShapeObject(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    points: points ?? this.points,
    fill: fill ?? this.fill,
    stroke: stroke ?? this.stroke,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    rotation: rotation ?? this.rotation,
    toneType: toneType ?? this.toneType,
    toneFrequency: toneFrequency ?? this.toneFrequency,
    toneAngle: toneAngle ?? this.toneAngle,
  );
}

class TextObjectData {
  final String id;
  final String text;
  final double x;
  final double y;
  final double width;
  final String fontFamily;
  final double fontSize;
  final FontWeight fontWeight;
  final Color color;
  final TextAlign textAlign;
  final bool isVertical;
  final Color outlineColor;
  final double outlineWidth;
  final bool hasDecoration;
  final Color decorationColor;
  final double rotation;

  const TextObjectData({
    required this.id,
    this.text = 'Text',
    this.x = 0,
    this.y = 0,
    this.width = 300.0,
    this.fontFamily = 'Roboto',
    this.fontSize = 24.0,
    this.fontWeight = FontWeight.normal,
    this.color = Colors.black,
    this.textAlign = TextAlign.left,
    this.isVertical = false,
    this.outlineColor = Colors.transparent,
    this.outlineWidth = 0.0,
    this.hasDecoration = false,
    this.decorationColor = Colors.black,
    this.rotation = 0.0,
  });

  Rect get bounds => Rect.fromLTWH(
    x,
    y,
    width,
    math.max(fontSize * 1.2, fontSize * text.split('\n').length * 1.2),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'x': x,
    'y': y,
    'width': width,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'fontWeight': fontWeight.value.toString(),
    'color': color.toARGB32(),
    'textAlign': textAlign.name,
    'isVertical': isVertical,
    'outlineColor': outlineColor.toARGB32(),
    'outlineWidth': outlineWidth,
    'hasDecoration': hasDecoration,
    'decorationColor': decorationColor.toARGB32(),
    'rotation': rotation,
  };

  factory TextObjectData.fromJson(Map<String, dynamic> json) => TextObjectData(
    id:
        json['id'] as String? ??
        'text_${DateTime.now().microsecondsSinceEpoch}',
    text: json['text'] as String? ?? 'Text',
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    width: (json['width'] as num?)?.toDouble() ?? 300,
    fontFamily: json['fontFamily'] as String? ?? 'Roboto',
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 24,
    fontWeight: FontWeight.values.firstWhere(
      (e) =>
          e.value.toString() == json['fontWeight'] ||
          e.toString() == json['fontWeight'],
      orElse: () => FontWeight.normal,
    ),
    color: Color((json['color'] as num?)?.toInt() ?? 0xFF000000),
    textAlign: TextAlign.values.firstWhere(
      (a) => a.name == json['textAlign'],
      orElse: () => TextAlign.left,
    ),
    isVertical: json['isVertical'] as bool? ?? false,
    outlineColor: Color((json['outlineColor'] as num?)?.toInt() ?? 0x00000000),
    outlineWidth: (json['outlineWidth'] as num?)?.toDouble() ?? 0,
    hasDecoration: json['hasDecoration'] as bool? ?? false,
    decorationColor: Color(
      (json['decorationColor'] as num?)?.toInt() ?? 0xFF000000,
    ),
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
  );

  TextObjectData copyWith({
    String? id,
    String? text,
    double? x,
    double? y,
    double? width,
    String? fontFamily,
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    TextAlign? textAlign,
    bool? isVertical,
    Color? outlineColor,
    double? outlineWidth,
    bool? hasDecoration,
    Color? decorationColor,
    double? rotation,
  }) => TextObjectData(
    id: id ?? this.id,
    text: text ?? this.text,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    fontWeight: fontWeight ?? this.fontWeight,
    color: color ?? this.color,
    textAlign: textAlign ?? this.textAlign,
    isVertical: isVertical ?? this.isVertical,
    outlineColor: outlineColor ?? this.outlineColor,
    outlineWidth: outlineWidth ?? this.outlineWidth,
    hasDecoration: hasDecoration ?? this.hasDecoration,
    decorationColor: decorationColor ?? this.decorationColor,
    rotation: rotation ?? this.rotation,
  );
}

class DrawingStroke {
  final String id;
  final StudioBrushCategory brush;
  final Color color;
  final double size;
  final double opacity;
  final List<DrawingStrokePoint> points;
  final BlendMode blendMode;
  final bool isEraser;
  final ScreenToneType toneType;
  final double toneFrequency;
  final double toneAngle;

  const DrawingStroke({
    required this.id,
    required this.brush,
    required this.color,
    required this.size,
    required this.opacity,
    required this.points,
    this.blendMode = BlendMode.srcOver,
    this.isEraser = false,
    this.toneType = ScreenToneType.none,
    this.toneFrequency = 24.0,
    this.toneAngle = 45.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'brush': brush.name,
    'color': color.toARGB32(),
    'size': size,
    'opacity': opacity,
    'points': points.map((p) => p.toJson()).toList(),
    'blendMode': blendMode.name,
    'isEraser': isEraser,
    'toneType': toneType.name,
    'toneFrequency': toneFrequency,
    'toneAngle': toneAngle,
  };

  factory DrawingStroke.fromJson(Map<String, dynamic> json) => DrawingStroke(
    id:
        json['id'] as String? ??
        'stroke_${DateTime.now().microsecondsSinceEpoch}',
    brush: StudioBrushCategory.values.firstWhere(
      (b) => b.name == json['brush'],
      orElse: () => StudioBrushCategory.inkPen,
    ),
    color: Color((json['color'] as num?)?.toInt() ?? 0xFF000000),
    size: (json['size'] as num?)?.toDouble() ?? 4.0,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    points:
        (json['points'] as List<dynamic>?)
            ?.map((p) => DrawingStrokePoint.fromJson(p as Map<String, dynamic>))
            .toList() ??
        const [],
    blendMode: BlendMode.values.firstWhere(
      (m) => m.name == json['blendMode'],
      orElse: () => BlendMode.srcOver,
    ),
    isEraser: json['isEraser'] as bool? ?? false,
    toneType: ScreenToneType.values.firstWhere(
      (t) => t.name == json['toneType'],
      orElse: () => ScreenToneType.none,
    ),
    toneFrequency: (json['toneFrequency'] as num?)?.toDouble() ?? 24.0,
    toneAngle: (json['toneAngle'] as num?)?.toDouble() ?? 45.0,
  );

  DrawingStroke copyWith({
    String? id,
    StudioBrushCategory? brush,
    Color? color,
    double? size,
    double? opacity,
    List<DrawingStrokePoint>? points,
    BlendMode? blendMode,
    bool? isEraser,
    ScreenToneType? toneType,
    double? toneFrequency,
    double? toneAngle,
  }) => DrawingStroke(
    id: id ?? this.id,
    brush: brush ?? this.brush,
    color: color ?? this.color,
    size: size ?? this.size,
    opacity: opacity ?? this.opacity,
    points: points ?? this.points,
    blendMode: blendMode ?? this.blendMode,
    isEraser: isEraser ?? this.isEraser,
    toneType: toneType ?? this.toneType,
    toneFrequency: toneFrequency ?? this.toneFrequency,
    toneAngle: toneAngle ?? this.toneAngle,
  );

  static Rect boundsOf(List<Offset> pts) {
    double l = double.infinity,
        t = double.infinity,
        r = -double.infinity,
        b = -double.infinity;
    for (final p in pts) {
      if (p.dx < l) l = p.dx;
      if (p.dy < t) t = p.dy;
      if (p.dx > r) r = p.dx;
      if (p.dy > b) b = p.dy;
    }
    return Rect.fromLTRB(l, t, r, b);
  }
}

class DrawingLayer {
  final String id;
  final String name;
  final LayerType type;
  final bool visible;
  final bool locked;
  final bool alphaLocked;
  final bool clipToBelow;
  final double opacity;
  final BlendMode blendMode;
  final String? parentFolderId;
  final List<DrawingStroke> strokes;
  final List<VectorShapeObject> shapes;
  final List<TextObjectData> texts;
  final AdjustmentFilterType? adjustmentFilter;
  final Map<String, double> adjustmentParams;

  const DrawingLayer({
    required this.id,
    required this.name,
    this.type = LayerType.raster,
    this.visible = true,
    this.locked = false,
    this.alphaLocked = false,
    this.clipToBelow = false,
    this.opacity = 1.0,
    this.blendMode = BlendMode.srcOver,
    this.parentFolderId,
    this.strokes = const [],
    this.shapes = const [],
    this.texts = const [],
    this.adjustmentFilter,
    this.adjustmentParams = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'visible': visible,
    'locked': locked,
    'alphaLocked': alphaLocked,
    'clipToBelow': clipToBelow,
    'opacity': opacity,
    'blendMode': blendMode.name,
    'parentFolderId': parentFolderId,
    'strokes': strokes.map((s) => s.toJson()).toList(),
    'shapes': shapes.map((s) => s.toJson()).toList(),
    'texts': texts.map((s) => s.toJson()).toList(),
    'adjustmentFilter': adjustmentFilter?.name,
    'adjustmentParams': adjustmentParams,
  };

  factory DrawingLayer.fromJson(Map<String, dynamic> json) => DrawingLayer(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Layer',
    type: LayerType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => LayerType.raster,
    ),
    visible: json['visible'] as bool? ?? true,
    locked: json['locked'] as bool? ?? false,
    alphaLocked: json['alphaLocked'] as bool? ?? false,
    clipToBelow: json['clipToBelow'] as bool? ?? false,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    blendMode: BlendMode.values.firstWhere(
      (m) => m.name == json['blendMode'],
      orElse: () => BlendMode.srcOver,
    ),
    parentFolderId: json['parentFolderId'] as String?,
    strokes:
        (json['strokes'] as List<dynamic>?)
            ?.map((s) => DrawingStroke.fromJson(s as Map<String, dynamic>))
            .toList() ??
        const [],
    shapes:
        (json['shapes'] as List<dynamic>?)
            ?.map((s) => VectorShapeObject.fromJson(s as Map<String, dynamic>))
            .toList() ??
        const [],
    texts:
        (json['texts'] as List<dynamic>?)
            ?.map((s) => TextObjectData.fromJson(s as Map<String, dynamic>))
            .toList() ??
        const [],
    adjustmentFilter: json['adjustmentFilter'] != null
        ? AdjustmentFilterType.values.firstWhere(
            (f) => f.name == json['adjustmentFilter'],
            orElse: () => AdjustmentFilterType.brightnessContrast,
          )
        : null,
    adjustmentParams:
        (json['adjustmentParams'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ) ??
        const {},
  );

  DrawingLayer clone() => DrawingLayer(
    id: id,
    name: name,
    type: type,
    visible: visible,
    locked: locked,
    alphaLocked: alphaLocked,
    clipToBelow: clipToBelow,
    opacity: opacity,
    blendMode: blendMode,
    parentFolderId: parentFolderId,
    strokes: strokes
        .map((stroke) => stroke.copyWith(points: List.of(stroke.points)))
        .toList(),
    shapes: shapes
        .map((shape) => shape.copyWith(points: List.of(shape.points)))
        .toList(),
    texts: texts.toList(),
    adjustmentFilter: adjustmentFilter,
    adjustmentParams: Map.of(adjustmentParams),
  );

  DrawingLayer copyWith({
    String? id,
    String? name,
    LayerType? type,
    bool? visible,
    bool? locked,
    bool? alphaLocked,
    bool? clipToBelow,
    double? opacity,
    BlendMode? blendMode,
    String? parentFolderId,
    List<DrawingStroke>? strokes,
    List<VectorShapeObject>? shapes,
    List<TextObjectData>? texts,
    AdjustmentFilterType? adjustmentFilter,
    Map<String, double>? adjustmentParams,
  }) => DrawingLayer(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    visible: visible ?? this.visible,
    locked: locked ?? this.locked,
    alphaLocked: alphaLocked ?? this.alphaLocked,
    clipToBelow: clipToBelow ?? this.clipToBelow,
    opacity: opacity ?? this.opacity,
    blendMode: blendMode ?? this.blendMode,
    parentFolderId: parentFolderId ?? this.parentFolderId,
    strokes: strokes ?? this.strokes,
    shapes: shapes ?? this.shapes,
    texts: texts ?? this.texts,
    adjustmentFilter: adjustmentFilter ?? this.adjustmentFilter,
    adjustmentParams: adjustmentParams ?? this.adjustmentParams,
  );
}

class ReferenceImageConfig {
  static const Object _sentinel = Object();

  /// Stable project-scoped Storage metadata for the reference image.
  final String? storagePath;
  final String? localPath;
  final String? url;
  final double x;
  final double y;
  final double width;
  final double height;
  final double zoom;
  final bool visible;

  const ReferenceImageConfig({
    this.storagePath,
    this.localPath,
    this.url,
    this.x = 20,
    this.y = 80,
    this.width = 220,
    this.height = 180,
    this.zoom = 1.0,
    this.visible = false,
  });

  Map<String, dynamic> toJson() => {
    'storagePath': ?durableAssetReference(storagePath),
    // Local paths and delivery URLs are runtime-only.
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'zoom': zoom,
    'visible': visible,
  };

  factory ReferenceImageConfig.fromJson(Map<String, dynamic> json) =>
      ReferenceImageConfig(
        storagePath: durableAssetReference(json['storagePath'] as String?),
        // Runtime paths and delivery URLs must be rehydrated through the
        // transient source resolver, never restored from durable JSON.
        localPath: null,
        url: null,
        x: (json['x'] as num?)?.toDouble() ?? 20.0,
        y: (json['y'] as num?)?.toDouble() ?? 80.0,
        width: (json['width'] as num?)?.toDouble() ?? 220.0,
        height: (json['height'] as num?)?.toDouble() ?? 180.0,
        zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
        visible: json['visible'] as bool? ?? false,
      );

  ReferenceImageConfig copyWith({
    Object? storagePath = _sentinel,
    Object? localPath = _sentinel,
    Object? url = _sentinel,
    double? x,
    double? y,
    double? width,
    double? height,
    double? zoom,
    bool? visible,
  }) => ReferenceImageConfig(
    storagePath: storagePath == _sentinel
        ? this.storagePath
        : durableAssetReference(storagePath as String?),
    localPath: localPath == _sentinel ? this.localPath : localPath as String?,
    url: url == _sentinel ? this.url : url as String?,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    zoom: zoom ?? this.zoom,
    visible: visible ?? this.visible,
  );
}

class DrawingPaperPage {
  final String id;
  final Offset position;
  final DrawingPaperPayload payload;

  const DrawingPaperPage({
    required this.id,
    required this.position,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': position.dx,
    'y': position.dy,
    'payload': payload.toJson(),
  };

  factory DrawingPaperPage.fromJson(Map<String, dynamic> json) =>
      DrawingPaperPage(
        id:
            json['id'] as String? ??
            'page_${DateTime.now().microsecondsSinceEpoch}',
        position: Offset(
          (json['x'] as num?)?.toDouble() ?? 0.0,
          (json['y'] as num?)?.toDouble() ?? 0.0,
        ),
        payload: DrawingPaperPayload.fromJson(
          json['payload'] as Map<String, dynamic>? ?? const {},
        ),
      );

  DrawingPaperPage copyWith({
    String? id,
    Offset? position,
    DrawingPaperPayload? payload,
  }) => DrawingPaperPage(
    id: id ?? this.id,
    position: position ?? this.position,
    payload: payload ?? this.payload,
  );

  DrawingPaperPage clone() => copyWith(payload: payload.clone());
}

class DrawingPaperPayload extends NodePayload {
  static const Object _unset = Object();

  final String presetName;
  final double dpi;
  final double pixelWidth;
  final double pixelHeight;
  final Color paperColor;
  final int rasterSchemaVersion;
  final String rasterDocumentId;
  final int rasterRevision;

  /// Stable project-scoped Storage metadata for the generated preview.
  final String? compositePreviewRef;
  final List<RasterEditOperation> rasterOperations;
  final PaperTextureType paperTexture;
  final List<DrawingLayer> layers;
  final int activeLayerIndex;
  final SelectionMask? activeSelection;
  final List<RulerGuide> rulers;
  final MangaStructure? mangaStructure;
  final ReferenceImageConfig referenceConfig;
  final bool showPixelGrid;
  final bool showGrid;
  final bool showMangaBleed;
  final double stabilizerStrength; // 0.0 to 1.0
  final bool enableTaper;
  final List<String> colorHistory; // Hex strings or RGBA
  final List<DrawingPaperPage> studioPages;

  DrawingPaperPayload({
    this.presetName = 'A4 Portrait',
    this.dpi = 300.0,
    this.pixelWidth = 2480.0,
    this.pixelHeight = 3508.0,
    this.paperColor = Colors.white,
    this.rasterSchemaVersion = 1,
    this.rasterDocumentId = '',
    this.rasterRevision = 0,
    this.compositePreviewRef,
    this.rasterOperations = const [],
    this.paperTexture = PaperTextureType.none,
    List<DrawingLayer>? layers,
    this.activeLayerIndex = 0,
    this.activeSelection,
    this.rulers = const [],
    this.mangaStructure,
    this.referenceConfig = const ReferenceImageConfig(),
    this.showPixelGrid = false,
    this.showGrid = false,
    this.showMangaBleed = false,
    this.stabilizerStrength = 0.4,
    this.enableTaper = true,
    this.colorHistory = const [
      '#000000',
      '#FFFFFF',
      '#F97316',
      '#3B82F6',
      '#10B981',
      '#EF4444',
      '#8B5CF6',
      '#EAB308',
    ],
    this.studioPages = const [],
  }) : layers =
           layers ??
           [
             const DrawingLayer(
               id: 'layer_1',
               name: 'Background Layer',
               type: LayerType.raster,
             ),
           ];

  Size get pixelSize => Size(pixelWidth, pixelHeight);

  factory DrawingPaperPayload.fromJson(Map<String, dynamic> json) {
    return DrawingPaperPayload(
      presetName: json['presetName'] as String? ?? 'A4 Portrait',
      dpi: (json['dpi'] as num?)?.toDouble() ?? 300.0,
      pixelWidth: (json['pixelWidth'] as num?)?.toDouble() ?? 2480.0,
      pixelHeight: (json['pixelHeight'] as num?)?.toDouble() ?? 3508.0,
      paperColor: Color((json['paperColor'] as num?)?.toInt() ?? 0xFFFFFFFF),
      rasterSchemaVersion: (json['rasterSchemaVersion'] as num?)?.toInt() ?? 1,
      rasterDocumentId: json['rasterDocumentId'] as String? ?? '',
      rasterRevision: (json['rasterRevision'] as num?)?.toInt() ?? 0,
      // raster:// references are local cache keys and are intentionally not
      // restored from portable/cloud JSON.
      compositePreviewRef:
          _isDurablePreviewReference(json['compositePreviewRef'] as String?)
          ? json['compositePreviewRef'] as String
          : null,
      studioPages:
          (json['studioPages'] as List<dynamic>?)
              ?.map(
                (page) =>
                    DrawingPaperPage.fromJson(page as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      rasterOperations:
          (json['rasterOperations'] as List<dynamic>?)
              ?.map(
                (operation) => RasterEditOperation.fromJson(
                  operation as Map<String, dynamic>,
                ),
              )
              .toList() ??
          const [],
      paperTexture: PaperTextureType.values.firstWhere(
        (t) => t.name == json['paperTexture'],
        orElse: () => PaperTextureType.none,
      ),
      layers: (json['layers'] as List<dynamic>?)
          ?.map((l) => DrawingLayer.fromJson(l as Map<String, dynamic>))
          .toList(),
      activeLayerIndex: (json['activeLayerIndex'] as num?)?.toInt() ?? 0,
      activeSelection: json['activeSelection'] != null
          ? SelectionMask.fromJson(
              json['activeSelection'] as Map<String, dynamic>,
            )
          : null,
      rulers:
          (json['rulers'] as List<dynamic>?)
              ?.map((r) => RulerGuide.fromJson(r as Map<String, dynamic>))
              .toList() ??
          const [],
      mangaStructure: json['mangaStructure'] != null
          ? MangaStructure.fromJson(
              json['mangaStructure'] as Map<String, dynamic>,
            )
          : null,
      referenceConfig: json['referenceConfig'] != null
          ? ReferenceImageConfig.fromJson(
              json['referenceConfig'] as Map<String, dynamic>,
            )
          : const ReferenceImageConfig(),
      showPixelGrid: json['showPixelGrid'] as bool? ?? false,
      showGrid: json['showGrid'] as bool? ?? false,
      showMangaBleed: json['showMangaBleed'] as bool? ?? false,
      stabilizerStrength:
          (json['stabilizerStrength'] as num?)?.toDouble() ?? 0.4,
      enableTaper: json['enableTaper'] as bool? ?? true,
      colorHistory:
          (json['colorHistory'] as List<dynamic>?)
              ?.map((c) => c.toString())
              .toList() ??
          const [
            '#000000',
            '#FFFFFF',
            '#F97316',
            '#3B82F6',
            '#10B981',
            '#EF4444',
            '#8B5CF6',
            '#EAB308',
          ],
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'presetName': presetName,
    'dpi': dpi,
    'pixelWidth': pixelWidth,
    'pixelHeight': pixelHeight,
    'paperColor': paperColor.toARGB32(),
    'rasterSchemaVersion': rasterSchemaVersion,
    'rasterDocumentId': rasterDocumentId,
    'rasterRevision': rasterRevision,
    if (_isDurablePreviewReference(compositePreviewRef))
      'compositePreviewRef': compositePreviewRef,
    'studioPages': studioPages.map((page) => page.toJson()).toList(),
    'rasterOperations': rasterOperations
        .map((operation) => operation.toJson())
        .toList(),
    'paperTexture': paperTexture.name,
    'layers': layers.map((l) => l.toJson()).toList(),
    'activeLayerIndex': activeLayerIndex,
    'activeSelection': activeSelection?.toJson(),
    'rulers': rulers.map((r) => r.toJson()).toList(),
    'mangaStructure': mangaStructure?.toJson(),
    'referenceConfig': referenceConfig.toJson(),
    'showPixelGrid': showPixelGrid,
    'showGrid': showGrid,
    'showMangaBleed': showMangaBleed,
    'stabilizerStrength': stabilizerStrength,
    'enableTaper': enableTaper,
    'colorHistory': colorHistory,
  };

  static bool _isDurablePreviewReference(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty || value != normalized) {
      return false;
    }
    if (normalized.toLowerCase().startsWith('raster://')) return false;
    return durableAssetReference(normalized) != null;
  }

  @override
  Map<String, dynamic> toPersistenceJson() => {
    'presetName': presetName,
    'dpi': dpi,
    'pixelWidth': pixelWidth,
    'pixelHeight': pixelHeight,
    'paperColor': paperColor.toARGB32(),
    'rasterSchemaVersion': rasterSchemaVersion,
    'rasterDocumentId': rasterDocumentId,
    'rasterRevision': rasterRevision,
    if (_isDurablePreviewReference(compositePreviewRef))
      'compositePreviewRef': compositePreviewRef,
    'studioPages': studioPages
        .map(
          (page) => {
            'id': page.id,
            'x': page.position.dx,
            'y': page.position.dy,
            'payload': page.payload.toPersistenceJson(),
          },
        )
        .toList(growable: false),
    'rasterOperations': rasterOperations
        .map((operation) => operation.toJson())
        .toList(growable: false),
    'paperTexture': paperTexture.name,
    'layers': layers.map((layer) => layer.toJson()).toList(growable: false),
    'activeLayerIndex': activeLayerIndex,
    'activeSelection': activeSelection?.toJson(),
    'rulers': rulers.map((ruler) => ruler.toJson()).toList(growable: false),
    'mangaStructure': mangaStructure?.toJson(),
    'referenceConfig': referenceConfig.toJson(),
    'showPixelGrid': showPixelGrid,
    'showGrid': showGrid,
    'showMangaBleed': showMangaBleed,
    'stabilizerStrength': stabilizerStrength,
    'enableTaper': enableTaper,
    'colorHistory': colorHistory,
  };

  @override
  DrawingPaperPayload clone() => DrawingPaperPayload(
    presetName: presetName,
    dpi: dpi,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    paperColor: paperColor,
    rasterSchemaVersion: rasterSchemaVersion,
    rasterDocumentId: rasterDocumentId,
    rasterRevision: rasterRevision,
    compositePreviewRef: compositePreviewRef,
    studioPages: studioPages.map((page) => page.clone()).toList(),
    rasterOperations: List.of(rasterOperations),
    paperTexture: paperTexture,
    layers: layers.map((l) => l.clone()).toList(),
    activeLayerIndex: activeLayerIndex,
    activeSelection: activeSelection?.clone(),
    rulers: List.of(rulers),
    mangaStructure: mangaStructure?.clone(),
    referenceConfig: referenceConfig.copyWith(),
    showPixelGrid: showPixelGrid,
    showGrid: showGrid,
    showMangaBleed: showMangaBleed,
    stabilizerStrength: stabilizerStrength,
    enableTaper: enableTaper,
    colorHistory: List.of(colorHistory),
  );

  DrawingPaperPayload copyWith({
    String? presetName,
    double? dpi,
    double? pixelWidth,
    double? pixelHeight,
    Color? paperColor,
    int? rasterSchemaVersion,
    String? rasterDocumentId,
    int? rasterRevision,
    Object? compositePreviewRef = _unset,
    List<RasterEditOperation>? rasterOperations,
    PaperTextureType? paperTexture,
    List<DrawingLayer>? layers,
    int? activeLayerIndex,
    Object? activeSelection = _unset,
    List<RulerGuide>? rulers,
    Object? mangaStructure = _unset,
    ReferenceImageConfig? referenceConfig,
    bool? showPixelGrid,
    bool? showGrid,
    bool? showMangaBleed,
    double? stabilizerStrength,
    bool? enableTaper,
    List<String>? colorHistory,
    List<DrawingPaperPage>? studioPages,
  }) {
    return DrawingPaperPayload(
      presetName: presetName ?? this.presetName,
      dpi: dpi ?? this.dpi,
      pixelWidth: pixelWidth ?? this.pixelWidth,
      pixelHeight: pixelHeight ?? this.pixelHeight,
      paperColor: paperColor ?? this.paperColor,
      rasterSchemaVersion: rasterSchemaVersion ?? this.rasterSchemaVersion,
      rasterDocumentId: rasterDocumentId ?? this.rasterDocumentId,
      rasterRevision: rasterRevision ?? this.rasterRevision,
      compositePreviewRef: compositePreviewRef == _unset
          ? this.compositePreviewRef
          : compositePreviewRef as String?,
      studioPages: studioPages ?? this.studioPages,
      rasterOperations: rasterOperations ?? this.rasterOperations,
      paperTexture: paperTexture ?? this.paperTexture,
      layers: layers ?? this.layers,
      activeLayerIndex: activeLayerIndex ?? this.activeLayerIndex,
      activeSelection: activeSelection == _unset
          ? this.activeSelection
          : activeSelection as SelectionMask?,
      rulers: rulers ?? this.rulers,
      mangaStructure: mangaStructure == _unset
          ? this.mangaStructure
          : mangaStructure as MangaStructure?,
      referenceConfig: referenceConfig ?? this.referenceConfig,
      showPixelGrid: showPixelGrid ?? this.showPixelGrid,
      showGrid: showGrid ?? this.showGrid,
      showMangaBleed: showMangaBleed ?? this.showMangaBleed,
      stabilizerStrength: stabilizerStrength ?? this.stabilizerStrength,
      enableTaper: enableTaper ?? this.enableTaper,
      colorHistory: colorHistory ?? this.colorHistory,
    );
  }
}
