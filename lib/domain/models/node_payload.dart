import 'package:flutter/material.dart';
import 'component_payload.dart';
import 'connector_edge.dart';
import 'drawing_paper_payload.dart';
import 'drawing_payload.dart';
import 'image_editing.dart';
import 'model3d_payload.dart';
import 'media_timeline.dart';
import 'mermaid_payload.dart';
import 'node.dart';
import 'pdf_annotation.dart';
import 'rich_text.dart';
import 'vector_path_payload.dart';
import 'durable_asset_reference.dart';

export 'mermaid_payload.dart';
export 'image_editing.dart';

enum NodeType {
  text,
  stickyNote,
  rectangle,
  ellipse,
  line,
  arrow,
  image,
  frame,
  diamond,
  cylinder,
  parallelogram,
  drawing,
  vectorPath,
  component,
  group,
  // Creative Paper Studio
  drawingPaper,
  // Infinite Board - Content
  fileCard,
  model3d,
  linkCard,
  videoCard,
  audioCard,
  mapCard,
  colorSwatch,
  document,
  embed,
  mermaid,
  // Infinite Board - Creative
  sketchCard,
  annotatedImage,
  // Infinite Board - Organization
  columnContainer,
  nestedBoard,
  tableGrid,
  todoList,
  chart,
}

abstract class NodePayload {
  final String? hotspotTargetFrameId;

  NodePayload({this.hotspotTargetFrameId});

  Map<String, dynamic> toJson();

  /// Serializes only values safe to retain in durable documents, cloud
  /// snapshots, collaboration state, history, and exports. Runtime payloads
  /// may override this when [toJson] includes transient delivery state.
  Map<String, dynamic> toPersistenceJson() => toJson();

  NodePayload clone();

  static NodePayload fromJson(NodeType type, Map<String, dynamic> json) {
    switch (type) {
      case NodeType.text:
        return TextPayload.fromJson(json);
      case NodeType.stickyNote:
        return StickyNotePayload.fromJson(json);
      case NodeType.rectangle:
      case NodeType.ellipse:
      case NodeType.line:
      case NodeType.arrow:
      case NodeType.diamond:
      case NodeType.cylinder:
      case NodeType.parallelogram:
        return ShapePayload.fromJson(json);
      case NodeType.image:
        return ImagePayload.fromJson(json);
      case NodeType.frame:
        return FramePayload.fromJson(json);
      case NodeType.drawing:
        return DrawingPayload.fromJson(json);
      case NodeType.vectorPath:
        return VectorPathPayload.fromJson(json);
      case NodeType.component:
        return ComponentPayload.fromJson(json);
      case NodeType.drawingPaper:
        return DrawingPaperPayload.fromJson(json);
      case NodeType.group:
        return GroupPayload.fromJson(json);
      case NodeType.fileCard:
        return FilePayload.fromJson(json);
      case NodeType.model3d:
        return Model3DPayload.fromJson(json);
      case NodeType.linkCard:
        return LinkPayload.fromJson(json);
      case NodeType.videoCard:
        return VideoPayload.fromJson(json);
      case NodeType.audioCard:
        return AudioPayload.fromJson(json);
      case NodeType.mapCard:
        return MapPayload.fromJson(json);
      case NodeType.colorSwatch:
        return ColorSwatchPayload.fromJson(json);
      case NodeType.document:
        return DocumentPayload.fromJson(json);
      case NodeType.embed:
        return EmbedPayload.fromJson(json);
      case NodeType.mermaid:
        return MermaidPayload.fromJson(json);
      case NodeType.sketchCard:
        return SketchCardPayload.fromJson(json);
      case NodeType.annotatedImage:
        return AnnotatedImagePayload.fromJson(json);
      case NodeType.columnContainer:
        return ColumnPayload.fromJson(json);
      case NodeType.nestedBoard:
        return NestedBoardPayload.fromJson(json);
      case NodeType.tableGrid:
        return TablePayload.fromJson(json);
      case NodeType.todoList:
        return TodoListPayload.fromJson(json);
      case NodeType.chart:
        return ChartPayload.fromJson(json);
    }
  }
}

enum TextTransformCase { none, uppercase, lowercase, capitalize }

enum TextVerticalAlign { top, middle, bottom }

enum TextSizeMode { autoWidth, autoHeight, fixed }

enum TextRenderMode { plain, rich, markdown }

enum TextWrapMode { wrap, clip, ellipsis }

enum TextPathAlignment { start, center, end }

class TextPayload extends NodePayload {
  final String text;
  final double fontSize;
  final FontWeight fontWeight;
  final TextAlign textAlign;
  final Color color;
  final List<RichTextBlock>? blocks;

  // Advanced Typography & Effects
  final String
  fontFamily; // e.g. 'Inter', 'Roboto', 'Poppins', 'Fira Code', 'Caveat', 'Playfair Display'
  final double lineHeight; // multiplier, default 1.2
  final double letterSpacing; // px, default 0.0
  final FontStyle fontStyle; // normal / italic
  final bool underline;
  final bool strikethrough;
  final TextTransformCase textTransform;
  final TextVerticalAlign verticalAlign;
  final TextSizeMode sizeMode;
  final TextRenderMode renderMode;
  final TextWrapMode wrapMode;
  final Map<String, double> fontAxes;
  final String? localeTag;
  final bool spellCheckEnabled;
  final String? textPathNodeId;
  final double textPathOffset;
  final bool textPathReversed;
  final TextPathAlignment textPathAlignment;

  // Outline / Stroke
  final Color? strokeColor;
  final double strokeWidth;

  // Shadow / Glow
  final Color? shadowColor;
  final double shadowBlurRadius;
  final Offset shadowOffset;

  // Background Box / Badge
  final Color? backgroundColor;
  final double backgroundRadius;
  final double backgroundPadding;

  TextPayload({
    this.text = 'Hello Canvas',
    this.fontSize = 18.0,
    this.fontWeight = FontWeight.normal,
    this.textAlign = TextAlign.left,
    this.color = Colors.white,
    this.blocks,
    this.fontFamily = 'Inter',
    this.lineHeight = 1.2,
    this.letterSpacing = 0.0,
    this.fontStyle = FontStyle.normal,
    this.underline = false,
    this.strikethrough = false,
    this.textTransform = TextTransformCase.none,
    this.verticalAlign = TextVerticalAlign.top,
    this.sizeMode = TextSizeMode.fixed,
    this.renderMode = TextRenderMode.plain,
    this.wrapMode = TextWrapMode.wrap,
    this.fontAxes = const {},
    this.localeTag,
    this.spellCheckEnabled = true,
    this.textPathNodeId,
    this.textPathOffset = 0.0,
    this.textPathReversed = false,
    this.textPathAlignment = TextPathAlignment.start,
    this.strokeColor,
    this.strokeWidth = 0.0,
    this.shadowColor,
    this.shadowBlurRadius = 0.0,
    this.shadowOffset = const Offset(0, 2),
    this.backgroundColor,
    this.backgroundRadius = 4.0,
    this.backgroundPadding = 8.0,
  });

  bool get isRichText =>
      renderMode == TextRenderMode.rich ||
      (blocks != null && blocks!.isNotEmpty);
  bool get isMarkdown => renderMode == TextRenderMode.markdown;

  factory TextPayload.fromJson(Map<String, dynamic> json) {
    return TextPayload(
      text: json['text'] as String? ?? '',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
      fontWeight: FontWeight.values.firstWhere(
        (e) =>
            e.value.toString() == json['fontWeight'] ||
            e.toString() == json['fontWeight'],
        orElse: () => FontWeight.normal,
      ),
      textAlign: TextAlign.values.firstWhere(
        (e) => e.name == json['textAlign'],
        orElse: () => TextAlign.left,
      ),
      color: Color((json['color'] as num?)?.toInt() ?? 0xFFFFFFFF),
      blocks: (json['blocks'] as List<dynamic>?)
          ?.map((b) => RichTextBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
      fontFamily: json['fontFamily'] as String? ?? 'Inter',
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.2,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0.0,
      fontStyle: json['fontStyle'] == 'italic'
          ? FontStyle.italic
          : FontStyle.normal,
      underline: json['underline'] as bool? ?? false,
      strikethrough: json['strikethrough'] as bool? ?? false,
      textTransform: TextTransformCase.values.firstWhere(
        (e) => e.name == json['textTransform'],
        orElse: () => TextTransformCase.none,
      ),
      verticalAlign: TextVerticalAlign.values.firstWhere(
        (e) => e.name == json['verticalAlign'],
        orElse: () => TextVerticalAlign.top,
      ),
      sizeMode: TextSizeMode.values.firstWhere(
        (e) => e.name == json['sizeMode'],
        orElse: () => TextSizeMode.fixed,
      ),
      renderMode: TextRenderMode.values.firstWhere(
        (e) => e.name == json['renderMode'],
        orElse: () => TextRenderMode.plain,
      ),
      wrapMode: TextWrapMode.values.firstWhere(
        (e) => e.name == json['wrapMode'],
        orElse: () => TextWrapMode.wrap,
      ),
      fontAxes: _readFontAxes(json['fontAxes']),
      localeTag: json['localeTag'] as String?,
      spellCheckEnabled: json['spellCheckEnabled'] as bool? ?? true,
      textPathNodeId: json['textPathNodeId'] as String?,
      textPathOffset: (json['textPathOffset'] as num?)?.toDouble() ?? 0.0,
      textPathReversed: json['textPathReversed'] as bool? ?? false,
      textPathAlignment: TextPathAlignment.values.firstWhere(
        (e) => e.name == json['textPathAlignment'],
        orElse: () => TextPathAlignment.start,
      ),
      strokeColor: json['strokeColor'] != null
          ? Color((json['strokeColor'] as num).toInt())
          : null,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 0.0,
      shadowColor: json['shadowColor'] != null
          ? Color((json['shadowColor'] as num).toInt())
          : null,
      shadowBlurRadius: (json['shadowBlurRadius'] as num?)?.toDouble() ?? 0.0,
      shadowOffset:
          json['shadowOffsetX'] != null && json['shadowOffsetY'] != null
          ? Offset(
              (json['shadowOffsetX'] as num).toDouble(),
              (json['shadowOffsetY'] as num).toDouble(),
            )
          : const Offset(0, 2),
      backgroundColor: json['backgroundColor'] != null
          ? Color((json['backgroundColor'] as num).toInt())
          : null,
      backgroundRadius: (json['backgroundRadius'] as num?)?.toDouble() ?? 4.0,
      backgroundPadding: (json['backgroundPadding'] as num?)?.toDouble() ?? 8.0,
    );
  }

  static Map<String, double> _readFontAxes(Object? value) {
    if (value is! Map) return const {};
    final axes = <String, double>{};
    for (final entry in value.entries) {
      final axis = entry.key.toString().trim();
      final number = entry.value;
      if (axis.isEmpty ||
          axis.length > 4 ||
          number is! num ||
          !number.isFinite) {
        continue;
      }
      axes[axis] = number.toDouble().clamp(-1000.0, 1000.0).toDouble();
    }
    return axes;
  }

  @override
  Map<String, dynamic> toJson() => {
    'text': text,
    'fontSize': fontSize,
    'fontWeight': fontWeight.value.toString(),
    'textAlign': textAlign.name,
    'color': color.toARGB32(),
    'blocks': blocks?.map((b) => b.toJson()).toList(),
    'fontFamily': fontFamily,
    'lineHeight': lineHeight,
    'letterSpacing': letterSpacing,
    'fontStyle': fontStyle.name,
    'underline': underline,
    'strikethrough': strikethrough,
    'textTransform': textTransform.name,
    'verticalAlign': verticalAlign.name,
    'sizeMode': sizeMode.name,
    'renderMode': renderMode.name,
    'wrapMode': wrapMode.name,
    'fontAxes': fontAxes,
    'localeTag': localeTag,
    'spellCheckEnabled': spellCheckEnabled,
    'textPathNodeId': textPathNodeId,
    'textPathOffset': textPathOffset,
    'textPathReversed': textPathReversed,
    'textPathAlignment': textPathAlignment.name,
    'strokeColor': strokeColor?.toARGB32(),
    'strokeWidth': strokeWidth,
    'shadowColor': shadowColor?.toARGB32(),
    'shadowBlurRadius': shadowBlurRadius,
    'shadowOffsetX': shadowOffset.dx,
    'shadowOffsetY': shadowOffset.dy,
    'backgroundColor': backgroundColor?.toARGB32(),
    'backgroundRadius': backgroundRadius,
    'backgroundPadding': backgroundPadding,
  };

  @override
  TextPayload clone() => TextPayload(
    text: text,
    fontSize: fontSize,
    fontWeight: fontWeight,
    textAlign: textAlign,
    color: color,
    blocks: blocks
        ?.map(
          (block) => block.copyWith(
            spans: block.spans
                .map((span) => span.copyWith())
                .toList(growable: false),
          ),
        )
        .toList(growable: false),
    fontFamily: fontFamily,
    lineHeight: lineHeight,
    letterSpacing: letterSpacing,
    fontStyle: fontStyle,
    underline: underline,
    strikethrough: strikethrough,
    textTransform: textTransform,
    verticalAlign: verticalAlign,
    sizeMode: sizeMode,
    renderMode: renderMode,
    wrapMode: wrapMode,
    fontAxes: Map<String, double>.from(fontAxes),
    localeTag: localeTag,
    spellCheckEnabled: spellCheckEnabled,
    textPathNodeId: textPathNodeId,
    textPathOffset: textPathOffset,
    textPathReversed: textPathReversed,
    textPathAlignment: textPathAlignment,
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
    shadowColor: shadowColor,
    shadowBlurRadius: shadowBlurRadius,
    shadowOffset: shadowOffset,
    backgroundColor: backgroundColor,
    backgroundRadius: backgroundRadius,
    backgroundPadding: backgroundPadding,
  );

  TextPayload copyWith({
    String? text,
    double? fontSize,
    FontWeight? fontWeight,
    TextAlign? textAlign,
    Color? color,
    List<RichTextBlock>? blocks,
    String? fontFamily,
    double? lineHeight,
    double? letterSpacing,
    FontStyle? fontStyle,
    bool? underline,
    bool? strikethrough,
    TextTransformCase? textTransform,
    TextVerticalAlign? verticalAlign,
    TextSizeMode? sizeMode,
    TextRenderMode? renderMode,
    TextWrapMode? wrapMode,
    Map<String, double>? fontAxes,
    Object? localeTag = _unset,
    bool? spellCheckEnabled,
    Object? textPathNodeId = _unset,
    double? textPathOffset,
    bool? textPathReversed,
    TextPathAlignment? textPathAlignment,
    Color? strokeColor,
    bool clearStrokeColor = false,
    double? strokeWidth,
    Color? shadowColor,
    bool clearShadowColor = false,
    double? shadowBlurRadius,
    Offset? shadowOffset,
    Color? backgroundColor,
    bool clearBackgroundColor = false,
    double? backgroundRadius,
    double? backgroundPadding,
  }) {
    return TextPayload(
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      textAlign: textAlign ?? this.textAlign,
      color: color ?? this.color,
      blocks: blocks ?? this.blocks,
      fontFamily: fontFamily ?? this.fontFamily,
      lineHeight: lineHeight ?? this.lineHeight,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      fontStyle: fontStyle ?? this.fontStyle,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      textTransform: textTransform ?? this.textTransform,
      verticalAlign: verticalAlign ?? this.verticalAlign,
      sizeMode: sizeMode ?? this.sizeMode,
      renderMode: renderMode ?? this.renderMode,
      wrapMode: wrapMode ?? this.wrapMode,
      fontAxes: fontAxes ?? this.fontAxes,
      localeTag: localeTag == _unset ? this.localeTag : localeTag as String?,
      spellCheckEnabled: spellCheckEnabled ?? this.spellCheckEnabled,
      textPathNodeId: textPathNodeId == _unset
          ? this.textPathNodeId
          : textPathNodeId as String?,
      textPathOffset: textPathOffset ?? this.textPathOffset,
      textPathReversed: textPathReversed ?? this.textPathReversed,
      textPathAlignment: textPathAlignment ?? this.textPathAlignment,
      strokeColor: clearStrokeColor ? null : (strokeColor ?? this.strokeColor),
      strokeWidth: strokeWidth ?? this.strokeWidth,
      shadowColor: clearShadowColor ? null : (shadowColor ?? this.shadowColor),
      shadowBlurRadius: shadowBlurRadius ?? this.shadowBlurRadius,
      shadowOffset: shadowOffset ?? this.shadowOffset,
      backgroundColor: clearBackgroundColor
          ? null
          : (backgroundColor ?? this.backgroundColor),
      backgroundRadius: backgroundRadius ?? this.backgroundRadius,
      backgroundPadding: backgroundPadding ?? this.backgroundPadding,
    );
  }

  static const Object _unset = Object();
}

class StickyNotePayload extends NodePayload {
  final String text;
  final Color backgroundColor;
  final Color textColor;
  final double fontSize;
  final String fontFamily;
  final TextAlign textAlign;
  final List<RichTextBlock>? blocks;

  StickyNotePayload({
    this.text = 'Note...',
    this.backgroundColor = const Color(0xFFFEF08A),
    this.textColor = const Color(0xFF1E293B),
    this.fontSize = 14.0,
    this.fontFamily = 'Inter',
    this.textAlign = TextAlign.left,
    this.blocks,
  });

  factory StickyNotePayload.fromJson(Map<String, dynamic> json) {
    return StickyNotePayload(
      text: json['text'] as String? ?? '',
      backgroundColor: Color(
        (json['backgroundColor'] as num?)?.toInt() ?? 0xFFFEF08A,
      ),
      textColor: Color((json['textColor'] as num?)?.toInt() ?? 0xFF1E293B),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
      fontFamily: json['fontFamily'] as String? ?? 'Inter',
      textAlign: TextAlign.values.firstWhere(
        (t) => t.name == json['textAlign'],
        orElse: () => TextAlign.left,
      ),
      blocks: (json['blocks'] as List<dynamic>?)
          ?.map((b) => RichTextBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'text': text,
    'backgroundColor': backgroundColor.toARGB32(),
    'textColor': textColor.toARGB32(),
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'textAlign': textAlign.name,
    'blocks': blocks?.map((b) => b.toJson()).toList(),
  };

  @override
  StickyNotePayload clone() => StickyNotePayload(
    text: text,
    backgroundColor: backgroundColor,
    textColor: textColor,
    fontSize: fontSize,
    fontFamily: fontFamily,
    textAlign: textAlign,
    blocks: blocks == null ? null : List<RichTextBlock>.from(blocks!),
  );

  StickyNotePayload copyWith({
    String? text,
    Color? backgroundColor,
    Color? textColor,
    double? fontSize,
    String? fontFamily,
    TextAlign? textAlign,
    List<RichTextBlock>? blocks,
  }) {
    return StickyNotePayload(
      text: text ?? this.text,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      textAlign: textAlign ?? this.textAlign,
      blocks: blocks ?? this.blocks,
    );
  }
}

enum StrokeStyle { solid, dashed, dotted }

enum LineMarker { none, arrow, circle, diamond }

enum LineRouting { straight, orthogonal, curved }

enum FillType { solid, linearGradient, radialGradient, angularGradient }

class ShapePayload extends NodePayload {
  final Color fill;
  final Color? fillGradientEnd;
  final FillType fillType;
  final double fillOpacity;
  final Color stroke;
  final double strokeWidth;
  final double cornerRadius;
  final bool independentCorners;
  final double topLeftRadius;
  final double topRightRadius;
  final double bottomRightRadius;
  final double bottomLeftRadius;
  final StrokeStyle strokeStyle;
  final bool hasShadow;
  final Color shadowColor;
  final double shadowBlur;
  final double shadowOffsetX;
  final double shadowOffsetY;
  final String label;
  final Color labelColor;
  final double labelFontSize;
  final double startAngle;
  final double sweepAngle;
  final double innerRadiusRatio;
  final String branchTop;
  final String branchRight;
  final String branchBottom;
  final String branchLeft;
  final int cylinderPartitions;
  final double cylinderCapRatio;
  final String badgeText;
  final double skewRatio;
  final String ioType;
  final String subText;
  final double startXRatio;
  final double startYRatio;
  final double endXRatio;
  final double endYRatio;
  final LineMarker startMarker;
  final LineMarker endMarker;
  final LineRouting lineRouting;
  final double curveDepth;

  /// Stable shape key used by the native diagram catalog.
  final String? diagramShapeId;

  /// Original draw.io style/cell data for XML round-tripping.
  final String? rawDrawioStyle;
  final String? rawDrawioCellXml;

  ShapePayload({
    this.fill = const Color(0xFF2563EB), // Retro Slate Cobalt
    this.fillGradientEnd,
    this.fillType = FillType.solid,
    this.fillOpacity = 1.0,
    this.stroke = const Color(0xFF60A5FA),
    this.strokeWidth = 2.0,
    this.cornerRadius = 4.0, // Tactile Braun corner
    this.independentCorners = false,
    double? topLeftRadius,
    double? topRightRadius,
    double? bottomRightRadius,
    double? bottomLeftRadius,
    this.strokeStyle = StrokeStyle.solid,
    this.hasShadow = false,
    this.shadowColor = const Color(0x66000000),
    this.shadowBlur = 8.0,
    this.shadowOffsetX = 0.0,
    this.shadowOffsetY = 4.0,
    this.label = '',
    this.labelColor = Colors.white,
    this.labelFontSize = 14.0,
    this.startAngle = 0.0,
    this.sweepAngle = 360.0,
    this.innerRadiusRatio = 0.0,
    this.branchTop = '',
    this.branchRight = '',
    this.branchBottom = '',
    this.branchLeft = '',
    this.cylinderPartitions = 1,
    this.cylinderCapRatio = 0.25,
    this.badgeText = '',
    this.skewRatio = 0.2,
    this.ioType = '',
    this.subText = '',
    this.startXRatio = 0.0,
    this.startYRatio = 0.0,
    this.endXRatio = 1.0,
    this.endYRatio = 1.0,
    this.startMarker = LineMarker.none,
    this.endMarker = LineMarker.none,
    this.lineRouting = LineRouting.straight,
    this.curveDepth = 0.25,
    this.diagramShapeId,
    this.rawDrawioStyle,
    this.rawDrawioCellXml,
  }) : topLeftRadius = topLeftRadius ?? cornerRadius,
       topRightRadius = topRightRadius ?? cornerRadius,
       bottomRightRadius = bottomRightRadius ?? cornerRadius,
       bottomLeftRadius = bottomLeftRadius ?? cornerRadius;

  factory ShapePayload.fromJson(Map<String, dynamic> json) {
    final uniformRadius = (json['cornerRadius'] as num?)?.toDouble() ?? 0.0;
    final strokeStyleName = json['strokeStyle'] as String? ?? 'solid';
    final fillTypeName = json['fillType'] as String? ?? 'solid';
    return ShapePayload(
      fill: Color((json['fill'] as num?)?.toInt() ?? 0xFF6366F1),
      fillGradientEnd: json['fillGradientEnd'] != null
          ? Color((json['fillGradientEnd'] as num).toInt())
          : null,
      fillType: FillType.values.firstWhere(
        (e) => e.name == fillTypeName,
        orElse: () => FillType.solid,
      ),
      fillOpacity: (json['fillOpacity'] as num?)?.toDouble() ?? 1.0,
      stroke: Color((json['stroke'] as num?)?.toInt() ?? 0xFF818CF8),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      cornerRadius: uniformRadius,
      independentCorners: json['independentCorners'] as bool? ?? false,
      topLeftRadius:
          (json['topLeftRadius'] as num?)?.toDouble() ?? uniformRadius,
      topRightRadius:
          (json['topRightRadius'] as num?)?.toDouble() ?? uniformRadius,
      bottomRightRadius:
          (json['bottomRightRadius'] as num?)?.toDouble() ?? uniformRadius,
      bottomLeftRadius:
          (json['bottomLeftRadius'] as num?)?.toDouble() ?? uniformRadius,
      strokeStyle: StrokeStyle.values.firstWhere(
        (e) => e.name == strokeStyleName,
        orElse: () => StrokeStyle.solid,
      ),
      hasShadow: json['hasShadow'] as bool? ?? false,
      shadowColor: Color((json['shadowColor'] as num?)?.toInt() ?? 0x66000000),
      shadowBlur: (json['shadowBlur'] as num?)?.toDouble() ?? 8.0,
      shadowOffsetX: (json['shadowOffsetX'] as num?)?.toDouble() ?? 0.0,
      shadowOffsetY: (json['shadowOffsetY'] as num?)?.toDouble() ?? 4.0,
      label: json['label'] as String? ?? '',
      labelColor: Color((json['labelColor'] as num?)?.toInt() ?? 0xFFFFFFFF),
      labelFontSize: (json['labelFontSize'] as num?)?.toDouble() ?? 14.0,
      startAngle: (json['startAngle'] as num?)?.toDouble() ?? 0.0,
      sweepAngle: (json['sweepAngle'] as num?)?.toDouble() ?? 360.0,
      innerRadiusRatio: (json['innerRadiusRatio'] as num?)?.toDouble() ?? 0.0,
      branchTop: json['branchTop'] as String? ?? '',
      branchRight: json['branchRight'] as String? ?? '',
      branchBottom: json['branchBottom'] as String? ?? '',
      branchLeft: json['branchLeft'] as String? ?? '',
      cylinderPartitions: (json['cylinderPartitions'] as num?)?.toInt() ?? 1,
      cylinderCapRatio: (json['cylinderCapRatio'] as num?)?.toDouble() ?? 0.25,
      badgeText: json['badgeText'] as String? ?? '',
      skewRatio: (json['skewRatio'] as num?)?.toDouble() ?? 0.2,
      ioType: json['ioType'] as String? ?? '',
      subText: json['subText'] as String? ?? '',
      startXRatio: (json['startXRatio'] as num?)?.toDouble() ?? 0.0,
      startYRatio: (json['startYRatio'] as num?)?.toDouble() ?? 0.0,
      endXRatio: (json['endXRatio'] as num?)?.toDouble() ?? 1.0,
      endYRatio: (json['endYRatio'] as num?)?.toDouble() ?? 1.0,
      startMarker: LineMarker.values.firstWhere(
        (e) => e.name == json['startMarker'],
        orElse: () => LineMarker.none,
      ),
      endMarker: LineMarker.values.firstWhere(
        (e) => e.name == json['endMarker'],
        orElse: () => LineMarker.none,
      ),
      lineRouting: LineRouting.values.firstWhere(
        (e) => e.name == json['lineRouting'],
        orElse: () => LineRouting.straight,
      ),
      curveDepth: (json['curveDepth'] as num?)?.toDouble() ?? 0.25,
      diagramShapeId: json['diagramShapeId'] as String?,
      rawDrawioStyle: json['rawDrawioStyle'] as String?,
      rawDrawioCellXml: json['rawDrawioCellXml'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'fill': fill.toARGB32(),
    'fillGradientEnd': fillGradientEnd?.toARGB32(),
    'fillType': fillType.name,
    'fillOpacity': fillOpacity,
    'stroke': stroke.toARGB32(),
    'strokeWidth': strokeWidth,
    'cornerRadius': cornerRadius,
    'independentCorners': independentCorners,
    'topLeftRadius': topLeftRadius,
    'topRightRadius': topRightRadius,
    'bottomRightRadius': bottomRightRadius,
    'bottomLeftRadius': bottomLeftRadius,
    'strokeStyle': strokeStyle.name,
    'hasShadow': hasShadow,
    'shadowColor': shadowColor.toARGB32(),
    'shadowBlur': shadowBlur,
    'shadowOffsetX': shadowOffsetX,
    'shadowOffsetY': shadowOffsetY,
    'label': label,
    'labelColor': labelColor.toARGB32(),
    'labelFontSize': labelFontSize,
    'startAngle': startAngle,
    'sweepAngle': sweepAngle,
    'innerRadiusRatio': innerRadiusRatio,
    'branchTop': branchTop,
    'branchRight': branchRight,
    'branchBottom': branchBottom,
    'branchLeft': branchLeft,
    'cylinderPartitions': cylinderPartitions,
    'cylinderCapRatio': cylinderCapRatio,
    'badgeText': badgeText,
    'skewRatio': skewRatio,
    'ioType': ioType,
    'subText': subText,
    'startXRatio': startXRatio,
    'startYRatio': startYRatio,
    'endXRatio': endXRatio,
    'endYRatio': endYRatio,
    'startMarker': startMarker.name,
    'endMarker': endMarker.name,
    'lineRouting': lineRouting.name,
    'curveDepth': curveDepth,
    if (diagramShapeId != null) 'diagramShapeId': diagramShapeId,
    if (rawDrawioStyle != null) 'rawDrawioStyle': rawDrawioStyle,
    if (rawDrawioCellXml != null) 'rawDrawioCellXml': rawDrawioCellXml,
  };

  @override
  ShapePayload clone() => ShapePayload(
    fill: fill,
    fillGradientEnd: fillGradientEnd,
    fillType: fillType,
    fillOpacity: fillOpacity,
    stroke: stroke,
    strokeWidth: strokeWidth,
    cornerRadius: cornerRadius,
    independentCorners: independentCorners,
    topLeftRadius: topLeftRadius,
    topRightRadius: topRightRadius,
    bottomRightRadius: bottomRightRadius,
    bottomLeftRadius: bottomLeftRadius,
    strokeStyle: strokeStyle,
    hasShadow: hasShadow,
    shadowColor: shadowColor,
    shadowBlur: shadowBlur,
    shadowOffsetX: shadowOffsetX,
    shadowOffsetY: shadowOffsetY,
    label: label,
    labelColor: labelColor,
    labelFontSize: labelFontSize,
    startAngle: startAngle,
    sweepAngle: sweepAngle,
    innerRadiusRatio: innerRadiusRatio,
    branchTop: branchTop,
    branchRight: branchRight,
    branchBottom: branchBottom,
    branchLeft: branchLeft,
    cylinderPartitions: cylinderPartitions,
    cylinderCapRatio: cylinderCapRatio,
    badgeText: badgeText,
    skewRatio: skewRatio,
    ioType: ioType,
    subText: subText,
    startXRatio: startXRatio,
    startYRatio: startYRatio,
    endXRatio: endXRatio,
    endYRatio: endYRatio,
    startMarker: startMarker,
    endMarker: endMarker,
    lineRouting: lineRouting,
    curveDepth: curveDepth,
    diagramShapeId: diagramShapeId,
    rawDrawioStyle: rawDrawioStyle,
    rawDrawioCellXml: rawDrawioCellXml,
  );

  ShapePayload copyWith({
    Color? fill,
    Color? fillGradientEnd,
    FillType? fillType,
    double? fillOpacity,
    Color? stroke,
    double? strokeWidth,
    double? cornerRadius,
    bool? independentCorners,
    double? topLeftRadius,
    double? topRightRadius,
    double? bottomRightRadius,
    double? bottomLeftRadius,
    StrokeStyle? strokeStyle,
    bool? hasShadow,
    Color? shadowColor,
    double? shadowBlur,
    double? shadowOffsetX,
    double? shadowOffsetY,
    String? label,
    Color? labelColor,
    double? labelFontSize,
    double? startAngle,
    double? sweepAngle,
    double? innerRadiusRatio,
    String? branchTop,
    String? branchRight,
    String? branchBottom,
    String? branchLeft,
    int? cylinderPartitions,
    double? cylinderCapRatio,
    String? badgeText,
    double? skewRatio,
    String? ioType,
    String? subText,
    double? startXRatio,
    double? startYRatio,
    double? endXRatio,
    double? endYRatio,
    LineMarker? startMarker,
    LineMarker? endMarker,
    LineRouting? lineRouting,
    double? curveDepth,
    String? diagramShapeId,
    String? rawDrawioStyle,
    String? rawDrawioCellXml,
  }) {
    final nextCornerRadius = cornerRadius ?? this.cornerRadius;
    return ShapePayload(
      fill: fill ?? this.fill,
      fillGradientEnd: fillGradientEnd ?? this.fillGradientEnd,
      fillType: fillType ?? this.fillType,
      fillOpacity: fillOpacity ?? this.fillOpacity,
      stroke: stroke ?? this.stroke,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      cornerRadius: nextCornerRadius,
      independentCorners: independentCorners ?? this.independentCorners,
      topLeftRadius:
          topLeftRadius ??
          (cornerRadius != null ? nextCornerRadius : this.topLeftRadius),
      topRightRadius:
          topRightRadius ??
          (cornerRadius != null ? nextCornerRadius : this.topRightRadius),
      bottomRightRadius:
          bottomRightRadius ??
          (cornerRadius != null ? nextCornerRadius : this.bottomRightRadius),
      bottomLeftRadius:
          bottomLeftRadius ??
          (cornerRadius != null ? nextCornerRadius : this.bottomLeftRadius),
      strokeStyle: strokeStyle ?? this.strokeStyle,
      hasShadow: hasShadow ?? this.hasShadow,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowOffsetX: shadowOffsetX ?? this.shadowOffsetX,
      shadowOffsetY: shadowOffsetY ?? this.shadowOffsetY,
      label: label ?? this.label,
      labelColor: labelColor ?? this.labelColor,
      labelFontSize: labelFontSize ?? this.labelFontSize,
      startAngle: startAngle ?? this.startAngle,
      sweepAngle: sweepAngle ?? this.sweepAngle,
      innerRadiusRatio: innerRadiusRatio ?? this.innerRadiusRatio,
      branchTop: branchTop ?? this.branchTop,
      branchRight: branchRight ?? this.branchRight,
      branchBottom: branchBottom ?? this.branchBottom,
      branchLeft: branchLeft ?? this.branchLeft,
      cylinderPartitions: cylinderPartitions ?? this.cylinderPartitions,
      cylinderCapRatio: cylinderCapRatio ?? this.cylinderCapRatio,
      badgeText: badgeText ?? this.badgeText,
      skewRatio: skewRatio ?? this.skewRatio,
      ioType: ioType ?? this.ioType,
      subText: subText ?? this.subText,
      startXRatio: startXRatio ?? this.startXRatio,
      startYRatio: startYRatio ?? this.startYRatio,
      endXRatio: endXRatio ?? this.endXRatio,
      endYRatio: endYRatio ?? this.endYRatio,
      startMarker: startMarker ?? this.startMarker,
      endMarker: endMarker ?? this.endMarker,
      lineRouting: lineRouting ?? this.lineRouting,
      curveDepth: curveDepth ?? this.curveDepth,
      diagramShapeId: diagramShapeId ?? this.diagramShapeId,
      rawDrawioStyle: rawDrawioStyle ?? this.rawDrawioStyle,
      rawDrawioCellXml: rawDrawioCellXml ?? this.rawDrawioCellXml,
    );
  }
}

class ImagePayload extends NodePayload {
  final String? assetId;

  /// Opaque owned artifact reference. Runtime delivery stays in [localPath] or
  /// [url] after the document hydration boundary.
  final String? imageArtifactReference;

  /// Stable project-scoped Storage metadata. Runtime delivery stays in [url].
  final String? storagePath;

  /// Safe generated-source metadata. Image bytes and delivery handles remain
  /// outside the durable payload.
  final String? mimeType;
  final int? byteLength;
  final String? localPath;
  final String? url;
  final String fit; // 'contain', 'cover', 'fill', 'fitWidth', 'fitHeight'
  final String? caption;
  final double cropX;
  final double cropY;
  final double cropWidth;
  final double cropHeight;

  // Corner radius & styling
  final double cornerRadius;
  final bool independentCorners;
  final double topLeftRadius;
  final double topRightRadius;
  final double bottomRightRadius;
  final double bottomLeftRadius;

  // Stroke / border
  final Color? strokeColor;
  final double strokeWidth;
  final StrokeStyle strokeStyle;

  // Shadow
  final bool hasShadow;
  final Color shadowColor;
  final double shadowBlur;
  final double shadowOffsetX;
  final double shadowOffsetY;

  // Color & Image Filters
  final bool grayscale;
  final bool sepia;
  final bool invert;
  final double brightness; // -1.0 to 1.0 (default 0.0)
  final double contrast; // 0.0 to 2.0 (default 1.0)
  final double blur; // 0.0 to 20.0 (default 0.0)

  // Transformations
  final bool flipHorizontal;
  final bool flipVertical;
  final bool aspectRatioLocked;
  final double focalPointX;
  final double focalPointY;
  final List<ImageAdjustment> adjustments;
  final ImageMask? backgroundMask;

  ImagePayload({
    this.assetId,
    this.imageArtifactReference,
    this.storagePath,
    this.mimeType,
    this.byteLength,
    this.localPath,
    this.url,
    this.fit = 'cover',
    this.caption,
    this.cropX = 0.0,
    this.cropY = 0.0,
    this.cropWidth = 1.0,
    this.cropHeight = 1.0,
    this.cornerRadius = 0.0,
    this.independentCorners = false,
    double? topLeftRadius,
    double? topRightRadius,
    double? bottomRightRadius,
    double? bottomLeftRadius,
    this.strokeColor,
    this.strokeWidth = 0.0,
    this.strokeStyle = StrokeStyle.solid,
    this.hasShadow = false,
    this.shadowColor = const Color(0x66000000),
    this.shadowBlur = 8.0,
    this.shadowOffsetX = 0.0,
    this.shadowOffsetY = 4.0,
    this.grayscale = false,
    this.sepia = false,
    this.invert = false,
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.blur = 0.0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.aspectRatioLocked = false,
    this.focalPointX = 0.5,
    this.focalPointY = 0.5,
    this.adjustments = const [],
    this.backgroundMask,
  }) : topLeftRadius = topLeftRadius ?? cornerRadius,
       topRightRadius = topRightRadius ?? cornerRadius,
       bottomRightRadius = bottomRightRadius ?? cornerRadius,
       bottomLeftRadius = bottomLeftRadius ?? cornerRadius;

  factory ImagePayload.fromJson(Map<String, dynamic> json) {
    final uniformRadius = (json['cornerRadius'] as num?)?.toDouble() ?? 0.0;
    final strokeStyleName = json['strokeStyle'] as String? ?? 'solid';

    return ImagePayload(
      assetId: json['assetId'] as String?,
      imageArtifactReference: validImageArtifactReference(
        json['imageArtifactReference'] as String?,
      ),
      storagePath: durableAssetReference(json['storagePath'] as String?),
      mimeType: _imageMimeType(json['mimeType'] as String?),
      byteLength: (json['byteLength'] as num?)?.toInt(),
      // Local paths and runtime delivery URLs are never restored from the
      // durable document envelope. Legacy public URLs are intentionally
      // dropped so provider output cannot become durable document state.
      localPath: null,
      url: null,
      fit: json['fit'] as String? ?? 'cover',
      caption: json['caption'] as String?,
      cropX: (json['cropX'] as num?)?.toDouble() ?? 0.0,
      cropY: (json['cropY'] as num?)?.toDouble() ?? 0.0,
      cropWidth: (json['cropWidth'] as num?)?.toDouble() ?? 1.0,
      cropHeight: (json['cropHeight'] as num?)?.toDouble() ?? 1.0,
      cornerRadius: uniformRadius,
      independentCorners: json['independentCorners'] as bool? ?? false,
      topLeftRadius:
          (json['topLeftRadius'] as num?)?.toDouble() ?? uniformRadius,
      topRightRadius:
          (json['topRightRadius'] as num?)?.toDouble() ?? uniformRadius,
      bottomRightRadius:
          (json['bottomRightRadius'] as num?)?.toDouble() ?? uniformRadius,
      bottomLeftRadius:
          (json['bottomLeftRadius'] as num?)?.toDouble() ?? uniformRadius,
      strokeColor: json['strokeColor'] != null
          ? Color((json['strokeColor'] as num).toInt())
          : null,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 0.0,
      strokeStyle: StrokeStyle.values.firstWhere(
        (e) => e.name == strokeStyleName,
        orElse: () => StrokeStyle.solid,
      ),
      hasShadow: json['hasShadow'] as bool? ?? false,
      shadowColor: Color((json['shadowColor'] as num?)?.toInt() ?? 0x66000000),
      shadowBlur: (json['shadowBlur'] as num?)?.toDouble() ?? 8.0,
      shadowOffsetX: (json['shadowOffsetX'] as num?)?.toDouble() ?? 0.0,
      shadowOffsetY: (json['shadowOffsetY'] as num?)?.toDouble() ?? 4.0,
      grayscale: json['grayscale'] as bool? ?? false,
      sepia: json['sepia'] as bool? ?? false,
      invert: json['invert'] as bool? ?? false,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
      blur: (json['blur'] as num?)?.toDouble() ?? 0.0,
      flipHorizontal: json['flipHorizontal'] as bool? ?? false,
      flipVertical: json['flipVertical'] as bool? ?? false,
      aspectRatioLocked: json['aspectRatioLocked'] as bool? ?? false,
      focalPointX: (json['focalPointX'] as num?)?.toDouble() ?? 0.5,
      focalPointY: (json['focalPointY'] as num?)?.toDouble() ?? 0.5,
      adjustments: (json['adjustments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (entry) =>
                ImageAdjustment.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(growable: false),
      backgroundMask: json['backgroundMask'] is Map
          ? ImageMask.fromJson(
              Map<String, dynamic>.from(json['backgroundMask'] as Map),
            )
          : null,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    if (assetId != null) 'assetId': assetId,
    'imageArtifactReference': ?validImageArtifactReference(
      imageArtifactReference,
    ),
    'storagePath': ?durableAssetReference(storagePath),
    'mimeType': ?_imageMimeType(mimeType),
    if (byteLength case final value? when value > 0) 'byteLength': value,
    'fit': fit,
    'caption': caption,
    'cropX': cropX,
    'cropY': cropY,
    'cropWidth': cropWidth,
    'cropHeight': cropHeight,
    'cornerRadius': cornerRadius,
    'independentCorners': independentCorners,
    'topLeftRadius': topLeftRadius,
    'topRightRadius': topRightRadius,
    'bottomRightRadius': bottomRightRadius,
    'bottomLeftRadius': bottomLeftRadius,
    'strokeColor': strokeColor?.toARGB32(),
    'strokeWidth': strokeWidth,
    'strokeStyle': strokeStyle.name,
    'hasShadow': hasShadow,
    'shadowColor': shadowColor.toARGB32(),
    'shadowBlur': shadowBlur,
    'shadowOffsetX': shadowOffsetX,
    'shadowOffsetY': shadowOffsetY,
    'grayscale': grayscale,
    'sepia': sepia,
    'invert': invert,
    'brightness': brightness,
    'contrast': contrast,
    'blur': blur,
    'flipHorizontal': flipHorizontal,
    'flipVertical': flipVertical,
    'aspectRatioLocked': aspectRatioLocked,
    'focalPointX': focalPointX,
    'focalPointY': focalPointY,
    'adjustments': adjustments
        .map((adjustment) => adjustment.toJson())
        .toList(),
    'backgroundMask': backgroundMask?.toJson(),
  };

  @override
  ImagePayload clone() => ImagePayload(
    assetId: assetId,
    imageArtifactReference: imageArtifactReference,
    storagePath: storagePath,
    mimeType: mimeType,
    byteLength: byteLength,
    localPath: localPath,
    url: url,
    fit: fit,
    caption: caption,
    cropX: cropX,
    cropY: cropY,
    cropWidth: cropWidth,
    cropHeight: cropHeight,
    cornerRadius: cornerRadius,
    independentCorners: independentCorners,
    topLeftRadius: topLeftRadius,
    topRightRadius: topRightRadius,
    bottomRightRadius: bottomRightRadius,
    bottomLeftRadius: bottomLeftRadius,
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
    strokeStyle: strokeStyle,
    hasShadow: hasShadow,
    shadowColor: shadowColor,
    shadowBlur: shadowBlur,
    shadowOffsetX: shadowOffsetX,
    shadowOffsetY: shadowOffsetY,
    grayscale: grayscale,
    sepia: sepia,
    invert: invert,
    brightness: brightness,
    contrast: contrast,
    blur: blur,
    flipHorizontal: flipHorizontal,
    flipVertical: flipVertical,
    aspectRatioLocked: aspectRatioLocked,
    focalPointX: focalPointX,
    focalPointY: focalPointY,
    adjustments: adjustments
        .map((adjustment) => adjustment.copyWith())
        .toList(growable: false),
    backgroundMask: backgroundMask?.copyWith(),
  );

  ImagePayload copyWith({
    String? assetId,
    String? imageArtifactReference,
    String? storagePath,
    String? mimeType,
    int? byteLength,
    String? localPath,
    String? url,
    String? fit,
    String? caption,
    double? cropX,
    double? cropY,
    double? cropWidth,
    double? cropHeight,
    double? cornerRadius,
    bool? independentCorners,
    double? topLeftRadius,
    double? topRightRadius,
    double? bottomRightRadius,
    double? bottomLeftRadius,
    Color? strokeColor,
    bool clearStrokeColor = false,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    bool? hasShadow,
    Color? shadowColor,
    double? shadowBlur,
    double? shadowOffsetX,
    double? shadowOffsetY,
    bool? grayscale,
    bool? sepia,
    bool? invert,
    double? brightness,
    double? contrast,
    double? blur,
    bool? flipHorizontal,
    bool? flipVertical,
    bool? aspectRatioLocked,
    double? focalPointX,
    double? focalPointY,
    List<ImageAdjustment>? adjustments,
    ImageMask? backgroundMask,
    bool clearImageArtifactReference = false,
    bool clearStoragePath = false,
    bool clearLocalPath = false,
    bool clearUrl = false,
    bool clearBackgroundMask = false,
  }) {
    final nextCornerRadius = cornerRadius ?? this.cornerRadius;
    return ImagePayload(
      assetId: assetId ?? this.assetId,
      imageArtifactReference: clearImageArtifactReference
          ? null
          : (imageArtifactReference ?? this.imageArtifactReference),
      storagePath: clearStoragePath ? null : (storagePath ?? this.storagePath),
      mimeType: _imageMimeType(mimeType ?? this.mimeType),
      byteLength: byteLength ?? this.byteLength,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      url: clearUrl ? null : (url ?? this.url),
      fit: fit ?? this.fit,
      caption: caption ?? this.caption,
      cropX: cropX ?? this.cropX,
      cropY: cropY ?? this.cropY,
      cropWidth: cropWidth ?? this.cropWidth,
      cropHeight: cropHeight ?? this.cropHeight,
      cornerRadius: nextCornerRadius,
      independentCorners: independentCorners ?? this.independentCorners,
      topLeftRadius:
          topLeftRadius ??
          (cornerRadius != null ? nextCornerRadius : this.topLeftRadius),
      topRightRadius:
          topRightRadius ??
          (cornerRadius != null ? nextCornerRadius : this.topRightRadius),
      bottomRightRadius:
          bottomRightRadius ??
          (cornerRadius != null ? nextCornerRadius : this.bottomRightRadius),
      bottomLeftRadius:
          bottomLeftRadius ??
          (cornerRadius != null ? nextCornerRadius : this.bottomLeftRadius),
      strokeColor: clearStrokeColor ? null : (strokeColor ?? this.strokeColor),
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeStyle: strokeStyle ?? this.strokeStyle,
      hasShadow: hasShadow ?? this.hasShadow,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowOffsetX: shadowOffsetX ?? this.shadowOffsetX,
      shadowOffsetY: shadowOffsetY ?? this.shadowOffsetY,
      grayscale: grayscale ?? this.grayscale,
      sepia: sepia ?? this.sepia,
      invert: invert ?? this.invert,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      blur: blur ?? this.blur,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      aspectRatioLocked: aspectRatioLocked ?? this.aspectRatioLocked,
      focalPointX: focalPointX ?? this.focalPointX,
      focalPointY: focalPointY ?? this.focalPointY,
      adjustments: adjustments ?? this.adjustments,
      backgroundMask: clearBackgroundMask
          ? null
          : (backgroundMask ?? this.backgroundMask),
    );
  }

  static String? _imageMimeType(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized != null && normalized.startsWith('image/')
        ? normalized
        : null;
  }
}

enum AutoLayoutDirection { none, horizontal, vertical }

enum AutoLayoutAlign { start, center, end, spaceBetween }

class FramePayload extends NodePayload {
  final String name;
  final Color background;
  final Color? backgroundGradientEnd;
  final bool clipContent;
  final double cornerRadius;
  final Color borderColor;
  final double borderWidth;
  final bool isDashedBorder;
  final bool hasShadow;
  final double shadowBlur;
  final Color shadowColor;

  // Auto-Layout properties
  final AutoLayoutDirection layoutDirection;
  final double itemSpacing;
  final double paddingLeft;
  final double paddingTop;
  final double paddingRight;
  final double paddingBottom;
  final AutoLayoutAlign layoutAlign;

  // Preset & Orientation metadata
  final String? presetId;
  final bool isLandscape;
  final String? rawDrawioStyle;
  final String? rawDrawioCellXml;

  FramePayload({
    this.name = 'Frame',
    this.background = const Color(0xFF1E293B),
    this.backgroundGradientEnd,
    this.clipContent = true,
    this.cornerRadius = 0.0,
    this.borderColor = const Color(0xFF6366F1),
    this.borderWidth = 1.5,
    this.isDashedBorder = false,
    this.hasShadow = false,
    this.shadowBlur = 12.0,
    this.shadowColor = const Color(0x66000000),
    this.layoutDirection = AutoLayoutDirection.none,
    this.itemSpacing = 16.0,
    this.paddingLeft = 16.0,
    this.paddingTop = 16.0,
    this.paddingRight = 16.0,
    this.paddingBottom = 16.0,
    this.layoutAlign = AutoLayoutAlign.start,
    this.presetId,
    this.isLandscape = false,
    this.rawDrawioStyle,
    this.rawDrawioCellXml,
  });

  String get title => name;

  factory FramePayload.fromJson(Map<String, dynamic> json) {
    return FramePayload(
      name: json['name'] as String? ?? 'Frame',
      background: Color((json['background'] as num?)?.toInt() ?? 0xFF1E293B),
      backgroundGradientEnd: json['backgroundGradientEnd'] != null
          ? Color((json['backgroundGradientEnd'] as num).toInt())
          : null,
      clipContent: json['clipContent'] as bool? ?? true,
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 0.0,
      borderColor: Color((json['borderColor'] as num?)?.toInt() ?? 0xFF6366F1),
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 1.5,
      isDashedBorder: json['isDashedBorder'] as bool? ?? false,
      hasShadow: json['hasShadow'] as bool? ?? false,
      shadowBlur: (json['shadowBlur'] as num?)?.toDouble() ?? 12.0,
      shadowColor: Color((json['shadowColor'] as num?)?.toInt() ?? 0x66000000),
      layoutDirection: AutoLayoutDirection.values.firstWhere(
        (e) => e.name == (json['layoutDirection'] as String?),
        orElse: () => AutoLayoutDirection.none,
      ),
      itemSpacing: (json['itemSpacing'] as num?)?.toDouble() ?? 16.0,
      paddingLeft: (json['paddingLeft'] as num?)?.toDouble() ?? 16.0,
      paddingTop: (json['paddingTop'] as num?)?.toDouble() ?? 16.0,
      paddingRight: (json['paddingRight'] as num?)?.toDouble() ?? 16.0,
      paddingBottom: (json['paddingBottom'] as num?)?.toDouble() ?? 16.0,
      layoutAlign: AutoLayoutAlign.values.firstWhere(
        (e) => e.name == (json['layoutAlign'] as String?),
        orElse: () => AutoLayoutAlign.start,
      ),
      presetId: json['presetId'] as String?,
      isLandscape: json['isLandscape'] as bool? ?? false,
      rawDrawioStyle: json['rawDrawioStyle'] as String?,
      rawDrawioCellXml: json['rawDrawioCellXml'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    'background': background.toARGB32(),
    if (backgroundGradientEnd != null)
      'backgroundGradientEnd': backgroundGradientEnd!.toARGB32(),
    'clipContent': clipContent,
    'cornerRadius': cornerRadius,
    'borderColor': borderColor.toARGB32(),
    'borderWidth': borderWidth,
    'isDashedBorder': isDashedBorder,
    'hasShadow': hasShadow,
    'shadowBlur': shadowBlur,
    'shadowColor': shadowColor.toARGB32(),
    'layoutDirection': layoutDirection.name,
    'itemSpacing': itemSpacing,
    'paddingLeft': paddingLeft,
    'paddingTop': paddingTop,
    'paddingRight': paddingRight,
    'paddingBottom': paddingBottom,
    'layoutAlign': layoutAlign.name,
    if (presetId != null) 'presetId': presetId,
    'isLandscape': isLandscape,
    if (rawDrawioStyle != null) 'rawDrawioStyle': rawDrawioStyle,
    if (rawDrawioCellXml != null) 'rawDrawioCellXml': rawDrawioCellXml,
  };

  @override
  FramePayload clone() => FramePayload(
    name: name,
    background: background,
    backgroundGradientEnd: backgroundGradientEnd,
    clipContent: clipContent,
    cornerRadius: cornerRadius,
    borderColor: borderColor,
    borderWidth: borderWidth,
    isDashedBorder: isDashedBorder,
    hasShadow: hasShadow,
    shadowBlur: shadowBlur,
    shadowColor: shadowColor,
    layoutDirection: layoutDirection,
    itemSpacing: itemSpacing,
    paddingLeft: paddingLeft,
    paddingTop: paddingTop,
    paddingRight: paddingRight,
    paddingBottom: paddingBottom,
    layoutAlign: layoutAlign,
    presetId: presetId,
    isLandscape: isLandscape,
    rawDrawioStyle: rawDrawioStyle,
    rawDrawioCellXml: rawDrawioCellXml,
  );

  FramePayload copyWith({
    String? name,
    Color? background,
    Color? backgroundGradientEnd,
    bool? clearGradient,
    bool? clipContent,
    double? cornerRadius,
    Color? borderColor,
    double? borderWidth,
    bool? isDashedBorder,
    bool? hasShadow,
    double? shadowBlur,
    Color? shadowColor,
    AutoLayoutDirection? layoutDirection,
    double? itemSpacing,
    double? paddingLeft,
    double? paddingTop,
    double? paddingRight,
    double? paddingBottom,
    AutoLayoutAlign? layoutAlign,
    String? presetId,
    bool? isLandscape,
    String? rawDrawioStyle,
    String? rawDrawioCellXml,
  }) {
    return FramePayload(
      name: name ?? this.name,
      background: background ?? this.background,
      backgroundGradientEnd: (clearGradient ?? false)
          ? null
          : (backgroundGradientEnd ?? this.backgroundGradientEnd),
      clipContent: clipContent ?? this.clipContent,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      isDashedBorder: isDashedBorder ?? this.isDashedBorder,
      hasShadow: hasShadow ?? this.hasShadow,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowColor: shadowColor ?? this.shadowColor,
      layoutDirection: layoutDirection ?? this.layoutDirection,
      itemSpacing: itemSpacing ?? this.itemSpacing,
      paddingLeft: paddingLeft ?? this.paddingLeft,
      paddingTop: paddingTop ?? this.paddingTop,
      paddingRight: paddingRight ?? this.paddingRight,
      paddingBottom: paddingBottom ?? this.paddingBottom,
      layoutAlign: layoutAlign ?? this.layoutAlign,
      presetId: presetId ?? this.presetId,
      isLandscape: isLandscape ?? this.isLandscape,
      rawDrawioStyle: rawDrawioStyle ?? this.rawDrawioStyle,
      rawDrawioCellXml: rawDrawioCellXml ?? this.rawDrawioCellXml,
    );
  }
}

class GroupPayload extends NodePayload {
  final String name;
  final List<String> childNodeIds;
  final String? rawDrawioStyle;
  final String? rawDrawioCellXml;

  GroupPayload({
    this.name = 'Group',
    this.childNodeIds = const [],
    this.rawDrawioStyle,
    this.rawDrawioCellXml,
  });

  factory GroupPayload.fromJson(Map<String, dynamic> json) {
    return GroupPayload(
      name: json['name'] as String? ?? 'Group',
      childNodeIds:
          (json['childNodeIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      rawDrawioStyle: json['rawDrawioStyle'] as String?,
      rawDrawioCellXml: json['rawDrawioCellXml'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    'childNodeIds': childNodeIds,
    if (rawDrawioStyle != null) 'rawDrawioStyle': rawDrawioStyle,
    if (rawDrawioCellXml != null) 'rawDrawioCellXml': rawDrawioCellXml,
  };

  @override
  GroupPayload clone() => GroupPayload(
    name: name,
    childNodeIds: List<String>.from(childNodeIds),
    rawDrawioStyle: rawDrawioStyle,
    rawDrawioCellXml: rawDrawioCellXml,
  );

  GroupPayload copyWith({
    String? name,
    List<String>? childNodeIds,
    String? rawDrawioStyle,
    String? rawDrawioCellXml,
  }) {
    return GroupPayload(
      name: name ?? this.name,
      childNodeIds: childNodeIds ?? this.childNodeIds,
      rawDrawioStyle: rawDrawioStyle ?? this.rawDrawioStyle,
      rawDrawioCellXml: rawDrawioCellXml ?? this.rawDrawioCellXml,
    );
  }
}

// -------------------------------------------------------------
// INFINITE BOARD - CONTENT NODES
// -------------------------------------------------------------

class FilePayload extends NodePayload {
  final String fileName;
  final String fileExtension;
  final String fileSizeText;

  /// Stable manifest identity for the attached file artifact.
  final String? assetId;

  /// Opaque owned file/PDF artifact reference. Runtime paths, bytes, and URLs
  /// are kept only on live render payloads and are excluded from persistence.
  final String? artifactReference;
  final String? storagePath;
  final String? localPath;
  final String? base64Data;
  final String? remoteUrl;
  final String? description;
  final Color? customBadgeColor;
  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;
  final double cornerRadius;
  final bool hasShadow;
  final Color shadowColor;
  final double shadowBlur;
  final PdfAnnotationData pdfAnnotations;

  FilePayload({
    this.fileName = 'Document.pdf',
    this.fileExtension = 'PDF',
    this.fileSizeText = '2.4 MB',
    this.assetId,
    this.artifactReference,
    this.storagePath,
    this.localPath,
    this.base64Data,
    this.remoteUrl,
    this.description,
    this.customBadgeColor,
    this.backgroundColor = const Color(0xFF22242A),
    this.borderColor = const Color(0xFF373A44),
    this.borderWidth = 1.2,
    this.cornerRadius = 8.0,
    this.hasShadow = true,
    this.shadowColor = const Color(0x33000000),
    this.shadowBlur = 8.0,
    this.pdfAnnotations = const PdfAnnotationData(),
  });

  factory FilePayload.fromJson(Map<String, dynamic> json) => FilePayload(
    fileName: json['fileName'] as String? ?? 'Document.pdf',
    fileExtension: json['fileExtension'] as String? ?? 'PDF',
    fileSizeText: json['fileSizeText'] as String? ?? '2.4 MB',
    assetId: json['assetId'] as String?,
    artifactReference: validFileArtifactReference(
      json['artifactReference'] as String?,
    ),
    storagePath: durableAssetReference(json['storagePath'] as String?),
    // Local paths, inline bytes, and delivery URLs are runtime-only. Stable
    // Storage references remain available for transient hydration.
    localPath: null,
    base64Data: null,
    remoteUrl: null,
    description: json['description'] as String?,
    customBadgeColor: json['customBadgeColor'] != null
        ? Color(json['customBadgeColor'] as int)
        : null,
    backgroundColor: json['backgroundColor'] != null
        ? Color(json['backgroundColor'] as int)
        : const Color(0xFF22242A),
    borderColor: json['borderColor'] != null
        ? Color(json['borderColor'] as int)
        : const Color(0xFF373A44),
    borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 1.2,
    cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 8.0,
    hasShadow: json['hasShadow'] as bool? ?? true,
    shadowColor: json['shadowColor'] != null
        ? Color(json['shadowColor'] as int)
        : const Color(0x33000000),
    shadowBlur: (json['shadowBlur'] as num?)?.toDouble() ?? 8.0,
    pdfAnnotations: PdfAnnotationData.fromJson(
      json['pdfAnnotations'] as Map<String, dynamic>?,
    ),
  );

  @override
  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'fileExtension': fileExtension,
    'fileSizeText': fileSizeText,
    if (assetId != null) 'assetId': assetId,
    'artifactReference': ?validFileArtifactReference(artifactReference),
    'storagePath': ?durableAssetReference(storagePath),
    // Local paths, inline bytes, and runtime delivery URLs are omitted.
    'description': description,
    'customBadgeColor': customBadgeColor?.toARGB32(),
    'backgroundColor': backgroundColor.toARGB32(),
    'borderColor': borderColor.toARGB32(),
    'borderWidth': borderWidth,
    'cornerRadius': cornerRadius,
    'hasShadow': hasShadow,
    'shadowColor': shadowColor.toARGB32(),
    'shadowBlur': shadowBlur,
    'pdfAnnotations': pdfAnnotations.toJson(),
  };

  @override
  FilePayload clone() => FilePayload(
    fileName: fileName,
    fileExtension: fileExtension,
    fileSizeText: fileSizeText,
    assetId: assetId,
    artifactReference: artifactReference,
    storagePath: storagePath,
    localPath: localPath,
    base64Data: base64Data,
    remoteUrl: remoteUrl,
    description: description,
    customBadgeColor: customBadgeColor,
    backgroundColor: backgroundColor,
    borderColor: borderColor,
    borderWidth: borderWidth,
    cornerRadius: cornerRadius,
    hasShadow: hasShadow,
    shadowColor: shadowColor,
    shadowBlur: shadowBlur,
    pdfAnnotations: pdfAnnotations,
  );

  FilePayload copyWith({
    String? fileName,
    String? fileExtension,
    String? fileSizeText,
    String? assetId,
    String? artifactReference,
    String? storagePath,
    String? localPath,
    String? base64Data,
    String? remoteUrl,
    String? description,
    Color? customBadgeColor,
    bool clearBadgeColor = false,
    Color? backgroundColor,
    Color? borderColor,
    double? borderWidth,
    double? cornerRadius,
    bool? hasShadow,
    Color? shadowColor,
    double? shadowBlur,
    PdfAnnotationData? pdfAnnotations,
    bool clearPdfAnnotations = false,
    bool clearArtifactReference = false,
    bool clearStoragePath = false,
    bool clearLocalPath = false,
    bool clearBase64Data = false,
    bool clearRemoteUrl = false,
  }) {
    return FilePayload(
      fileName: fileName ?? this.fileName,
      fileExtension: fileExtension ?? this.fileExtension,
      fileSizeText: fileSizeText ?? this.fileSizeText,
      assetId: assetId ?? this.assetId,
      artifactReference: clearArtifactReference
          ? null
          : validFileArtifactReference(
              artifactReference ?? this.artifactReference,
            ),
      storagePath: clearStoragePath ? null : storagePath ?? this.storagePath,
      localPath: clearLocalPath ? null : localPath ?? this.localPath,
      base64Data: clearBase64Data ? null : base64Data ?? this.base64Data,
      remoteUrl: clearRemoteUrl ? null : remoteUrl ?? this.remoteUrl,
      description: description ?? this.description,
      customBadgeColor: clearBadgeColor
          ? null
          : (customBadgeColor ?? this.customBadgeColor),
      backgroundColor: backgroundColor ?? this.backgroundColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      hasShadow: hasShadow ?? this.hasShadow,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      pdfAnnotations: clearPdfAnnotations
          ? const PdfAnnotationData()
          : (pdfAnnotations ?? this.pdfAnnotations),
    );
  }
}

class DocumentPayload extends NodePayload {
  final String title;
  final List<RichTextBlock> blocks;
  final String? deltaJson;
  final String
  paperPresetId; // 'a4', 'letter', 'a5', 'a3', 'legal', 'executive', 'b5', 'square', 'custom'
  final bool isLandscape;
  final double customWidth;
  final double customHeight;
  final String themeId; // 'default_light', 'ivory', 'sepia', 'dark'
  final double marginPreset; // 32, 64, 96
  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;
  final double cornerRadius;
  final bool hasShadow;
  final bool showHeaderBar;

  DocumentPayload({
    this.title = 'Untitled Document',
    List<RichTextBlock>? blocks,
    this.deltaJson,
    this.paperPresetId = 'a4',
    this.isLandscape = false,
    this.customWidth = 595.0,
    this.customHeight = 842.0,
    this.themeId = 'default_light',
    this.marginPreset = 64.0,
    this.backgroundColor = const Color(0xFFFDFDFC),
    this.borderColor = const Color(0xFFD1D5DB),
    this.borderWidth = 1.2,
    this.cornerRadius = 6.0,
    this.hasShadow = true,
    this.showHeaderBar = false,
  }) : blocks =
           blocks ??
           [
             const RichTextBlock(
               spans: [RichTextSpan(text: 'Start writing your document...')],
             ),
           ];

  factory DocumentPayload.fromJson(Map<String, dynamic> json) =>
      DocumentPayload(
        title: json['title'] as String? ?? 'Untitled Document',
        blocks: (json['blocks'] as List<dynamic>?)
            ?.map((b) => RichTextBlock.fromJson(b as Map<String, dynamic>))
            .toList(),
        deltaJson: json['deltaJson'] as String?,
        paperPresetId: json['paperPresetId'] as String? ?? 'a4',
        isLandscape: json['isLandscape'] as bool? ?? false,
        customWidth: (json['customWidth'] as num?)?.toDouble() ?? 595.0,
        customHeight: (json['customHeight'] as num?)?.toDouble() ?? 842.0,
        themeId: json['themeId'] as String? ?? 'default_light',
        marginPreset: (json['marginPreset'] as num?)?.toDouble() ?? 64.0,
        backgroundColor: Color(
          (json['backgroundColor'] as num?)?.toInt() ?? 0xFFFDFDFC,
        ),
        borderColor: Color(
          (json['borderColor'] as num?)?.toInt() ?? 0xFFD1D5DB,
        ),
        borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 1.2,
        cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 6.0,
        hasShadow: json['hasShadow'] as bool? ?? true,
        showHeaderBar: json['showHeaderBar'] as bool? ?? false,
      );

  @override
  Map<String, dynamic> toJson() => {
    'title': title,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    if (deltaJson != null) 'deltaJson': deltaJson,
    'paperPresetId': paperPresetId,
    'isLandscape': isLandscape,
    'customWidth': customWidth,
    'customHeight': customHeight,
    'themeId': themeId,
    'marginPreset': marginPreset,
    'backgroundColor': backgroundColor.toARGB32(),
    'borderColor': borderColor.toARGB32(),
    'borderWidth': borderWidth,
    'cornerRadius': cornerRadius,
    'hasShadow': hasShadow,
    'showHeaderBar': showHeaderBar,
  };

  @override
  DocumentPayload clone() => DocumentPayload(
    title: title,
    blocks: List<RichTextBlock>.from(blocks),
    deltaJson: deltaJson,
    paperPresetId: paperPresetId,
    isLandscape: isLandscape,
    customWidth: customWidth,
    customHeight: customHeight,
    themeId: themeId,
    marginPreset: marginPreset,
    backgroundColor: backgroundColor,
    borderColor: borderColor,
    borderWidth: borderWidth,
    cornerRadius: cornerRadius,
    hasShadow: hasShadow,
    showHeaderBar: showHeaderBar,
  );

  DocumentPayload copyWith({
    String? title,
    List<RichTextBlock>? blocks,
    String? deltaJson,
    String? paperPresetId,
    bool? isLandscape,
    double? customWidth,
    double? customHeight,
    String? themeId,
    double? marginPreset,
    Color? backgroundColor,
    Color? borderColor,
    double? borderWidth,
    double? cornerRadius,
    bool? hasShadow,
    bool? showHeaderBar,
  }) {
    return DocumentPayload(
      title: title ?? this.title,
      blocks: blocks ?? this.blocks,
      deltaJson: deltaJson ?? this.deltaJson,
      paperPresetId: paperPresetId ?? this.paperPresetId,
      isLandscape: isLandscape ?? this.isLandscape,
      customWidth: customWidth ?? this.customWidth,
      customHeight: customHeight ?? this.customHeight,
      themeId: themeId ?? this.themeId,
      marginPreset: marginPreset ?? this.marginPreset,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      hasShadow: hasShadow ?? this.hasShadow,
      showHeaderBar: showHeaderBar ?? this.showHeaderBar,
    );
  }
}

class EmbedPayload extends NodePayload {
  final String provider;
  final String url;
  final String? title;
  final String? description;
  final String? thumbnailUrl;

  EmbedPayload({
    this.provider = 'YouTube',
    this.url = '',
    this.title = '',
    this.description,
    this.thumbnailUrl,
  });

  factory EmbedPayload.fromJson(Map<String, dynamic> json) => EmbedPayload(
    provider: json['provider'] as String? ?? 'YouTube',
    url: json['url'] as String? ?? '',
    title: json['title'] as String?,
    description: json['description'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => {
    'provider': provider,
    'url': url,
    'title': title,
    'description': description,
    'thumbnailUrl': thumbnailUrl,
  };

  @override
  EmbedPayload clone() => EmbedPayload(
    provider: provider,
    url: url,
    title: title,
    description: description,
    thumbnailUrl: thumbnailUrl,
  );

  EmbedPayload copyWith({
    String? provider,
    String? url,
    String? title,
    String? description,
    String? thumbnailUrl,
  }) {
    return EmbedPayload(
      provider: provider ?? this.provider,
      url: url ?? this.url,
      title: title ?? this.title,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }
}

enum LinkPreviewStatus { idle, loading, ready, error }

class MermaidPayload extends NodePayload {
  final String source;
  final String diagramType;
  final MermaidTheme theme;
  final MermaidDirection? direction;
  final Map<String, dynamic> config;
  final MermaidRenderMode renderMode;
  final int sourceRevision;
  final MermaidConversionStatus conversionStatus;
  final List<String> nativeNodeIds;
  final List<String> nativeEdgeIds;
  final String? cachedSvg;
  final int? cachedSvgRevision;
  final String? cachedSvgConfigKey;
  final String? rendererVersion;
  final MermaidDiagnostic? lastError;

  MermaidPayload({
    this.source = 'flowchart TD\n  A[Start] --> B[End]',
    this.diagramType = 'unknown',
    this.theme = MermaidTheme.defaultTheme,
    this.direction,
    this.config = const {},
    this.renderMode = MermaidRenderMode.sourcePreview,
    this.sourceRevision = 0,
    this.conversionStatus = MermaidConversionStatus.notConverted,
    this.nativeNodeIds = const [],
    this.nativeEdgeIds = const [],
    this.cachedSvg,
    this.cachedSvgRevision,
    this.cachedSvgConfigKey,
    this.rendererVersion,
    this.lastError,
    super.hotspotTargetFrameId,
  });

  factory MermaidPayload.fromJson(Map<String, dynamic> json) {
    final rawConfig = json['config'];
    final cachedSvg = MermaidPayloadData.boundedSvg(
      json['cachedSvg'] as String?,
    );
    return MermaidPayload(
      source: json['source'] as String? ?? '',
      diagramType: json['diagramType'] as String? ?? 'unknown',
      theme: MermaidTheme.fromValue(json['theme']),
      direction: MermaidDirection.fromValue(json['direction']),
      config: rawConfig is Map
          ? MermaidRenderConfig.fromJson({'overrides': rawConfig}).overrides
          : const <String, dynamic>{},
      renderMode: MermaidRenderMode.values.firstWhere(
        (value) => value.name == json['renderMode'],
        orElse: () => MermaidRenderMode.sourcePreview,
      ),
      sourceRevision: (json['sourceRevision'] as num?)?.toInt() ?? 0,
      conversionStatus: MermaidConversionStatus.values.firstWhere(
        (value) => value.name == json['conversionStatus'],
        orElse: () => MermaidConversionStatus.notConverted,
      ),
      nativeNodeIds: _stringList(json['nativeNodeIds']),
      nativeEdgeIds: _stringList(json['nativeEdgeIds']),
      cachedSvg: cachedSvg,
      cachedSvgRevision: (json['cachedSvgRevision'] as num?)?.toInt(),
      cachedSvgConfigKey: MermaidPayloadData.boundedCacheKey(
        json['cachedSvgConfigKey'],
      ),
      rendererVersion: MermaidPayloadData.boundedRendererVersion(
        json['rendererVersion'],
      ),
      lastError: json['lastError'] is Map
          ? MermaidDiagnostic.fromJson(
              (json['lastError'] as Map).cast<String, dynamic>(),
            )
          : null,
      hotspotTargetFrameId: json['hotspotTargetFrameId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'source': source,
    'diagramType': diagramType,
    'theme': theme.value,
    'direction': direction?.value,
    'config': MermaidRenderConfig(
      theme: theme,
      direction: direction,
      overrides: config,
    ).toJson()['overrides'],
    'renderMode': renderMode.name,
    'sourceRevision': sourceRevision,
    'conversionStatus': conversionStatus.name,
    'nativeNodeIds': nativeNodeIds,
    'nativeEdgeIds': nativeEdgeIds,
    'cachedSvg': MermaidPayloadData.boundedSvg(cachedSvg),
    'cachedSvgRevision': cachedSvgRevision,
    'cachedSvgConfigKey': MermaidPayloadData.boundedCacheKey(
      cachedSvgConfigKey,
    ),
    'rendererVersion': MermaidPayloadData.boundedRendererVersion(
      rendererVersion,
    ),
    'lastError': lastError?.toJson(),
    'hotspotTargetFrameId': hotspotTargetFrameId,
  };

  @override
  MermaidPayload clone() => MermaidPayload(
    source: source,
    diagramType: diagramType,
    theme: theme,
    direction: direction,
    config: MermaidRenderConfig.fromJson({'overrides': config}).overrides,
    renderMode: renderMode,
    sourceRevision: sourceRevision,
    conversionStatus: conversionStatus,
    nativeNodeIds: List<String>.from(nativeNodeIds),
    nativeEdgeIds: List<String>.from(nativeEdgeIds),
    cachedSvg: cachedSvg,
    cachedSvgRevision: cachedSvgRevision,
    cachedSvgConfigKey: cachedSvgConfigKey,
    rendererVersion: rendererVersion,
    lastError: lastError,
    hotspotTargetFrameId: hotspotTargetFrameId,
  );

  MermaidPayload copyWith({
    String? source,
    String? diagramType,
    MermaidTheme? theme,
    Object? direction = _sentinel,
    Map<String, dynamic>? config,
    MermaidRenderMode? renderMode,
    int? sourceRevision,
    MermaidConversionStatus? conversionStatus,
    List<String>? nativeNodeIds,
    List<String>? nativeEdgeIds,
    Object? cachedSvg = _sentinel,
    Object? cachedSvgRevision = _sentinel,
    Object? cachedSvgConfigKey = _sentinel,
    Object? rendererVersion = _sentinel,
    Object? lastError = _sentinel,
    Object? hotspotTargetFrameId = _sentinel,
  }) {
    return MermaidPayload(
      source: source ?? this.source,
      diagramType: diagramType ?? this.diagramType,
      theme: theme ?? this.theme,
      direction: direction == _sentinel
          ? this.direction
          : direction as MermaidDirection?,
      config: config ?? this.config,
      renderMode: renderMode ?? this.renderMode,
      sourceRevision: sourceRevision ?? this.sourceRevision,
      conversionStatus: conversionStatus ?? this.conversionStatus,
      nativeNodeIds: nativeNodeIds ?? this.nativeNodeIds,
      nativeEdgeIds: nativeEdgeIds ?? this.nativeEdgeIds,
      cachedSvg: cachedSvg == _sentinel ? this.cachedSvg : cachedSvg as String?,
      cachedSvgRevision: cachedSvgRevision == _sentinel
          ? this.cachedSvgRevision
          : cachedSvgRevision as int?,
      cachedSvgConfigKey: cachedSvgConfigKey == _sentinel
          ? this.cachedSvgConfigKey
          : cachedSvgConfigKey as String?,
      rendererVersion: rendererVersion == _sentinel
          ? this.rendererVersion
          : rendererVersion as String?,
      lastError: lastError == _sentinel
          ? this.lastError
          : lastError as MermaidDiagnostic?,
      hotspotTargetFrameId: hotspotTargetFrameId == _sentinel
          ? this.hotspotTargetFrameId
          : hotspotTargetFrameId as String?,
    );
  }

  MermaidPayload updateSource(String nextSource) => copyWith(
    source: nextSource,
    diagramType: 'unknown',
    renderMode: MermaidRenderMode.sourcePreview,
    sourceRevision: sourceRevision + 1,
    conversionStatus: MermaidConversionStatus.notConverted,
    nativeNodeIds: const [],
    nativeEdgeIds: const [],
    cachedSvg: null,
    cachedSvgRevision: null,
    cachedSvgConfigKey: null,
    rendererVersion: null,
    lastError: null,
  );

  static const Object _sentinel = Object();

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .take(MermaidSourceLimits.maxGeneratedObjects)
        .toList();
  }
}

class LinkPayload extends NodePayload {
  final String title;
  final String url;
  final String? description;
  final String? faviconUrl;
  final String? imageUrl;
  final String? siteName;
  final DateTime? fetchedAt;
  final LinkPreviewStatus previewStatus;
  final String? previewError;
  final String? mediaType;

  LinkPayload({
    this.title = '',
    this.url = '',
    this.description,
    this.faviconUrl,
    this.imageUrl,
    this.siteName,
    this.fetchedAt,
    this.previewStatus = LinkPreviewStatus.idle,
    this.previewError,
    this.mediaType = 'webpage',
  });

  factory LinkPayload.fromJson(Map<String, dynamic> json) {
    final status = LinkPreviewStatus.values.firstWhere(
      (value) => value.name == json['previewStatus'],
      orElse: () => LinkPreviewStatus.idle,
    );
    return LinkPayload(
      title: json['title'] as String? ?? 'Resource Link',
      url: json['url'] as String? ?? 'https://example.com',
      description: json['description'] as String?,
      faviconUrl: json['faviconUrl'] as String?,
      imageUrl: json['imageUrl'] as String?,
      siteName: json['siteName'] as String?,
      fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? ''),
      previewStatus: status == LinkPreviewStatus.loading
          ? LinkPreviewStatus.idle
          : status,
      previewError: json['previewError'] as String?,
      mediaType: json['mediaType'] as String? ?? 'webpage',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'description': description,
    'faviconUrl': faviconUrl,
    'imageUrl': imageUrl,
    'siteName': siteName,
    'fetchedAt': fetchedAt?.toIso8601String(),
    'previewStatus': previewStatus.name,
    'previewError': previewError,
    'mediaType': mediaType,
  };

  LinkPayload copyWith({
    String? title,
    String? url,
    String? description,
    String? faviconUrl,
    String? imageUrl,
    String? siteName,
    DateTime? fetchedAt,
    LinkPreviewStatus? previewStatus,
    String? previewError,
    String? mediaType,
    bool clearDescription = false,
    bool clearFaviconUrl = false,
    bool clearImageUrl = false,
    bool clearSiteName = false,
    bool clearFetchedAt = false,
    bool clearPreviewError = false,
  }) => LinkPayload(
    title: title ?? this.title,
    url: url ?? this.url,
    description: clearDescription ? null : description ?? this.description,
    faviconUrl: clearFaviconUrl ? null : faviconUrl ?? this.faviconUrl,
    imageUrl: clearImageUrl ? null : imageUrl ?? this.imageUrl,
    siteName: clearSiteName ? null : siteName ?? this.siteName,
    fetchedAt: clearFetchedAt ? null : fetchedAt ?? this.fetchedAt,
    previewStatus: previewStatus ?? this.previewStatus,
    previewError: clearPreviewError ? null : previewError ?? this.previewError,
    mediaType: mediaType ?? this.mediaType,
  );

  LinkPayload clearPreview({required String url}) => copyWith(
    title: '',
    url: url,
    previewStatus: LinkPreviewStatus.idle,
    clearDescription: true,
    clearFaviconUrl: true,
    clearImageUrl: true,
    clearSiteName: true,
    clearFetchedAt: true,
    clearPreviewError: true,
    mediaType: 'webpage',
  );

  @override
  LinkPayload clone() => copyWith();
}

class VideoPayload extends NodePayload {
  final String title;
  final String durationText;

  /// Stable manifest identity for the attached video artifact.
  final String? assetId;

  /// Stable project-scoped Storage metadata for the video source.
  final String? storagePath;

  /// Stable project-scoped Storage metadata for an optional poster image.
  final String? posterStoragePath;

  /// Opaque owned image artifact reference for an optional poster image.
  final String? posterArtifactReference;
  final String? videoUrl;
  final String? videoPath;
  final String? videoArtifactReference;
  final String? caption;
  final bool isPlaying;
  final int? durationMs;
  final int? videoWidth;
  final int? videoHeight;
  final String? posterUrl;
  final String? posterPath;
  final String? sourceError;
  final bool isTemporary;
  final MediaTimeline? mediaTimeline;

  VideoPayload({
    this.title = 'Video Showcase',
    this.durationText = '03:45',
    this.assetId,
    this.storagePath,
    this.posterStoragePath,
    this.posterArtifactReference,
    this.videoUrl,
    this.videoPath,
    this.videoArtifactReference,
    this.caption,
    this.isPlaying = false,
    this.durationMs,
    this.videoWidth,
    this.videoHeight,
    this.posterUrl,
    this.posterPath,
    this.sourceError,
    this.isTemporary = false,
    this.mediaTimeline,
  });

  factory VideoPayload.fromJson(Map<String, dynamic> json) => VideoPayload(
    title: json['title'] as String? ?? 'Video Showcase',
    durationText: json['durationText'] as String? ?? '03:45',
    assetId: json['assetId'] as String?,
    storagePath: durableAssetReference(json['storagePath'] as String?),
    posterStoragePath: durableAssetReference(
      json['posterStoragePath'] as String?,
    ),
    posterArtifactReference: validImageArtifactReference(
      json['posterArtifactReference'] as String?,
    ),
    // Delivery URLs and local paths are runtime-only. A validated opaque
    // artifact reference remains the durable local fallback.
    videoUrl: null,
    videoPath: null,
    videoArtifactReference: validVideoArtifactReference(
      json['videoArtifactReference'] as String?,
    ),
    caption: json['caption'] as String?,
    isPlaying: false,
    durationMs: (json['durationMs'] as num?)?.toInt(),
    videoWidth: (json['videoWidth'] as num?)?.toInt(),
    videoHeight: (json['videoHeight'] as num?)?.toInt(),
    posterUrl: null,
    posterPath: null,
    sourceError: null,
    isTemporary: false,
    mediaTimeline: json['mediaTimeline'] is Map
        ? MediaTimeline.fromJson(
            Map<String, dynamic>.from(json['mediaTimeline'] as Map),
          )
        : null,
  );

  @override
  Map<String, dynamic> toJson() => {
    'title': title,
    'durationText': durationText,
    if (assetId != null) 'assetId': assetId,
    'storagePath': ?durableAssetReference(storagePath),
    'posterStoragePath': ?durableAssetReference(posterStoragePath),
    'posterArtifactReference': ?validImageArtifactReference(
      posterArtifactReference,
    ),
    'videoArtifactReference': ?validVideoArtifactReference(
      videoArtifactReference,
    ),
    'caption': caption,
    // Playback state, delivery URLs, local paths, and temporary flags are runtime-only.
    if (durationMs != null) 'durationMs': durationMs,
    'videoWidth': videoWidth,
    'videoHeight': videoHeight,
    'mediaTimeline': mediaTimeline?.toPersistenceJson(),
  };

  @override
  VideoPayload clone() => VideoPayload(
    title: title,
    durationText: durationText,
    assetId: assetId,
    storagePath: storagePath,
    videoUrl: videoUrl,
    videoPath: videoPath,
    videoArtifactReference: videoArtifactReference,
    caption: caption,
    isPlaying: isPlaying,
    durationMs: durationMs,
    videoWidth: videoWidth,
    videoHeight: videoHeight,
    posterStoragePath: posterStoragePath,
    posterArtifactReference: posterArtifactReference,
    posterUrl: posterUrl,
    posterPath: posterPath,
    sourceError: sourceError,
    isTemporary: isTemporary,
    mediaTimeline: mediaTimeline,
  );

  VideoPayload copyWith({
    String? title,
    String? durationText,
    String? assetId,
    Object? storagePath = _sentinel,
    Object? videoUrl = _sentinel,
    Object? videoPath = _sentinel,
    Object? videoArtifactReference = _sentinel,
    String? caption,
    bool? isPlaying,
    int? durationMs,
    int? videoWidth,
    int? videoHeight,
    Object? posterStoragePath = _sentinel,
    Object? posterArtifactReference = _sentinel,
    Object? posterUrl = _sentinel,
    String? posterPath,
    bool clearPosterPath = false,
    bool clearPosterUrl = false,
    String? sourceError,
    bool? isTemporary,
    Object? mediaTimeline = _sentinel,
  }) {
    return VideoPayload(
      title: title ?? this.title,
      durationText: durationText ?? this.durationText,
      assetId: assetId ?? this.assetId,
      storagePath: storagePath == _sentinel
          ? this.storagePath
          : durableAssetReference(storagePath as String?),
      videoUrl: videoUrl == _sentinel ? this.videoUrl : videoUrl as String?,
      videoPath: videoPath == _sentinel ? this.videoPath : videoPath as String?,
      videoArtifactReference: videoArtifactReference == _sentinel
          ? this.videoArtifactReference
          : videoArtifactReference as String?,
      caption: caption ?? this.caption,
      isPlaying: isPlaying ?? this.isPlaying,
      durationMs: durationMs ?? this.durationMs,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      posterStoragePath: posterStoragePath == _sentinel
          ? this.posterStoragePath
          : durableAssetReference(posterStoragePath as String?),
      posterArtifactReference: posterArtifactReference == _sentinel
          ? this.posterArtifactReference
          : validImageArtifactReference(posterArtifactReference as String?),
      posterUrl: clearPosterUrl
          ? null
          : (posterUrl == _sentinel ? this.posterUrl : posterUrl as String?),
      posterPath: clearPosterPath ? null : (posterPath ?? this.posterPath),
      sourceError: sourceError ?? this.sourceError,
      isTemporary: isTemporary ?? this.isTemporary,
      mediaTimeline: mediaTimeline == _sentinel
          ? this.mediaTimeline
          : mediaTimeline as MediaTimeline?,
    );
  }

  static const Object _sentinel = Object();
}

class AudioPayload extends NodePayload {
  final String trackName;
  final String artist;
  final String description;
  final String durationText;
  final int? durationSeconds;

  /// Stable manifest identity for the attached audio artifact.
  final String? assetId;

  /// Stable project-scoped Storage metadata for the audio source.
  final String? storagePath;

  /// Durable owned media artifact reference. Runtime paths and URLs remain
  /// transient and are populated only by the media resolver.
  final String? audioArtifactReference;
  final String? audioPath;
  final String? audioUrl;
  final bool isPlaying;
  final bool isLooping;
  final double playbackSpeed;
  final MediaTimeline? mediaTimeline;

  AudioPayload({
    this.trackName = 'Audio Voiceover / BGM',
    this.artist = '',
    this.description = '',
    this.durationText = '01:20',
    this.durationSeconds,
    this.assetId,
    this.storagePath,
    this.audioArtifactReference,
    this.audioPath,
    this.audioUrl,
    this.isPlaying = false,
    this.isLooping = false,
    this.playbackSpeed = 1.0,
    this.mediaTimeline,
  });

  static bool isRemoteSource(String source) {
    final value = source.trim().toLowerCase();
    return value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('blob:') ||
        value.startsWith('data:');
  }

  factory AudioPayload.fromJson(Map<String, dynamic> json) => AudioPayload(
    trackName: json['trackName'] as String? ?? 'Audio Voiceover / BGM',
    artist: json['artist'] as String? ?? '',
    description: json['description'] as String? ?? '',
    durationText: json['durationText'] as String? ?? '01:20',
    durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
    assetId: json['assetId'] as String?,
    storagePath: durableAssetReference(json['storagePath'] as String?),
    audioArtifactReference: validMediaArtifactReference(
      json['audioArtifactReference'] as String?,
    ),
    // Native paths and delivery URLs are runtime-only. They are rehydrated
    // from the stable Storage reference or local artifact manifest.
    audioPath: null,
    audioUrl: null,
    isPlaying: false,
    isLooping: false,
    playbackSpeed: 1.0,
    mediaTimeline: json['mediaTimeline'] is Map
        ? MediaTimeline.fromJson(
            Map<String, dynamic>.from(json['mediaTimeline'] as Map),
          )
        : null,
  );

  @override
  Map<String, dynamic> toJson() => {
    'trackName': trackName,
    'artist': artist,
    'description': description,
    'durationText': durationText,
    'durationSeconds': durationSeconds,
    if (assetId != null) 'assetId': assetId,
    'storagePath': ?durableAssetReference(storagePath),
    'audioArtifactReference': ?validMediaArtifactReference(
      audioArtifactReference,
    ),
    // Audio paths, playback state, and signed/runtime URLs are transient.
    'mediaTimeline': mediaTimeline?.toPersistenceJson(),
  };

  @override
  AudioPayload clone() => AudioPayload(
    trackName: trackName,
    artist: artist,
    description: description,
    durationText: durationText,
    durationSeconds: durationSeconds,
    assetId: assetId,
    storagePath: storagePath,
    audioArtifactReference: audioArtifactReference,
    audioPath: audioPath,
    audioUrl: audioUrl,
    isPlaying: isPlaying,
    isLooping: isLooping,
    playbackSpeed: playbackSpeed,
    mediaTimeline: mediaTimeline,
  );

  AudioPayload copyWith({
    String? trackName,
    String? artist,
    String? description,
    String? durationText,
    int? durationSeconds,
    String? assetId,
    Object? storagePath = _sentinel,
    Object? audioArtifactReference = _sentinel,
    Object? audioPath = _sentinel,
    Object? audioUrl = _sentinel,
    bool? isPlaying,
    bool? isLooping,
    double? playbackSpeed,
    Object? mediaTimeline = _sentinel,
  }) {
    return AudioPayload(
      trackName: trackName ?? this.trackName,
      durationText: durationText ?? this.durationText,
      artist: artist ?? this.artist,
      description: description ?? this.description,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      assetId: assetId ?? this.assetId,
      storagePath: storagePath == _sentinel
          ? this.storagePath
          : durableAssetReference(storagePath as String?),
      audioArtifactReference: audioArtifactReference == _sentinel
          ? this.audioArtifactReference
          : validMediaArtifactReference(audioArtifactReference as String?),
      audioPath: audioPath == _sentinel ? this.audioPath : audioPath as String?,
      audioUrl: audioUrl == _sentinel ? this.audioUrl : audioUrl as String?,
      isPlaying: isPlaying ?? this.isPlaying,
      isLooping: isLooping ?? this.isLooping,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      mediaTimeline: mediaTimeline == _sentinel
          ? this.mediaTimeline
          : mediaTimeline as MediaTimeline?,
    );
  }

  static const Object _sentinel = Object();
}

class MapPayload extends NodePayload {
  final String locationTitle;
  final String address;
  final double latitude;
  final double longitude;
  final double zoomLevel;

  MapPayload({
    this.locationTitle = 'Design Headquarters',
    this.address = 'Tokyo, Japan',
    double latitude = 35.6762,
    double longitude = 139.6503,
    double zoomLevel = 12.0,
  }) : latitude = isValidLatitude(latitude) ? latitude : 0.0,
       longitude = isValidLongitude(longitude) ? longitude : 0.0,
       zoomLevel = isValidZoom(zoomLevel) ? zoomLevel : 12.0;

  static bool isValidLatitude(double value) =>
      value.isFinite && value >= -90 && value <= 90;

  static bool isValidLongitude(double value) =>
      value.isFinite && value >= -180 && value <= 180;

  static bool isValidZoom(double value) =>
      value.isFinite && value >= 1 && value <= 19;

  factory MapPayload.fromJson(Map<String, dynamic> json) => MapPayload(
    locationTitle: json['locationTitle'] as String? ?? 'Location Pin',
    address: json['address'] as String? ?? '',
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
    zoomLevel: (json['zoomLevel'] as num?)?.toDouble() ?? 12.0,
  );

  @override
  Map<String, dynamic> toJson() => {
    'locationTitle': locationTitle,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'zoomLevel': zoomLevel,
  };

  @override
  MapPayload clone() => MapPayload(
    locationTitle: locationTitle,
    address: address,
    latitude: latitude,
    longitude: longitude,
    zoomLevel: zoomLevel,
  );
}

class ColorSwatchPayload extends NodePayload {
  final String label;
  final Color color;
  final String colorHex;

  ColorSwatchPayload({
    this.label = 'Brand Accent',
    this.color = const Color(0xFFF97316),
    this.colorHex = '#F97316',
  });

  factory ColorSwatchPayload.fromJson(Map<String, dynamic> json) =>
      ColorSwatchPayload(
        label: json['label'] as String? ?? 'Color Swatch',
        color: Color((json['color'] as num?)?.toInt() ?? 0xFFF97316),
        colorHex: json['colorHex'] as String? ?? '#F97316',
      );

  @override
  Map<String, dynamic> toJson() => {
    'label': label,
    'color': color.toARGB32(),
    'colorHex': colorHex,
  };

  @override
  ColorSwatchPayload clone() =>
      ColorSwatchPayload(label: label, color: color, colorHex: colorHex);
}

// -------------------------------------------------------------
// INFINITE BOARD - CREATIVE NODES
// -------------------------------------------------------------

class SketchCardPayload extends NodePayload {
  final String title;
  final List<List<Offset>> strokes;
  final Color strokeColor;
  final double strokeWidth;
  final Color backgroundColor;
  final String cardPattern; // 'none', 'grid', 'dots'
  final bool smoothCurves;

  SketchCardPayload({
    this.title = 'Quick Sketch',
    this.strokes = const [],
    this.strokeColor = const Color(0xFFF59E0B),
    this.strokeWidth = 2.5,
    this.backgroundColor = const Color(0xFF1E2028),
    this.cardPattern = 'dots',
    this.smoothCurves = true,
  });

  factory SketchCardPayload.fromJson(Map<String, dynamic> json) {
    List<List<Offset>> parsedStrokes = [];
    if (json['strokes'] is List) {
      final rawList = json['strokes'] as List<dynamic>;
      if (rawList.isNotEmpty) {
        if (rawList.first is List) {
          // Format baru: List<List<Offset>>
          parsedStrokes = rawList.map((stroke) {
            return (stroke as List<dynamic>).map((pt) {
              return Offset(
                (pt['x'] as num).toDouble(),
                (pt['y'] as num).toDouble(),
              );
            }).toList();
          }).toList();
        } else if (rawList.first is Map) {
          // Backward compatibility: List<Offset>
          final singleStroke = rawList.map((pt) {
            return Offset(
              (pt['x'] as num).toDouble(),
              (pt['y'] as num).toDouble(),
            );
          }).toList();
          parsedStrokes = [singleStroke];
        }
      }
    }

    return SketchCardPayload(
      title: json['title'] as String? ?? 'Quick Sketch',
      strokes: parsedStrokes,
      strokeColor: json['strokeColor'] != null
          ? Color(json['strokeColor'] as int)
          : const Color(0xFFF59E0B),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.5,
      backgroundColor: json['backgroundColor'] != null
          ? Color(json['backgroundColor'] as int)
          : const Color(0xFF1E2028),
      cardPattern: json['cardPattern'] as String? ?? 'dots',
      smoothCurves: json['smoothCurves'] as bool? ?? true,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'title': title,
    'strokes': strokes
        .map((stroke) => stroke.map((p) => {'x': p.dx, 'y': p.dy}).toList())
        .toList(),
    'strokeColor': strokeColor.toARGB32(),
    'strokeWidth': strokeWidth,
    'backgroundColor': backgroundColor.toARGB32(),
    'cardPattern': cardPattern,
    'smoothCurves': smoothCurves,
  };

  @override
  SketchCardPayload clone() => SketchCardPayload(
    title: title,
    strokes: strokes.map((s) => List<Offset>.from(s)).toList(),
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
    backgroundColor: backgroundColor,
    cardPattern: cardPattern,
    smoothCurves: smoothCurves,
  );

  SketchCardPayload copyWith({
    String? title,
    List<List<Offset>>? strokes,
    Color? strokeColor,
    double? strokeWidth,
    Color? backgroundColor,
    String? cardPattern,
    bool? smoothCurves,
  }) {
    return SketchCardPayload(
      title: title ?? this.title,
      strokes: strokes ?? this.strokes,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      cardPattern: cardPattern ?? this.cardPattern,
      smoothCurves: smoothCurves ?? this.smoothCurves,
    );
  }
}

enum AnnotationPinStatus { open, inProgress, resolved, issue }

class ImageAnnotationPin {
  final String id;
  final Offset position;
  final String text;
  final String author;
  final DateTime? createdAt;
  final AnnotationPinStatus status;
  final Color color;
  final bool isResolved;

  ImageAnnotationPin({
    required this.id,
    required this.position,
    required this.text,
    this.author = 'Anonymous',
    this.createdAt,
    this.status = AnnotationPinStatus.open,
    this.color = const Color(0xFFEC4899),
    this.isResolved = false,
  });

  ImageAnnotationPin copyWith({
    String? id,
    Offset? position,
    String? text,
    String? author,
    DateTime? createdAt,
    AnnotationPinStatus? status,
    Color? color,
    bool? isResolved,
  }) {
    return ImageAnnotationPin(
      id: id ?? this.id,
      position: position ?? this.position,
      text: text ?? this.text,
      author: author ?? this.author,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      color: color ?? this.color,
      isResolved: isResolved ?? this.isResolved,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': position.dx,
    'y': position.dy,
    'text': text,
    'author': author,
    'createdAt': createdAt?.toIso8601String(),
    'status': status.name,
    'color': color.toARGB32(),
    'isResolved': isResolved,
  };

  factory ImageAnnotationPin.fromJson(Map<String, dynamic> json) =>
      ImageAnnotationPin(
        id: json['id'] as String? ?? '',
        position: Offset(
          (json['x'] as num?)?.toDouble() ?? 0.0,
          (json['y'] as num?)?.toDouble() ?? 0.0,
        ),
        text: json['text'] as String? ?? '',
        author: json['author'] as String? ?? 'Anonymous',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        status: AnnotationPinStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => AnnotationPinStatus.open,
        ),
        color: Color((json['color'] as num?)?.toInt() ?? 0xFFEC4899),
        isResolved: json['isResolved'] as bool? ?? false,
      );
}

class AnnotatedImagePayload extends NodePayload {
  /// Stable manifest identity for the attached image artifact.
  final String? assetId;

  /// Stable opaque image artifact identity. Runtime paths stay transient.
  final String? imageArtifactReference;
  final String? imagePath;
  final List<ImageAnnotationPin> pins;
  final bool showCornerBadge;
  final bool showLeaderLines;

  AnnotatedImagePayload({
    this.assetId,
    this.imageArtifactReference,
    this.imagePath,
    this.pins = const [],
    this.showCornerBadge = true,
    this.showLeaderLines = true,
  });

  AnnotatedImagePayload copyWith({
    String? assetId,
    String? imageArtifactReference,
    String? imagePath,
    List<ImageAnnotationPin>? pins,
    bool? showCornerBadge,
    bool? showLeaderLines,
  }) {
    return AnnotatedImagePayload(
      assetId: assetId ?? this.assetId,
      imageArtifactReference:
          imageArtifactReference ?? this.imageArtifactReference,
      imagePath: imagePath ?? this.imagePath,
      pins: pins ?? this.pins,
      showCornerBadge: showCornerBadge ?? this.showCornerBadge,
      showLeaderLines: showLeaderLines ?? this.showLeaderLines,
    );
  }

  factory AnnotatedImagePayload.fromJson(Map<String, dynamic> json) =>
      AnnotatedImagePayload(
        assetId: json['assetId'] as String?,
        imageArtifactReference: validImageArtifactReference(
          json['imageArtifactReference'] as String?,
        ),
        // Compatibility JSON may carry the legacy runtime path. The durable
        // projection below intentionally excludes it.
        imagePath: json['imagePath'] as String?,
        pins:
            (json['pins'] as List<dynamic>?)
                ?.map(
                  (e) => ImageAnnotationPin.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            const [],
        showCornerBadge: json['showCornerBadge'] as bool? ?? true,
        showLeaderLines: json['showLeaderLines'] as bool? ?? true,
      );

  @override
  Map<String, dynamic> toJson() => {
    if (assetId != null) 'assetId': assetId,
    'imageArtifactReference': ?validImageArtifactReference(
      imageArtifactReference,
    ),
    'imagePath': imagePath,
    'pins': pins.map((p) => p.toJson()).toList(),
    'showCornerBadge': showCornerBadge,
    'showLeaderLines': showLeaderLines,
  };

  @override
  Map<String, dynamic> toPersistenceJson() => {
    if (assetId != null) 'assetId': assetId,
    'imageArtifactReference': ?validImageArtifactReference(
      imageArtifactReference,
    ),
    'pins': pins.map((p) => p.toJson()).toList(),
    'showCornerBadge': showCornerBadge,
    'showLeaderLines': showLeaderLines,
  };

  @override
  AnnotatedImagePayload clone() => AnnotatedImagePayload(
    assetId: assetId,
    imageArtifactReference: imageArtifactReference,
    imagePath: imagePath,
    pins: List<ImageAnnotationPin>.from(pins),
    showCornerBadge: showCornerBadge,
    showLeaderLines: showLeaderLines,
  );
}

// -------------------------------------------------------------
// INFINITE BOARD - ORGANIZATION NODES
// -------------------------------------------------------------

enum ColumnCardPriority { none, low, medium, high }

class ColumnCardItem {
  final String id;
  final String title;
  final String description;
  final bool isDone;
  final ColumnCardPriority priority;
  final List<String> tags;
  final String? dueDate;
  final String? assignee;
  final Color? cardColor;

  const ColumnCardItem({
    required this.id,
    required this.title,
    this.description = '',
    this.isDone = false,
    this.priority = ColumnCardPriority.none,
    this.tags = const [],
    this.dueDate,
    this.assignee,
    this.cardColor,
  });

  factory ColumnCardItem.fromJson(Map<String, dynamic> json) => ColumnCardItem(
    id: json['id'] as String? ?? UniqueKey().toString(),
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    isDone: json['isDone'] as bool? ?? false,
    priority: ColumnCardPriority.values.firstWhere(
      (e) => e.name == json['priority'],
      orElse: () => ColumnCardPriority.none,
    ),
    tags:
        (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
        const [],
    dueDate: json['dueDate'] as String?,
    assignee: json['assignee'] as String?,
    cardColor: json['cardColor'] != null
        ? Color((json['cardColor'] as num).toInt())
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'isDone': isDone,
    'priority': priority.name,
    'tags': tags,
    'dueDate': dueDate,
    'assignee': assignee,
    'cardColor': cardColor?.toARGB32(),
  };

  ColumnCardItem copyWith({
    String? id,
    String? title,
    String? description,
    bool? isDone,
    ColumnCardPriority? priority,
    List<String>? tags,
    String? dueDate,
    String? assignee,
    Color? cardColor,
  }) {
    return ColumnCardItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isDone: isDone ?? this.isDone,
      priority: priority ?? this.priority,
      tags: tags ?? this.tags,
      dueDate: dueDate ?? this.dueDate,
      assignee: assignee ?? this.assignee,
      cardColor: cardColor ?? this.cardColor,
    );
  }
}

class ColumnPayload extends NodePayload {
  final String headerTitle;
  final Color headerColor;
  final List<ColumnCardItem> cards;
  final int wipLimit; // 0 = unlimited
  final bool isCollapsed;
  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;
  final double cornerRadius;
  final bool hasShadow;
  final bool showProgressBar;
  final String filterMode; // 'all', 'active', 'done'

  // Compatibility getter for legacy callers
  List<String> get itemTitles => cards.map((c) => c.title).toList();

  ColumnPayload({
    this.headerTitle = 'In Progress',
    this.headerColor = const Color(0xFF3B82F6),
    List<ColumnCardItem>? cards,
    List<String>? itemTitles,
    this.wipLimit = 0,
    this.isCollapsed = false,
    this.backgroundColor = const Color(0xFF1A1C22),
    this.borderColor = const Color(0xFF32353E),
    this.borderWidth = 1.2,
    this.cornerRadius = 6.0,
    this.hasShadow = true,
    this.showProgressBar = false,
    this.filterMode = 'all',
  }) : cards =
           cards ??
           (itemTitles != null
               ? itemTitles
                     .asMap()
                     .entries
                     .map(
                       (e) => ColumnCardItem(
                         id: 'card_${e.key}_${e.value.hashCode}',
                         title: e.value,
                       ),
                     )
                     .toList()
               : const [
                   ColumnCardItem(
                     id: 'c1',
                     title: 'Review UI spec',
                     priority: ColumnCardPriority.high,
                     tags: ['UI/UX'],
                   ),
                   ColumnCardItem(
                     id: 'c2',
                     title: 'Build wireframe',
                     priority: ColumnCardPriority.medium,
                     tags: ['Dev'],
                   ),
                   ColumnCardItem(
                     id: 'c3',
                     title: 'Export assets',
                     priority: ColumnCardPriority.low,
                     isDone: true,
                   ),
                 ]);

  factory ColumnPayload.fromJson(Map<String, dynamic> json) {
    List<ColumnCardItem> parsedCards = [];
    if (json['cards'] != null) {
      parsedCards = (json['cards'] as List<dynamic>)
          .map(
            (e) => ColumnCardItem.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } else if (json['itemTitles'] != null) {
      parsedCards = (json['itemTitles'] as List<dynamic>)
          .asMap()
          .entries
          .map(
            (e) =>
                ColumnCardItem(id: 'card_${e.key}', title: e.value.toString()),
          )
          .toList();
    }

    return ColumnPayload(
      headerTitle: json['headerTitle'] as String? ?? 'Column',
      headerColor: Color((json['headerColor'] as num?)?.toInt() ?? 0xFF3B82F6),
      cards: parsedCards,
      wipLimit: (json['wipLimit'] as num?)?.toInt() ?? 0,
      isCollapsed: json['isCollapsed'] as bool? ?? false,
      backgroundColor: Color(
        (json['backgroundColor'] as num?)?.toInt() ?? 0xFF1A1C22,
      ),
      borderColor: Color((json['borderColor'] as num?)?.toInt() ?? 0xFF32353E),
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 1.2,
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 6.0,
      hasShadow: json['hasShadow'] as bool? ?? true,
      showProgressBar: json['showProgressBar'] as bool? ?? false,
      filterMode: json['filterMode'] as String? ?? 'all',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'headerTitle': headerTitle,
    'headerColor': headerColor.toARGB32(),
    'cards': cards.map((c) => c.toJson()).toList(),
    'itemTitles': itemTitles,
    'wipLimit': wipLimit,
    'isCollapsed': isCollapsed,
    'backgroundColor': backgroundColor.toARGB32(),
    'borderColor': borderColor.toARGB32(),
    'borderWidth': borderWidth,
    'cornerRadius': cornerRadius,
    'hasShadow': hasShadow,
    'showProgressBar': showProgressBar,
    'filterMode': filterMode,
  };

  @override
  ColumnPayload clone() => ColumnPayload(
    headerTitle: headerTitle,
    headerColor: headerColor,
    cards: cards.map((c) => c.copyWith()).toList(),
    wipLimit: wipLimit,
    isCollapsed: isCollapsed,
    backgroundColor: backgroundColor,
    borderColor: borderColor,
    borderWidth: borderWidth,
    cornerRadius: cornerRadius,
    hasShadow: hasShadow,
    showProgressBar: showProgressBar,
    filterMode: filterMode,
  );

  ColumnPayload copyWith({
    String? headerTitle,
    Color? headerColor,
    List<ColumnCardItem>? cards,
    int? wipLimit,
    bool? isCollapsed,
    Color? backgroundColor,
    Color? borderColor,
    double? borderWidth,
    double? cornerRadius,
    bool? hasShadow,
    bool? showProgressBar,
    String? filterMode,
  }) {
    return ColumnPayload(
      headerTitle: headerTitle ?? this.headerTitle,
      headerColor: headerColor ?? this.headerColor,
      cards: cards ?? this.cards,
      wipLimit: wipLimit ?? this.wipLimit,
      isCollapsed: isCollapsed ?? this.isCollapsed,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      hasShadow: hasShadow ?? this.hasShadow,
      showProgressBar: showProgressBar ?? this.showProgressBar,
      filterMode: filterMode ?? this.filterMode,
    );
  }
}

class NestedBoardPayload extends NodePayload {
  final String boardName;
  final String description;
  final String subCanvasId;
  final int childNodeCount;
  final List<CanvasNode> subNodes;
  final List<CanvasEdge> subEdges;
  final List<String> tags;
  final Color backgroundColor;
  final Color borderColor;
  final Color accentColor;
  final double borderWidth;
  final double cornerRadius;
  final bool hasShadow;
  final bool showGridPreview;
  final String iconEmoji;

  NestedBoardPayload({
    this.boardName = 'Sub-Project Moodboard',
    this.description = '',
    this.subCanvasId = '',
    int? childNodeCount,
    this.subNodes = const [],
    this.subEdges = const [],
    this.tags = const [],
    this.backgroundColor = const Color(0xFF1E1B4B),
    this.borderColor = const Color(0xFF818CF8),
    this.accentColor = const Color(0xFFA5B4FC),
    this.borderWidth = 1.5,
    this.cornerRadius = 8.0,
    this.hasShadow = true,
    this.showGridPreview = true,
    this.iconEmoji = '🗂',
  }) : childNodeCount = childNodeCount ?? subNodes.length;

  factory NestedBoardPayload.fromJson(Map<String, dynamic> json) {
    final rawSubNodes = json['subNodes'] as List<dynamic>?;
    final parsedNodes = rawSubNodes != null
        ? rawSubNodes
              .map((e) => CanvasNode.fromJson(e as Map<String, dynamic>))
              .toList()
        : <CanvasNode>[];

    final rawSubEdges = json['subEdges'] as List<dynamic>?;
    final parsedEdges = rawSubEdges != null
        ? rawSubEdges
              .map((e) => CanvasEdge.fromJson(e as Map<String, dynamic>))
              .toList()
        : <CanvasEdge>[];

    final rawTags = json['tags'] as List<dynamic>?;
    final parsedTags = rawTags != null
        ? rawTags.map((e) => e.toString()).toList()
        : <String>[];

    final count =
        (json['childNodeCount'] as num?)?.toInt() ?? parsedNodes.length;

    return NestedBoardPayload(
      boardName: json['boardName'] as String? ?? 'Nested Board',
      description: json['description'] as String? ?? '',
      subCanvasId: json['subCanvasId'] as String? ?? '',
      childNodeCount: count,
      subNodes: parsedNodes,
      subEdges: parsedEdges,
      tags: parsedTags,
      backgroundColor: json['backgroundColor'] != null
          ? Color(json['backgroundColor'] as int)
          : const Color(0xFF1E1B4B),
      borderColor: json['borderColor'] != null
          ? Color(json['borderColor'] as int)
          : const Color(0xFF818CF8),
      accentColor: json['accentColor'] != null
          ? Color(json['accentColor'] as int)
          : const Color(0xFFA5B4FC),
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 1.5,
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 8.0,
      hasShadow: json['hasShadow'] as bool? ?? true,
      showGridPreview: json['showGridPreview'] as bool? ?? true,
      iconEmoji: json['iconEmoji'] as String? ?? '🗂',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'boardName': boardName,
    'description': description,
    'subCanvasId': subCanvasId,
    'childNodeCount': subNodes.isNotEmpty ? subNodes.length : childNodeCount,
    'subNodes': subNodes.map((e) => e.toJson()).toList(),
    'subEdges': subEdges.map((e) => e.toJson()).toList(),
    'tags': tags,
    'backgroundColor': backgroundColor.toARGB32(),
    'borderColor': borderColor.toARGB32(),
    'accentColor': accentColor.toARGB32(),
    'borderWidth': borderWidth,
    'cornerRadius': cornerRadius,
    'hasShadow': hasShadow,
    'showGridPreview': showGridPreview,
    'iconEmoji': iconEmoji,
  };

  @override
  Map<String, dynamic> toPersistenceJson() => {
    'boardName': boardName,
    'description': description,
    'subCanvasId': subCanvasId,
    'childNodeCount': subNodes.isNotEmpty ? subNodes.length : childNodeCount,
    'subNodes': subNodes
        .map((node) => node.toPersistenceJson())
        .toList(growable: false),
    'subEdges': subEdges.map((edge) => edge.toJson()).toList(growable: false),
    'tags': tags,
    'backgroundColor': backgroundColor.toARGB32(),
    'borderColor': borderColor.toARGB32(),
    'accentColor': accentColor.toARGB32(),
    'borderWidth': borderWidth,
    'cornerRadius': cornerRadius,
    'hasShadow': hasShadow,
    'showGridPreview': showGridPreview,
    'iconEmoji': iconEmoji,
  };

  @override
  NestedBoardPayload clone() => NestedBoardPayload(
    boardName: boardName,
    description: description,
    subCanvasId: subCanvasId,
    childNodeCount: childNodeCount,
    subNodes: subNodes
        .map((n) => n.copyWith(payload: n.payload.clone()))
        .toList(),
    subEdges: subEdges.map((e) => e.copyWith()).toList(),
    tags: List<String>.from(tags),
    backgroundColor: backgroundColor,
    borderColor: borderColor,
    accentColor: accentColor,
    borderWidth: borderWidth,
    cornerRadius: cornerRadius,
    hasShadow: hasShadow,
    showGridPreview: showGridPreview,
    iconEmoji: iconEmoji,
  );

  NestedBoardPayload copyWith({
    String? boardName,
    String? description,
    String? subCanvasId,
    int? childNodeCount,
    List<CanvasNode>? subNodes,
    List<CanvasEdge>? subEdges,
    List<String>? tags,
    Color? backgroundColor,
    Color? borderColor,
    Color? accentColor,
    double? borderWidth,
    double? cornerRadius,
    bool? hasShadow,
    bool? showGridPreview,
    String? iconEmoji,
  }) {
    final newSubNodes = subNodes ?? this.subNodes;
    return NestedBoardPayload(
      boardName: boardName ?? this.boardName,
      description: description ?? this.description,
      subCanvasId: subCanvasId ?? this.subCanvasId,
      childNodeCount:
          childNodeCount ??
          (subNodes != null ? newSubNodes.length : this.childNodeCount),
      subNodes: newSubNodes,
      subEdges: subEdges ?? this.subEdges,
      tags: tags ?? this.tags,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      borderColor: borderColor ?? this.borderColor,
      accentColor: accentColor ?? this.accentColor,
      borderWidth: borderWidth ?? this.borderWidth,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      hasShadow: hasShadow ?? this.hasShadow,
      showGridPreview: showGridPreview ?? this.showGridPreview,
      iconEmoji: iconEmoji ?? this.iconEmoji,
    );
  }
}

const _maxChartSeries = 12;
const _maxChartValues = 100;
const _maxChartPoints = 200;
const _maxChartLabelLength = 120;

enum ChartType { line, bar, pie, doughnut, scatter, radar }

enum ChartBarOrientation { vertical, horizontal }

class ChartPoint {
  final double x;
  final double y;
  final String? label;

  ChartPoint({required double x, required double y, String? label})
    : x = _finiteChartNumber(x),
      y = _finiteChartNumber(y),
      label = _optionalChartText(label, maxLength: _maxChartLabelLength);

  factory ChartPoint.fromJson(Map<String, dynamic> json) => ChartPoint(
    x: _finiteChartNumber(json['x']),
    y: _finiteChartNumber(json['y']),
    label: json['label'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    if (label != null) 'label': label,
  };

  ChartPoint clone() => ChartPoint(x: x, y: y, label: label);
}

class ChartSeries {
  final String name;
  final List<double> values;
  final List<ChartPoint> points;
  final Color color;

  ChartSeries({
    String name = 'Series',
    List<double> values = const [],
    List<ChartPoint> points = const [],
    this.color = const Color(0xFFF97316),
  }) : name = _chartText(name, maxLength: 80, fallback: 'Series'),
       values = _boundedChartValues(values),
       points = _boundedChartPoints(points);

  factory ChartSeries.fromJson(Map<String, dynamic> json) {
    final rawValues = json['values'];
    final values = rawValues is List
        ? rawValues.map<double>(_finiteChartNumber).toList()
        : const <double>[];
    final rawPoints = json['points'];
    final points = rawPoints is List
        ? rawPoints
              .whereType<Map>()
              .map(
                (point) =>
                    ChartPoint.fromJson(Map<String, dynamic>.from(point)),
              )
              .toList()
        : const <ChartPoint>[];
    return ChartSeries(
      name: json['name'] as String? ?? 'Series',
      values: values,
      points: points,
      color: _chartColor(json['color'], const Color(0xFFF97316)),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'values': values,
    'points': points.map((point) => point.toJson()).toList(),
    'color': color.toARGB32(),
  };

  ChartSeries clone() => ChartSeries(
    name: name,
    values: List<double>.from(values),
    points: points.map((point) => point.clone()).toList(),
    color: color,
  );

  ChartSeries copyWith({
    String? name,
    List<double>? values,
    List<ChartPoint>? points,
    Color? color,
  }) => ChartSeries(
    name: name ?? this.name,
    values: values ?? this.values,
    points: points ?? this.points,
    color: color ?? this.color,
  );
}

class ChartPayload extends NodePayload {
  final String title;
  final ChartType chartType;
  final List<String> categories;
  final List<ChartSeries> series;
  final List<Color> colors;
  final ChartBarOrientation barOrientation;
  final bool showLegend;
  final bool showGrid;
  final bool showAxes;
  final bool showValues;
  final bool lineCurved;
  final bool showDots;
  final bool showTooltips;
  final double doughnutHoleRatio;
  final double? minY;
  final double? maxY;
  final String categoryFilter;
  final String? tableSourceNodeId;
  final int tableCategoryColumn;
  final List<int> tableValueColumns;
  final String? dataSourceUrl;
  final String? databaseTableName;
  final String databaseCategoryColumn;
  final List<String> databaseValueColumns;
  final int databaseRowLimit;
  final int dataRefreshRevision;

  ChartPayload({
    String title = 'Chart',
    this.chartType = ChartType.line,
    List<String> categories = const ['A', 'B', 'C', 'D'],
    List<ChartSeries>? series,
    List<Color> colors = const [
      Color(0xFFF97316),
      Color(0xFF38BDF8),
      Color(0xFF10B981),
      Color(0xFFA78BFA),
      Color(0xFFF43F5E),
      Color(0xFFEAB308),
    ],
    this.barOrientation = ChartBarOrientation.vertical,
    this.showLegend = true,
    this.showGrid = true,
    this.showAxes = true,
    this.showValues = false,
    this.lineCurved = true,
    this.showDots = true,
    this.showTooltips = true,
    double doughnutHoleRatio = 0.58,
    double? minY,
    double? maxY,
    String categoryFilter = '',
    String? tableSourceNodeId,
    int tableCategoryColumn = 0,
    List<int> tableValueColumns = const [],
    String? dataSourceUrl,
    String? databaseTableName,
    String databaseCategoryColumn = 'category',
    List<String> databaseValueColumns = const [],
    int databaseRowLimit = 100,
    int dataRefreshRevision = 0,
  }) : title = _chartText(title, maxLength: 160, fallback: 'Chart'),
       categoryFilter =
           _optionalChartText(
             categoryFilter,
             maxLength: _maxChartLabelLength,
           ) ??
           '',
       tableSourceNodeId = _optionalChartText(
         tableSourceNodeId,
         maxLength: 200,
       ),
       tableCategoryColumn = tableCategoryColumn < 0 ? 0 : tableCategoryColumn,
       tableValueColumns = _boundedTableColumnIndexes(tableValueColumns),
       dataSourceUrl = _optionalChartText(dataSourceUrl, maxLength: 2048),
       databaseTableName = _optionalChartIdentifier(databaseTableName),
       databaseCategoryColumn = _chartIdentifier(
         databaseCategoryColumn,
         fallback: 'category',
       ),
       databaseValueColumns = _boundedChartIdentifiers(databaseValueColumns),
       databaseRowLimit = databaseRowLimit.clamp(1, _maxChartValues).toInt(),
       dataRefreshRevision = dataRefreshRevision < 0 ? 0 : dataRefreshRevision,
       categories = _boundedChartLabels(categories),
       series = _boundedChartSeries(
         series ??
             [
               ChartSeries(name: 'Series', values: [4, 7, 5, 9]),
             ],
       ),
       colors = _boundedChartColors(colors),
       doughnutHoleRatio = doughnutHoleRatio.clamp(0.0, 0.9),
       minY = _optionalFiniteChartNumber(minY),
       maxY = _optionalFiniteChartNumber(maxY);

  factory ChartPayload.fromJson(Map<String, dynamic> json) {
    final rawSeries = json['series'];
    final series = rawSeries is List
        ? rawSeries
              .whereType<Map>()
              .map(
                (item) => ChartSeries.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : null;
    final rawColors = json['colors'];
    final colors = rawColors is List
        ? rawColors
              .map((color) => _chartColor(color, const Color(0xFFF97316)))
              .toList()
        : const <Color>[];

    return ChartPayload(
      title: json['title'] as String? ?? 'Chart',
      chartType: ChartType.values.firstWhere(
        (type) => type.name == json['chartType'],
        orElse: () => ChartType.line,
      ),
      categories: _jsonChartLabels(json['categories']),
      series: series,
      colors: colors.isEmpty
          ? const [
              Color(0xFFF97316),
              Color(0xFF38BDF8),
              Color(0xFF10B981),
              Color(0xFFA78BFA),
              Color(0xFFF43F5E),
              Color(0xFFEAB308),
            ]
          : colors,
      barOrientation: ChartBarOrientation.values.firstWhere(
        (orientation) => orientation.name == json['barOrientation'],
        orElse: () => ChartBarOrientation.vertical,
      ),
      showLegend: json['showLegend'] as bool? ?? true,
      showGrid: json['showGrid'] as bool? ?? true,
      showAxes: json['showAxes'] as bool? ?? true,
      showValues: json['showValues'] as bool? ?? false,
      lineCurved: json['lineCurved'] as bool? ?? true,
      showDots: json['showDots'] as bool? ?? true,
      showTooltips: json['showTooltips'] as bool? ?? true,
      doughnutHoleRatio: _finiteChartNumber(
        json['doughnutHoleRatio'],
        fallback: 0.58,
      ),
      minY: _optionalFiniteChartNumber(json['minY']),
      maxY: _optionalFiniteChartNumber(json['maxY']),
      categoryFilter: json['categoryFilter'] as String? ?? '',
      tableSourceNodeId: _optionalChartText(
        json['tableSourceNodeId'] is String
            ? json['tableSourceNodeId'] as String
            : null,
        maxLength: 200,
      ),
      tableCategoryColumn: (json['tableCategoryColumn'] as num?)?.toInt() ?? 0,
      tableValueColumns:
          (json['tableValueColumns'] as List<dynamic>?)
              ?.whereType<num>()
              .map((value) => value.toInt())
              .toList() ??
          const [],
      dataSourceUrl: _optionalChartText(
        json['dataSourceUrl'] is String
            ? json['dataSourceUrl'] as String
            : null,
        maxLength: 2048,
      ),
      databaseTableName: _optionalChartIdentifier(
        json['databaseTableName'] is String
            ? json['databaseTableName'] as String
            : null,
      ),
      databaseCategoryColumn:
          json['databaseCategoryColumn'] as String? ?? 'category',
      databaseValueColumns:
          (json['databaseValueColumns'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      databaseRowLimit: (json['databaseRowLimit'] as num?)?.toInt() ?? 100,
      dataRefreshRevision: (json['dataRefreshRevision'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'title': title,
    'chartType': chartType.name,
    'categories': categories,
    'series': series.map((item) => item.toJson()).toList(),
    'colors': colors.map((color) => color.toARGB32()).toList(),
    'barOrientation': barOrientation.name,
    'showLegend': showLegend,
    'showGrid': showGrid,
    'showAxes': showAxes,
    'showValues': showValues,
    'lineCurved': lineCurved,
    'showDots': showDots,
    'showTooltips': showTooltips,
    'doughnutHoleRatio': doughnutHoleRatio,
    'minY': minY,
    'maxY': maxY,
    'categoryFilter': categoryFilter,
    if (tableSourceNodeId != null) 'tableSourceNodeId': tableSourceNodeId,
    'tableCategoryColumn': tableCategoryColumn,
    'tableValueColumns': tableValueColumns,
    if (dataSourceUrl != null) 'dataSourceUrl': dataSourceUrl,
    if (databaseTableName != null) 'databaseTableName': databaseTableName,
    'databaseCategoryColumn': databaseCategoryColumn,
    'databaseValueColumns': databaseValueColumns,
    'databaseRowLimit': databaseRowLimit,
    'dataRefreshRevision': dataRefreshRevision,
  };

  ChartPayload resolvedFromTable(TablePayload table) {
    final categoryIndex = tableCategoryColumn < table.columns.length
        ? tableCategoryColumn
        : 0;
    final candidateColumns = tableValueColumns.isEmpty
        ? [
            for (var index = 0; index < table.columns.length; index++)
              if (index != categoryIndex) index,
          ]
        : tableValueColumns.where(
            (index) => index < table.columns.length && index != categoryIndex,
          );
    final valueColumns = [
      for (final index in candidateColumns)
        if (table.rows.any(
          (row) => _tableNumericValue(table, row, index) != null,
        ))
          index,
    ];
    if (valueColumns.isEmpty || table.rows.isEmpty) return this;

    final categories = [
      for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++)
        rowIndex < table.rows.length &&
                categoryIndex < table.rows[rowIndex].length
            ? table.rows[rowIndex][categoryIndex]
            : 'Category ${rowIndex + 1}',
    ];
    final nextSeries = [
      for (final columnIndex in valueColumns)
        ChartSeries(
          name: columnIndex < table.columns.length
              ? table.columns[columnIndex]
              : 'Series ${columnIndex + 1}',
          values: [
            for (final row in table.rows)
              _tableNumericValue(table, row, columnIndex) ?? 0,
          ],
          color: colors[columnIndex % colors.length],
        ),
    ];
    return copyWith(categories: categories, series: nextSeries);
  }

  ChartPayload filteredByCategory() {
    final query = categoryFilter.trim().toLowerCase();
    if (query.isEmpty) return this;

    final matchingIndexes = [
      for (var index = 0; index < categories.length; index++)
        if (categories[index].toLowerCase().contains(query)) index,
    ];
    final filteredCategories = [
      for (final index in matchingIndexes) categories[index],
    ];
    final filteredSeries = [
      for (final currentSeries in series)
        currentSeries.copyWith(
          values: [
            for (final index in matchingIndexes)
              index < currentSeries.values.length
                  ? currentSeries.values[index]
                  : 0,
          ],
          points: [
            for (
              var filteredIndex = 0;
              filteredIndex < matchingIndexes.length;
              filteredIndex++
            )
              for (final point in currentSeries.points)
                if (point.x.round() == matchingIndexes[filteredIndex])
                  ChartPoint(
                    x: filteredIndex.toDouble(),
                    y: point.y,
                    label: point.label,
                  ),
          ],
        ),
    ];
    return copyWith(categories: filteredCategories, series: filteredSeries);
  }

  @override
  ChartPayload clone() => ChartPayload(
    title: title,
    chartType: chartType,
    categories: List<String>.from(categories),
    series: series.map((item) => item.clone()).toList(),
    colors: List<Color>.from(colors),
    barOrientation: barOrientation,
    showLegend: showLegend,
    showGrid: showGrid,
    showAxes: showAxes,
    showValues: showValues,
    lineCurved: lineCurved,
    showDots: showDots,
    showTooltips: showTooltips,
    doughnutHoleRatio: doughnutHoleRatio,
    minY: minY,
    maxY: maxY,
    categoryFilter: categoryFilter,
    tableSourceNodeId: tableSourceNodeId,
    tableCategoryColumn: tableCategoryColumn,
    tableValueColumns: List<int>.from(tableValueColumns),
    dataSourceUrl: dataSourceUrl,
    databaseTableName: databaseTableName,
    databaseCategoryColumn: databaseCategoryColumn,
    databaseValueColumns: List<String>.from(databaseValueColumns),
    databaseRowLimit: databaseRowLimit,
    dataRefreshRevision: dataRefreshRevision,
  );

  ChartPayload copyWith({
    String? title,
    ChartType? chartType,
    List<String>? categories,
    List<ChartSeries>? series,
    List<Color>? colors,
    ChartBarOrientation? barOrientation,
    bool? showLegend,
    bool? showGrid,
    bool? showAxes,
    bool? showValues,
    bool? lineCurved,
    bool? showDots,
    bool? showTooltips,
    double? doughnutHoleRatio,
    double? minY,
    bool clearMinY = false,
    double? maxY,
    bool clearMaxY = false,
    String? categoryFilter,
    String? tableSourceNodeId,
    bool clearTableSource = false,
    int? tableCategoryColumn,
    List<int>? tableValueColumns,
    String? dataSourceUrl,
    bool clearDataSourceUrl = false,
    String? databaseTableName,
    bool clearDatabaseTable = false,
    String? databaseCategoryColumn,
    List<String>? databaseValueColumns,
    int? databaseRowLimit,
    int? dataRefreshRevision,
  }) => ChartPayload(
    title: title ?? this.title,
    chartType: chartType ?? this.chartType,
    categories: categories ?? this.categories,
    series: series ?? this.series,
    colors: colors ?? this.colors,
    barOrientation: barOrientation ?? this.barOrientation,
    showLegend: showLegend ?? this.showLegend,
    showGrid: showGrid ?? this.showGrid,
    showAxes: showAxes ?? this.showAxes,
    showValues: showValues ?? this.showValues,
    lineCurved: lineCurved ?? this.lineCurved,
    showDots: showDots ?? this.showDots,
    showTooltips: showTooltips ?? this.showTooltips,
    doughnutHoleRatio: doughnutHoleRatio ?? this.doughnutHoleRatio,
    minY: clearMinY ? null : (minY ?? this.minY),
    maxY: clearMaxY ? null : (maxY ?? this.maxY),
    categoryFilter: categoryFilter ?? this.categoryFilter,
    tableSourceNodeId: clearTableSource
        ? null
        : (tableSourceNodeId ?? this.tableSourceNodeId),
    tableCategoryColumn: tableCategoryColumn ?? this.tableCategoryColumn,
    tableValueColumns: tableValueColumns ?? this.tableValueColumns,
    dataSourceUrl: clearDataSourceUrl
        ? null
        : (dataSourceUrl ?? this.dataSourceUrl),
    databaseTableName: clearDatabaseTable
        ? null
        : (databaseTableName ?? this.databaseTableName),
    databaseCategoryColumn:
        databaseCategoryColumn ?? this.databaseCategoryColumn,
    databaseValueColumns: databaseValueColumns ?? this.databaseValueColumns,
    databaseRowLimit: databaseRowLimit ?? this.databaseRowLimit,
    dataRefreshRevision: dataRefreshRevision ?? this.dataRefreshRevision,
  );
}

List<String> _jsonChartLabels(Object? raw) {
  if (raw is! List) return const ['A', 'B', 'C', 'D'];
  return raw.map((value) => value.toString()).toList();
}

List<String> _boundedChartLabels(Iterable<String> labels) => labels
    .take(_maxChartValues)
    .map((label) => _chartText(label, maxLength: _maxChartLabelLength))
    .toList();

List<double> _boundedChartValues(Iterable<double> values) =>
    values.take(_maxChartValues).map(_finiteChartNumber).toList();

List<ChartPoint> _boundedChartPoints(Iterable<ChartPoint> points) =>
    points.take(_maxChartPoints).map((point) => point.clone()).toList();

List<ChartSeries> _boundedChartSeries(Iterable<ChartSeries> series) =>
    series.take(_maxChartSeries).map((item) => item.clone()).toList();

List<Color> _boundedChartColors(Iterable<Color> colors) {
  final bounded = colors.take(_maxChartSeries).toList();
  return bounded.isEmpty ? [const Color(0xFFF97316)] : bounded;
}

List<int> _boundedTableColumnIndexes(Iterable<int> indexes) =>
    indexes.where((index) => index >= 0).toSet().take(_maxChartSeries).toList();

final _chartIdentifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,62}$');

String? _optionalChartIdentifier(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || !_chartIdentifierPattern.hasMatch(trimmed)) {
    return null;
  }
  return trimmed;
}

String _chartIdentifier(String value, {required String fallback}) =>
    _optionalChartIdentifier(value) ?? fallback;

List<String> _boundedChartIdentifiers(Iterable<String> values) => [
  for (final value in values) ?_optionalChartIdentifier(value),
].take(_maxChartSeries).toList();

double? _tableNumericValue(TablePayload table, List<String> row, int index) {
  if (index < 0 || index >= row.length) return null;
  var raw = row[index].trim();
  final type = table.typeForColumn(index);
  if (type == TableCellType.currency) {
    raw = raw.replaceAll(RegExp(r'[\$,Rp\s]'), '');
  } else if (type == TableCellType.percentage) {
    raw = raw.replaceAll(RegExp(r'[%\s]'), '');
  } else if (type == TableCellType.checkbox) {
    return raw.toLowerCase() == 'true' || raw == '1' ? 1 : 0;
  }
  final value = double.tryParse(raw);
  return value != null && value.isFinite ? value : null;
}

String _chartText(
  String value, {
  required int maxLength,
  String fallback = '',
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return fallback;
  return trimmed.length <= maxLength
      ? trimmed
      : trimmed.substring(0, maxLength);
}

String? _optionalChartText(String? value, {required int maxLength}) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length <= maxLength
      ? trimmed
      : trimmed.substring(0, maxLength);
}

double _finiteChartNumber(Object? value, {double fallback = 0.0}) {
  final number = value is num ? value.toDouble() : fallback;
  return number.isFinite ? number : fallback;
}

double? _optionalFiniteChartNumber(Object? value) {
  if (value == null) return null;
  final number = _finiteChartNumber(value, fallback: double.nan);
  return number.isFinite ? number : null;
}

Color _chartColor(Object? value, Color fallback) =>
    value is num ? Color(value.toInt()) : fallback;

enum TableCellType {
  text,
  number,
  currency,
  percentage,
  checkbox,
  date,
  time,
  formula,
}

class TablePayload extends NodePayload {
  final String name;
  final List<String> columns;
  final List<List<String>> rows;
  final List<TableCellType> columnTypes;
  final Color headerBgColor;
  final Color headerTextColor;
  final Color backgroundColor;
  final Color zebraColor;
  final Color borderColor;
  final double borderWidth;
  final double cornerRadius;
  final bool hasShadow;
  final bool showSummaryRow;
  final Map<int, String>
  summaryAggregates; // index -> 'SUM', 'AVG', 'MIN', 'MAX', 'COUNT'

  TablePayload({
    this.name = '',
    this.columns = const ['Feature', 'Priority', 'Status'],
    this.rows = const [
      ['Authentication', 'High', 'Done'],
      ['Drawing Engine', 'High', 'Active'],
      ['Multiplayer CRDT', 'Medium', 'Pending'],
    ],
    List<TableCellType>? columnTypes,
    this.headerBgColor = const Color(0xFF282B34),
    this.headerTextColor = const Color(0xFFF97316),
    this.backgroundColor = const Color(0xFF1E2026),
    this.zebraColor = const Color(0xFF22252C),
    this.borderColor = const Color(0xFF373A44),
    this.borderWidth = 1.2,
    this.cornerRadius = 6.0,
    this.hasShadow = true,
    this.showSummaryRow = false,
    this.summaryAggregates = const {},
  }) : columnTypes = columnTypes ?? const [];

  TableCellType typeForColumn(int index) =>
      index < columnTypes.length ? columnTypes[index] : TableCellType.text;

  factory TablePayload.fromJson(Map<String, dynamic> json) => TablePayload(
    name: json['name'] as String? ?? '',
    columns:
        (json['columns'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['Column 1', 'Column 2'],
    rows:
        (json['rows'] as List<dynamic>?)
            ?.map((r) => (r as List<dynamic>).map((c) => c.toString()).toList())
            .toList() ??
        const [],
    columnTypes: (json['columnTypes'] as List<dynamic>?)
        ?.map(
          (e) => TableCellType.values.firstWhere(
            (t) => t.name == e.toString(),
            orElse: () => TableCellType.text,
          ),
        )
        .toList(),
    headerBgColor: json['headerBgColor'] != null
        ? Color(json['headerBgColor'] as int)
        : const Color(0xFF282B34),
    headerTextColor: json['headerTextColor'] != null
        ? Color(json['headerTextColor'] as int)
        : const Color(0xFFF97316),
    backgroundColor: json['backgroundColor'] != null
        ? Color(json['backgroundColor'] as int)
        : const Color(0xFF1E2026),
    zebraColor: json['zebraColor'] != null
        ? Color(json['zebraColor'] as int)
        : const Color(0xFF22252C),
    borderColor: json['borderColor'] != null
        ? Color(json['borderColor'] as int)
        : const Color(0xFF373A44),
    borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 1.2,
    cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 6.0,
    hasShadow: json['hasShadow'] as bool? ?? true,
    showSummaryRow: json['showSummaryRow'] as bool? ?? false,
    summaryAggregates:
        (json['summaryAggregates'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(int.tryParse(k) ?? 0, v.toString()),
        ) ??
        const {},
  );

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    'columns': columns,
    'rows': rows,
    'columnTypes': columnTypes.map((t) => t.name).toList(),
    'headerBgColor': headerBgColor.toARGB32(),
    'headerTextColor': headerTextColor.toARGB32(),
    'backgroundColor': backgroundColor.toARGB32(),
    'zebraColor': zebraColor.toARGB32(),
    'borderColor': borderColor.toARGB32(),
    'borderWidth': borderWidth,
    'cornerRadius': cornerRadius,
    'hasShadow': hasShadow,
    'showSummaryRow': showSummaryRow,
    'summaryAggregates': summaryAggregates.map(
      (k, v) => MapEntry(k.toString(), v),
    ),
  };

  @override
  TablePayload clone() => TablePayload(
    name: name,
    columns: List<String>.from(columns),
    rows: rows.map((r) => List<String>.from(r)).toList(),
    columnTypes: List<TableCellType>.from(columnTypes),
    headerBgColor: headerBgColor,
    headerTextColor: headerTextColor,
    backgroundColor: backgroundColor,
    zebraColor: zebraColor,
    borderColor: borderColor,
    borderWidth: borderWidth,
    cornerRadius: cornerRadius,
    hasShadow: hasShadow,
    showSummaryRow: showSummaryRow,
    summaryAggregates: Map<int, String>.from(summaryAggregates),
  );

  TablePayload copyWith({
    String? name,
    List<String>? columns,
    List<List<String>>? rows,
    List<TableCellType>? columnTypes,
    Color? headerBgColor,
    Color? headerTextColor,
    Color? backgroundColor,
    Color? zebraColor,
    Color? borderColor,
    double? borderWidth,
    double? cornerRadius,
    bool? hasShadow,
    bool? showSummaryRow,
    Map<int, String>? summaryAggregates,
  }) {
    return TablePayload(
      name: name ?? this.name,
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      columnTypes: columnTypes ?? this.columnTypes,
      headerBgColor: headerBgColor ?? this.headerBgColor,
      headerTextColor: headerTextColor ?? this.headerTextColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      zebraColor: zebraColor ?? this.zebraColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      hasShadow: hasShadow ?? this.hasShadow,
      showSummaryRow: showSummaryRow ?? this.showSummaryRow,
      summaryAggregates: summaryAggregates ?? this.summaryAggregates,
    );
  }
}

enum TodoPriority {
  none,
  low,
  medium,
  high;

  String get label {
    switch (this) {
      case TodoPriority.high:
        return 'High';
      case TodoPriority.medium:
        return 'Medium';
      case TodoPriority.low:
        return 'Low';
      case TodoPriority.none:
        return 'None';
    }
  }

  static TodoPriority fromString(String? val) {
    if (val == null) return TodoPriority.none;
    return TodoPriority.values.firstWhere(
      (e) => e.name.toLowerCase() == val.toLowerCase(),
      orElse: () => TodoPriority.none,
    );
  }
}

class TodoItem {
  final String id;
  final String text;
  final bool isDone;
  final String? dueDate;
  final String? assignee;
  final TodoPriority priority;
  final List<String> tags;

  TodoItem({
    required this.id,
    required this.text,
    this.isDone = false,
    this.dueDate,
    this.assignee,
    this.priority = TodoPriority.none,
    this.tags = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'isDone': isDone,
    'dueDate': dueDate,
    'assignee': assignee,
    'priority': priority.name,
    'tags': tags,
  };

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
    id: json['id'] as String? ?? '',
    text: json['text'] as String? ?? '',
    isDone: json['isDone'] as bool? ?? false,
    dueDate: json['dueDate'] as String?,
    assignee: json['assignee'] as String?,
    priority: TodoPriority.fromString(json['priority'] as String?),
    tags:
        (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
        const [],
  );

  TodoItem copyWith({
    String? id,
    String? text,
    bool? isDone,
    String? dueDate,
    String? assignee,
    TodoPriority? priority,
    List<String>? tags,
  }) => TodoItem(
    id: id ?? this.id,
    text: text ?? this.text,
    isDone: isDone ?? this.isDone,
    dueDate: dueDate ?? this.dueDate,
    assignee: assignee ?? this.assignee,
    priority: priority ?? this.priority,
    tags: tags ?? this.tags,
  );
}

class TodoListPayload extends NodePayload {
  final String title;
  final List<TodoItem> items;
  final Color backgroundColor;
  final Color accentColor;
  final Color borderColor;
  final double borderWidth;
  final double cornerRadius;
  final bool hasShadow;
  final String filterMode; // 'all', 'active', 'completed'
  final bool showProgressBar;

  TodoListPayload({
    this.title = 'Tasks & Actions',
    this.items = const [],
    this.backgroundColor = const Color(0xFF1F2430),
    this.accentColor = const Color(0xFF10B981),
    this.borderColor = const Color(0xFF10B981),
    this.borderWidth = 1.2,
    this.cornerRadius = 8.0,
    this.hasShadow = true,
    this.filterMode = 'all',
    this.showProgressBar = true,
  });

  factory TodoListPayload.fromJson(Map<String, dynamic> json) =>
      TodoListPayload(
        title: json['title'] as String? ?? 'Tasks & Actions',
        items:
            (json['items'] as List<dynamic>?)
                ?.map((e) => TodoItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        backgroundColor: json['backgroundColor'] != null
            ? Color(json['backgroundColor'] as int)
            : const Color(0xFF1F2430),
        accentColor: json['accentColor'] != null
            ? Color(json['accentColor'] as int)
            : const Color(0xFF10B981),
        borderColor: json['borderColor'] != null
            ? Color(json['borderColor'] as int)
            : const Color(0xFF10B981),
        borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 1.2,
        cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 8.0,
        hasShadow: json['hasShadow'] as bool? ?? true,
        filterMode: json['filterMode'] as String? ?? 'all',
        showProgressBar: json['showProgressBar'] as bool? ?? true,
      );

  @override
  Map<String, dynamic> toJson() => {
    'title': title,
    'items': items.map((i) => i.toJson()).toList(),
    'backgroundColor': backgroundColor.toARGB32(),
    'accentColor': accentColor.toARGB32(),
    'borderColor': borderColor.toARGB32(),
    'borderWidth': borderWidth,
    'cornerRadius': cornerRadius,
    'hasShadow': hasShadow,
    'filterMode': filterMode,
    'showProgressBar': showProgressBar,
  };

  @override
  TodoListPayload clone() => TodoListPayload(
    title: title,
    items: List<TodoItem>.from(items),
    backgroundColor: backgroundColor,
    accentColor: accentColor,
    borderColor: borderColor,
    borderWidth: borderWidth,
    cornerRadius: cornerRadius,
    hasShadow: hasShadow,
    filterMode: filterMode,
    showProgressBar: showProgressBar,
  );

  TodoListPayload copyWith({
    String? title,
    List<TodoItem>? items,
    Color? backgroundColor,
    Color? accentColor,
    Color? borderColor,
    double? borderWidth,
    double? cornerRadius,
    bool? hasShadow,
    String? filterMode,
    bool? showProgressBar,
  }) {
    return TodoListPayload(
      title: title ?? this.title,
      items: items ?? this.items,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      accentColor: accentColor ?? this.accentColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      hasShadow: hasShadow ?? this.hasShadow,
      filterMode: filterMode ?? this.filterMode,
      showProgressBar: showProgressBar ?? this.showProgressBar,
    );
  }
}
