import 'dart:math';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Viewport;
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/domain/models/design_tokens.dart';
import 'grid_painter.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/drawing_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/vector_path_payload.dart';
import 'package:varian/domain/models/viewport.dart';
import 'package:varian/features/diagrams/domain/diagram_shape_catalog.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';
import 'package:varian/features/canvas/utils/brush_path_smoother.dart';
import 'package:varian/features/canvas/utils/hit_tester.dart';
import 'package:varian/features/canvas/utils/snap_engine.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';
import 'package:varian/features/collaboration/presentation/painters/cursor_painter.dart';
import 'edge_painter.dart';
import 'node_painter.dart';

class CanvasPainter extends CustomPainter {
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final List<RemoteCursor> cursors;
  final Viewport viewport;
  final Set<String> selectedNodeIds;
  final Rect? selectionMarquee;
  final List<SnapGuide> snapGuides;
  final List<SpacingMeasurement> measurements;

  // Real-time ephemeral creation & editing previews
  final List<Offset> activeBrushStroke;
  final BrushType activeBrushType;
  final Color activeBrushColor;
  final double activeBrushWidth;
  final double activeBrushOpacity;
  final bool activeBrushSmooth;

  final CanvasTool? activeCreationTool;
  final String? activeDiagramShapeId;
  final Rect? creationPreviewRect;
  final (Offset, Offset)? creationPreviewLine;

  final (Offset, Offset)? connectorPreview;
  final CanvasEdge? connectorEditPreview;
  final String? connectorSnapNodeId;
  final Offset? connectorSnapPoint;

  final List<BezierPoint> activePenPoints;
  final Offset? penHoverPosition;
  final Offset? brushCursorPosition;
  final String? editingNodeId;
  final CanvasRenderTokens? renderTokens;
  final DesignTokenSet? designTokens;
  final bool renderEdges;
  final bool renderNodes;
  final bool renderForeground;
  final bool showRotationHandle;
  final CanvasImageCache? imageCache;

  const CanvasPainter({
    required this.nodes,
    this.edges = const [],
    this.cursors = const [],
    required this.viewport,
    required this.selectedNodeIds,
    this.selectionMarquee,
    this.snapGuides = const [],
    this.measurements = const [],
    this.activeBrushStroke = const [],
    this.activeBrushType = BrushType.ink,
    this.activeBrushColor = const Color(0xFFF97316),
    this.activeBrushWidth = 3.0,
    this.activeBrushOpacity = 1.0,
    this.activeBrushSmooth = true,
    this.activeCreationTool,
    this.activeDiagramShapeId,
    this.creationPreviewRect,
    this.creationPreviewLine,
    this.connectorPreview,
    this.connectorEditPreview,
    this.connectorSnapNodeId,
    this.connectorSnapPoint,
    this.activePenPoints = const [],
    this.penHoverPosition,
    this.brushCursorPosition,
    this.editingNodeId,
    this.renderTokens,
    this.designTokens,
    this.renderEdges = true,
    this.renderNodes = true,
    this.renderForeground = true,
    this.showRotationHandle = false,
    this.imageCache,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(viewport.x, viewport.y);
    canvas.scale(viewport.zoom, viewport.zoom);

    final double worldLeft = -viewport.x / viewport.zoom;
    final double worldTop = -viewport.y / viewport.zoom;
    final double worldWidth = size.width / viewport.zoom;
    final double worldHeight = size.height / viewport.zoom;
    final worldViewportRect = Rect.fromLTWH(
      worldLeft,
      worldTop,
      worldWidth,
      worldHeight,
    );

    final palette = renderTokens ?? CanvasRenderTokens.dark;
    if (renderEdges) {
      final nodeMap = {for (final n in nodes) n.id: n};
      for (final edge in edges) {
        final preview = connectorEditPreview?.id == edge.id
            ? connectorEditPreview
            : null;
        final edgeToPaint = preview ?? edge;
        final isSelected = selectedNodeIds.contains(edge.id);
        EdgePainter.paint(
          canvas,
          edgeToPaint,
          nodeMap,
          isSelected: isSelected,
          zoom: viewport.zoom,
          renderTokens: palette,
        );
      }
    }

    if (renderNodes) {
      final nodeMap = {for (final n in nodes) n.id: n};
      final sortedNodes = List<CanvasNode>.from(nodes)
        ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

      // Render frame containers first, then children with clipping if enabled
      for (final node in sortedNodes) {
        if (!node.bounds.overlaps(worldViewportRect)) continue;
        // Do not paint canvas node text if it is currently being edited in the inline TextField.
        if (node.id == editingNodeId && node.type == NodeType.text) continue;
        final nodeToPaint =
            node.id == editingNodeId && node.payload is ShapePayload
            ? node.copyWith(
                payload: (node.payload as ShapePayload).copyWith(label: ''),
              )
            : node;
        final textPathNode = nodeToPaint.payload is TextPayload
            ? nodeMap[(nodeToPaint.payload as TextPayload).textPathNodeId]
            : null;

        final vectorMask = nodeToPaint.payload is VectorPathPayload
            ? nodeMap[(nodeToPaint.payload as VectorPathPayload).maskNodeId]
            : null;
        final vectorMaskPayload = vectorMask?.payload is VectorPathPayload
            ? vectorMask!.payload as VectorPathPayload
            : null;
        final hasVectorMask = vectorMaskPayload != null;
        final maskLayerBounds = hasVectorMask
            ? _maskLayerBounds(nodeToPaint, vectorMask!)
            : Rect.zero;
        if (hasVectorMask) {
          canvas.saveLayer(maskLayerBounds, Paint());
        }

        if (node.parentId != null) {
          final parent = nodeMap[node.parentId];
          if (parent != null &&
              parent.type == NodeType.frame &&
              parent.payload is FramePayload) {
            final framePayload = parent.payload as FramePayload;
            if (framePayload.clipContent) {
              canvas.save();
              final parentRect = Rect.fromLTWH(
                parent.x,
                parent.y,
                parent.width,
                parent.height,
              );
              clipToFrame(
                canvas,
                frameRect: parentRect,
                rotation: parent.rotation,
                cornerRadius: framePayload.cornerRadius,
              );
              NodePainter.paint(
                canvas,
                nodeToPaint,
                renderTokens: palette,
                textPathNode: textPathNode,
                designTokens: designTokens,
                imageCache: imageCache,
              );
              canvas.restore();
              if (hasVectorMask) {
                _paintVectorMask(
                  canvas,
                  vectorMask!,
                  vectorMaskPayload,
                  maskMode: (nodeToPaint.payload as VectorPathPayload).maskMode,
                  layerBounds: maskLayerBounds,
                );
                canvas.restore();
              }
              continue;
            }
          }
        }

        NodePainter.paint(
          canvas,
          nodeToPaint,
          renderTokens: palette,
          textPathNode: textPathNode,
          designTokens: designTokens,
          imageCache: imageCache,
        );
        if (hasVectorMask) {
          _paintVectorMask(
            canvas,
            vectorMask!,
            vectorMaskPayload,
            maskMode: (nodeToPaint.payload as VectorPathPayload).maskMode,
            layerBounds: maskLayerBounds,
          );
          canvas.restore();
        }
      }
    }

    if (renderForeground) {
      // Paint real-time ephemeral layers
      _paintActiveBrushStroke(canvas);
      _paintCreationPreview(canvas);
      _paintConnectorPreview(canvas);
      _paintConnectorControls(canvas, palette);
      _paintConnectorSnapTarget(canvas, palette);
      _paintPenPathPreview(canvas);
      _paintBrushCursor(canvas);

      _paintSelectionHighlights(canvas);
      _paintSnapGuides(canvas, worldViewportRect);
      _paintMeasurements(canvas);
      _paintRemoteSelections(canvas);

      for (final cursor in cursors) {
        CursorPainter.paint(canvas, cursor, viewport.zoom);
      }

      if (selectionMarquee != null) {
        final marqueeFill = Paint()
          ..color = palette.selection.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill;
        final marqueeStroke = Paint()
          ..color = palette.selection
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 / viewport.zoom;

        canvas.drawRect(selectionMarquee!, marqueeFill);
        canvas.drawRect(selectionMarquee!, marqueeStroke);
      }
    }

    canvas.restore();
  }

  /// Clips to a frame boundary while preserving the child's current canvas
  /// transform. The path is transformed instead of the canvas so a child
  /// that already carries its own rotation is not rotated twice.
  static void clipToFrame(
    Canvas canvas, {
    required Rect frameRect,
    required double rotation,
    required double cornerRadius,
  }) {
    if (!rotation.isFinite || rotation == 0.0) {
      if (cornerRadius > 0) {
        canvas.clipRRect(
          RRect.fromRectAndRadius(frameRect, Radius.circular(cornerRadius)),
        );
      } else {
        canvas.clipRect(frameRect);
      }
      return;
    }
    canvas.clipPath(
      rotatedFrameClipPath(
        frameRect: frameRect,
        rotation: rotation,
        cornerRadius: cornerRadius,
      ),
    );
  }

  static Path rotatedFrameClipPath({
    required Rect frameRect,
    required double rotation,
    required double cornerRadius,
  }) {
    final path = Path();
    if (cornerRadius > 0) {
      path.addRRect(
        RRect.fromRectAndRadius(frameRect, Radius.circular(cornerRadius)),
      );
    } else {
      path.addRect(frameRect);
    }

    if (!rotation.isFinite || rotation == 0.0) return path;
    final center = frameRect.center;
    final cosine = math.cos(rotation);
    final sine = math.sin(rotation);
    final translateX = center.dx - cosine * center.dx + sine * center.dy;
    final translateY = center.dy - sine * center.dx - cosine * center.dy;
    return path.transform(
      Float64List.fromList([
        cosine,
        sine,
        0,
        0,
        -sine,
        cosine,
        0,
        0,
        0,
        0,
        1,
        0,
        translateX,
        translateY,
        0,
        1,
      ]),
    );
  }

  static Rect _maskLayerBounds(CanvasNode node, CanvasNode mask) {
    final nodeBounds = _rotatedNodeBounds(node);
    final maskBounds = _rotatedNodeBounds(mask);
    final left = math.min(nodeBounds.left, maskBounds.left);
    final top = math.min(nodeBounds.top, maskBounds.top);
    final right = math.max(nodeBounds.right, maskBounds.right);
    final bottom = math.max(nodeBounds.bottom, maskBounds.bottom);
    return Rect.fromLTRB(left, top, right, bottom).inflate(1.0);
  }

  static Rect _rotatedNodeBounds(CanvasNode node) {
    final cosine = math.cos(node.rotation).abs();
    final sine = math.sin(node.rotation).abs();
    final width = node.width * cosine + node.height * sine;
    final height = node.width * sine + node.height * cosine;
    final center = Offset(
      node.x + node.width / 2.0,
      node.y + node.height / 2.0,
    );
    return Rect.fromCenter(center: center, width: width, height: height);
  }

  static void _paintVectorMask(
    Canvas canvas,
    CanvasNode maskNode,
    VectorPathPayload maskPayload, {
    required VectorMaskMode maskMode,
    required Rect layerBounds,
  }) {
    final path = maskPayload.toPath(closeOpenSubpaths: true);
    if (maskPayload.allSubpaths.isEmpty) return;

    final maskPaint = Paint()
      ..style = PaintingStyle.fill
      ..colorFilter = ColorFilter.matrix(
        _vectorMaskColorFilterMatrix(maskMode),
      );
    if (maskPayload.isGradientFill) {
      final colors = [maskPayload.fill, maskPayload.gradientEndColor];
      final bounds = Rect.fromLTWH(0, 0, maskNode.width, maskNode.height);
      maskPaint.shader = switch (maskPayload.gradientType) {
        FillType.radialGradient => RadialGradient(
          colors: colors,
        ).createShader(bounds),
        FillType.angularGradient => SweepGradient(
          colors: colors,
        ).createShader(bounds),
        _ => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(bounds),
      };
    } else {
      maskPaint.color = maskPayload.fill;
    }

    canvas.saveLayer(layerBounds, Paint()..blendMode = BlendMode.dstIn);
    canvas.save();
    canvas.translate(maskNode.x, maskNode.y);
    if (maskNode.rotation != 0.0) {
      canvas.translate(maskNode.width / 2.0, maskNode.height / 2.0);
      canvas.rotate(maskNode.rotation);
      canvas.translate(-maskNode.width / 2.0, -maskNode.height / 2.0);
    }
    canvas.drawPath(path, maskPaint);
    canvas.restore();
    canvas.restore();
  }

  static List<double> _vectorMaskColorFilterMatrix(VectorMaskMode mode) {
    switch (mode) {
      case VectorMaskMode.alpha:
        return const [
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ];
      case VectorMaskMode.luminance:
        return const [
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
        ];
      case VectorMaskMode.invertedLuminance:
        return const [
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          -0.2126,
          -0.7152,
          -0.0722,
          0,
          255,
        ];
    }
  }

  void _paintRemoteSelections(Canvas canvas) {
    final nodesById = {for (final node in nodes) node.id: node};
    for (final cursor in cursors) {
      final selectedIds = <String>{
        ...cursor.selectedNodeIds,
        if (cursor.selectedNodeId != null) cursor.selectedNodeId!,
      };
      if (selectedIds.isEmpty) continue;
      final paint = Paint()
        ..color = cursor.userColor.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 / viewport.zoom;
      for (final nodeId in selectedIds) {
        final node = nodesById[nodeId];
        if (node == null) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(node.bounds, const Radius.circular(4)),
          paint,
        );
      }
    }
  }

  void _paintActiveBrushStroke(Canvas canvas) {
    if (activeBrushStroke.length < 2) return;
    if (activeBrushType == BrushType.eraser) return;

    final paint = Paint()
      ..strokeWidth = activeBrushWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    switch (activeBrushType) {
      case BrushType.ink:
        paint.color = activeBrushColor.withValues(alpha: activeBrushOpacity);
        break;
      case BrushType.marker:
        paint.color = activeBrushColor.withValues(
          alpha: (activeBrushOpacity * 0.55).clamp(0.0, 1.0),
        );
        paint.strokeCap = StrokeCap.square;
        break;
      case BrushType.airbrush:
        paint.color = activeBrushColor.withValues(
          alpha: (activeBrushOpacity * 0.4).clamp(0.0, 1.0),
        );
        paint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          activeBrushWidth * 0.5,
        );
        break;
      case BrushType.highlighter:
        paint.color = activeBrushColor.withValues(
          alpha: (activeBrushOpacity * 0.4).clamp(0.0, 1.0),
        );
        paint.strokeCap = StrokeCap.square;
        paint.strokeWidth = activeBrushWidth * 2.5;
        break;
      case BrushType.calligraphy:
        paint.color = activeBrushColor.withValues(alpha: activeBrushOpacity);
        paint.strokeCap = StrokeCap.butt;
        break;
      case BrushType.pencil:
        paint.color = activeBrushColor.withValues(
          alpha: (activeBrushOpacity * 0.7).clamp(0.0, 1.0),
        );
        paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.4);
        paint.strokeWidth = activeBrushWidth * 0.8;
        break;
      case BrushType.eraser:
        return;
    }

    final path = activeBrushSmooth
        ? BrushPathSmoother.buildSmoothPath(activeBrushStroke)
        : BrushPathSmoother.buildLinearPath(activeBrushStroke);

    if (activeBrushType == BrushType.calligraphy) {
      const ribbonOffset = Offset(1.5, 1.5);
      canvas.drawPath(path.shift(-ribbonOffset), paint);
      canvas.drawPath(path, paint);
      canvas.drawPath(path.shift(ribbonOffset), paint);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  void _paintBrushCursor(Canvas canvas) {
    final palette = renderTokens ?? CanvasRenderTokens.dark;
    final pos = brushCursorPosition;
    if (pos == null) return;

    final double radius =
        (activeBrushType == BrushType.eraser
            ? activeBrushWidth
            : (activeBrushType == BrushType.highlighter
                  ? activeBrushWidth * 2.5
                  : activeBrushWidth)) /
        2.0;

    final outlinePaint = Paint()
      ..color = activeBrushColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / viewport.zoom;

    switch (activeBrushType) {
      case BrushType.marker:
      case BrushType.highlighter:
        canvas.drawRect(
          Rect.fromCenter(center: pos, width: radius * 2, height: radius * 2),
          outlinePaint,
        );
        break;
      case BrushType.airbrush:
        final fillPaint = Paint()
          ..color = activeBrushColor.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pos, radius, fillPaint);
        canvas.drawCircle(pos, radius, outlinePaint);
        break;
      case BrushType.calligraphy:
        final calPaint = Paint()
          ..color = activeBrushColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 / viewport.zoom;
        canvas.drawLine(
          pos - Offset(radius, radius),
          pos + Offset(radius, radius),
          calPaint,
        );
        break;
      case BrushType.pencil:
        outlinePaint.color = activeBrushColor.withValues(alpha: 0.8);
        canvas.drawCircle(pos, radius, outlinePaint);
        break;
      case BrushType.eraser:
        outlinePaint.color = palette.danger;
        final fillPaint = Paint()
          ..color = palette.danger.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pos, radius, fillPaint);
        canvas.drawCircle(pos, radius, outlinePaint);
        break;
      case BrushType.ink:
        canvas.drawCircle(pos, radius, outlinePaint);
        break;
    }
  }

  void _paintCreationPreview(Canvas canvas) {
    final palette = renderTokens ?? CanvasRenderTokens.dark;
    if (creationPreviewLine != null) {
      final (p1, p2) = creationPreviewLine!;
      final strokePaint = Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      canvas.drawLine(p1, p2, strokePaint);

      if (activeCreationTool == CanvasTool.arrow) {
        const double arrowSize = 12.0;
        final arrowHead = Path()
          ..moveTo(p2.dx, p2.dy)
          ..lineTo(
            p2.dx -
                arrowSize *
                    (p2 == p1
                        ? 0
                        : 0.866 * (p2 - p1).dx / (p2 - p1).distance -
                              0.5 * (p2 - p1).dy / (p2 - p1).distance),
            p2.dy -
                arrowSize *
                    (p2 == p1
                        ? 0
                        : 0.866 * (p2 - p1).dy / (p2 - p1).distance +
                              0.5 * (p2 - p1).dx / (p2 - p1).distance),
          )
          ..lineTo(
            p2.dx -
                arrowSize *
                    (p2 == p1
                        ? 0
                        : 0.866 * (p2 - p1).dx / (p2 - p1).distance +
                              0.5 * (p2 - p1).dy / (p2 - p1).distance),
            p2.dy -
                arrowSize *
                    (p2 == p1
                        ? 0
                        : 0.866 * (p2 - p1).dy / (p2 - p1).distance -
                              0.5 * (p2 - p1).dx / (p2 - p1).distance),
          )
          ..close();
        final arrowFill = Paint()
          ..color = palette.accent
          ..style = PaintingStyle.fill;
        canvas.drawPath(arrowHead, arrowFill);
      }
      return;
    }

    if (creationPreviewRect == null || activeCreationTool == null) return;
    final rect = creationPreviewRect!;

    final previewFill = Paint()
      ..color = palette.accent.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    final previewStroke = Paint()
      ..color = palette.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / viewport.zoom;

    if (activeCreationTool == CanvasTool.diagramShape &&
        activeDiagramShapeId != null) {
      final shapeRect = DiagramShapeCatalog.normalizeCreationRect(
        activeDiagramShapeId,
        rect,
      );
      final path = DiagramShapeCatalog.resolve(
        activeDiagramShapeId!,
      ).buildPath(shapeRect.size);
      canvas.drawPath(path.shift(shapeRect.topLeft), previewFill);
      canvas.drawPath(path.shift(shapeRect.topLeft), previewStroke);
      return;
    }

    switch (activeCreationTool!) {
      case CanvasTool.rectangle:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          previewFill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          previewStroke,
        );
        break;
      case CanvasTool.ellipse:
        canvas.drawOval(rect, previewFill);
        canvas.drawOval(rect, previewStroke);
        break;
      case CanvasTool.diamond:
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
        canvas.drawPath(path, previewFill);
        canvas.drawPath(path, previewStroke);
        break;
      case CanvasTool.cylinder:
        final capHeight = (rect.height * 0.25).clamp(8.0, 24.0);
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left,
            rect.top + capHeight / 2,
            rect.width,
            rect.height - capHeight,
          ),
          previewFill,
        );
        canvas.drawOval(
          Rect.fromLTWH(rect.left, rect.top, rect.width, capHeight),
          previewFill,
        );
        canvas.drawOval(
          Rect.fromLTWH(
            rect.left,
            rect.bottom - capHeight,
            rect.width,
            capHeight,
          ),
          previewFill,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left,
            rect.top + capHeight / 2,
            rect.width,
            rect.height - capHeight,
          ),
          previewStroke,
        );
        canvas.drawOval(
          Rect.fromLTWH(rect.left, rect.top, rect.width, capHeight),
          previewStroke,
        );
        canvas.drawOval(
          Rect.fromLTWH(
            rect.left,
            rect.bottom - capHeight,
            rect.width,
            capHeight,
          ),
          previewStroke,
        );
        break;
      case CanvasTool.parallelogram:
        final offset = (rect.width * 0.2).clamp(10.0, 25.0);
        final path = Path()
          ..moveTo(rect.left + offset, rect.top)
          ..lineTo(rect.right, rect.top)
          ..lineTo(rect.right - offset, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
        canvas.drawPath(path, previewFill);
        canvas.drawPath(path, previewStroke);
        break;
      case CanvasTool.stickyNote:
        final noteFill = Paint()
          ..color = const Color(0xFFFEF08A).withValues(alpha: 0.75)
          ..style = PaintingStyle.fill;
        canvas.drawRect(rect, noteFill);
        canvas.drawRect(rect, previewStroke);
        break;
      case CanvasTool.frame:
        final frameStroke = Paint()
          ..color = palette.info
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / viewport.zoom;
        canvas.drawRect(rect, frameStroke);
        break;
      case CanvasTool.text:
        canvas.drawRect(rect, previewFill);
        canvas.drawRect(rect, previewStroke);
        break;
      case CanvasTool.component:
        final compFill = Paint()
          ..color = palette.info.withValues(alpha: 0.18)
          ..style = PaintingStyle.fill;
        final compStroke = Paint()
          ..color = palette.info
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / viewport.zoom;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          compFill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          compStroke,
        );
        break;
      default:
        canvas.drawRect(rect, previewFill);
        canvas.drawRect(rect, previewStroke);
        break;
    }
  }

  void _paintConnectorControls(Canvas canvas, CanvasRenderTokens palette) {
    final nodeMap = {for (final node in nodes) node.id: node};
    for (final edge in edges) {
      if (!selectedNodeIds.contains(edge.id)) continue;
      final edgeToPaint = connectorEditPreview?.id == edge.id
          ? connectorEditPreview!
          : edge;
      EdgePainter.paintControls(
        canvas,
        edgeToPaint,
        nodeMap,
        zoom: viewport.zoom,
        renderTokens: palette,
      );
    }
  }

  void _paintConnectorSnapTarget(Canvas canvas, CanvasRenderTokens palette) {
    final point = connectorSnapPoint;
    if (point == null) return;
    final node = connectorSnapNodeId == null
        ? null
        : nodes
              .where((candidate) => candidate.id == connectorSnapNodeId)
              .firstOrNull;
    if (node != null) {
      final outline = Paint()
        ..color = palette.accent.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 / viewport.zoom;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          node.bounds.inflate(5.0 / viewport.zoom),
          Radius.circular(6.0 / viewport.zoom),
        ),
        outline,
      );
    }
    final fill = Paint()
      ..color = palette.accent.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = palette.canvas
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / viewport.zoom;
    canvas.drawCircle(point, 6.0 / viewport.zoom, fill);
    canvas.drawCircle(point, 6.0 / viewport.zoom, stroke);
  }

  void _paintConnectorPreview(Canvas canvas) {
    final palette = renderTokens ?? CanvasRenderTokens.dark;
    if (connectorPreview == null) return;
    final (start, end) = connectorPreview!;

    final linePaint = Paint()
      ..color = palette.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / viewport.zoom;

    // Draw dashed connection line
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);

    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()
      ..color = palette.accent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, 4.0 / viewport.zoom, dotPaint);
    canvas.drawCircle(end, 4.0 / viewport.zoom, dotPaint);
  }

  void _paintPenPathPreview(Canvas canvas) {
    final palette = renderTokens ?? CanvasRenderTokens.dark;
    if (activePenPoints.isEmpty) return;

    final strokePaint = Paint()
      ..color = palette.info
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / viewport.zoom;

    final path = Path();
    path.moveTo(activePenPoints.first.point.dx, activePenPoints.first.point.dy);

    for (int i = 0; i < activePenPoints.length - 1; i++) {
      final p1 = activePenPoints[i];
      final p2 = activePenPoints[i + 1];
      final cp1 = p1.point + p1.handleOut;
      final cp2 = p2.point + p2.handleIn;
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.point.dx, p2.point.dy);
    }

    if (penHoverPosition != null && activePenPoints.isNotEmpty) {
      final last = activePenPoints.last;
      final cp1 = last.point + last.handleOut;
      path.cubicTo(
        cp1.dx,
        cp1.dy,
        penHoverPosition!.dx,
        penHoverPosition!.dy,
        penHoverPosition!.dx,
        penHoverPosition!.dy,
      );
    }

    canvas.drawPath(path, strokePaint);

    final handleLinePaint = Paint()
      ..color = palette.textMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / viewport.zoom;

    final anchorPaint = Paint()
      ..color = palette.info
      ..style = PaintingStyle.fill;

    final handleDotPaint = Paint()
      ..color = palette.warning
      ..style = PaintingStyle.fill;

    for (int i = 0; i < activePenPoints.length; i++) {
      final bp = activePenPoints[i];
      // Highlight the first anchor with a pulsing close loop target if cursor is hovering near it
      final isFirst = i == 0;
      final isHoveringFirst =
          isFirst &&
          penHoverPosition != null &&
          activePenPoints.length >= 2 &&
          (penHoverPosition! - bp.point).distance < 14.0;

      if (isHoveringFirst) {
        final closeGlow = Paint()
          ..color = palette.success.withValues(alpha: 0.4)
          ..style = PaintingStyle.fill;
        final closeBorder = Paint()
          ..color = palette.success
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 / viewport.zoom;
        canvas.drawCircle(bp.point, 8.0 / viewport.zoom, closeGlow);
        canvas.drawCircle(bp.point, 8.0 / viewport.zoom, closeBorder);
      }

      // Draw anchor
      canvas.drawCircle(bp.point, 4.0 / viewport.zoom, anchorPaint);

      // Draw handles
      if (bp.handleIn != Offset.zero) {
        final inPos = bp.point + bp.handleIn;
        canvas.drawLine(bp.point, inPos, handleLinePaint);
        canvas.drawCircle(inPos, 3.0 / viewport.zoom, handleDotPaint);
      }
      if (bp.handleOut != Offset.zero) {
        final outPos = bp.point + bp.handleOut;
        canvas.drawLine(bp.point, outPos, handleLinePaint);
        canvas.drawCircle(outPos, 3.0 / viewport.zoom, handleDotPaint);
      }
    }
  }

  void _paintSnapGuides(Canvas canvas, Rect bounds) {
    final palette = renderTokens ?? CanvasRenderTokens.dark;
    final guidePaint = Paint()
      ..color = palette.info
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / viewport.zoom;

    for (final guide in snapGuides) {
      if (guide.isVertical) {
        canvas.drawLine(
          Offset(guide.position, bounds.top),
          Offset(guide.position, bounds.bottom),
          guidePaint,
        );
      } else {
        canvas.drawLine(
          Offset(bounds.left, guide.position),
          Offset(bounds.right, guide.position),
          guidePaint,
        );
      }
    }
  }

  void _paintMeasurements(Canvas canvas) {
    final palette = renderTokens ?? CanvasRenderTokens.dark;
    if (measurements.isEmpty) return;

    final measurePaint = Paint()
      ..color = palette.danger
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / viewport.zoom;

    final tickLen = 4.0 / viewport.zoom;

    for (final m in measurements) {
      canvas.drawLine(m.a, m.b, measurePaint);

      final tickDir = m.isVertical ? const Offset(1, 0) : const Offset(0, 1);
      canvas.drawLine(
        m.a - tickDir * tickLen,
        m.a + tickDir * tickLen,
        measurePaint,
      );
      canvas.drawLine(
        m.b - tickDir * tickLen,
        m.b + tickDir * tickLen,
        measurePaint,
      );

      final labelText =
          '${m.distance.toStringAsFixed(m.distance >= 10 ? 0 : 1)} px';
      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: palette.text,
            fontSize: 11.0 / viewport.zoom,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final pad = 3.0 / viewport.zoom;
      final center = Offset((m.a.dx + m.b.dx) / 2, (m.a.dy + m.b.dy) / 2);
      final labelRect = Rect.fromCenter(
        center: center,
        width: tp.width + pad * 2,
        height: tp.height + pad * 2,
      );

      final bgPaint = Paint()..color = palette.danger;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          labelRect,
          Radius.circular(3.0 / viewport.zoom),
        ),
        bgPaint,
      );
      tp.paint(canvas, Offset(labelRect.left + pad, labelRect.top + pad));
    }
  }

  void _paintSelectionHighlights(Canvas canvas) {
    final palette = renderTokens ?? CanvasRenderTokens.dark;
    for (final node in nodes) {
      if (!selectedNodeIds.contains(node.id) || !node.visible) continue;

      canvas.save();
      canvas.translate(node.x, node.y);
      if (node.rotation != 0.0) {
        canvas.translate(node.width / 2, node.height / 2);
        canvas.rotate(node.rotation);
        canvas.translate(-node.width / 2, -node.height / 2);
      }

      final outlinePaint = Paint()
        ..color = palette.selection
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / viewport.zoom;

      final double handleRadius = 4.0 / viewport.zoom;
      final handleFill = Paint()
        ..color = palette.handle
        ..style = PaintingStyle.fill;
      final handleStroke = Paint()
        ..color = palette.selection
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 / viewport.zoom;

      if (showRotationHandle && selectedNodeIds.length == 1) {
        _paintRotationHandle(canvas, node, palette);
      }

      if (node.type == NodeType.vectorPath &&
          node.payload is VectorPathPayload) {
        final vp = node.payload as VectorPathPayload;
        if (vp.points.isNotEmpty) {
          final path = vp.toPath();

          final vectorGlow = Paint()
            ..color = palette.selection.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(6.0, vp.strokeWidth + 6.0 / viewport.zoom)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;
          canvas.drawPath(path, vectorGlow);

          final handleLinePaint = Paint()
            ..color = palette.textMuted
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0 / viewport.zoom;
          final handleDotFill = Paint()
            ..color = palette.warning
            ..style = PaintingStyle.fill;
          final handleDotStroke = Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0 / viewport.zoom;

          for (final bp in vp.points) {
            if (bp.handleIn != Offset.zero) {
              final inPos = bp.point + bp.handleIn;
              canvas.drawLine(bp.point, inPos, handleLinePaint);
              canvas.drawCircle(inPos, 3.2 / viewport.zoom, handleDotFill);
              canvas.drawCircle(inPos, 3.2 / viewport.zoom, handleDotStroke);
            }
            if (bp.handleOut != Offset.zero) {
              final outPos = bp.point + bp.handleOut;
              canvas.drawLine(bp.point, outPos, handleLinePaint);
              canvas.drawCircle(outPos, 3.2 / viewport.zoom, handleDotFill);
              canvas.drawCircle(outPos, 3.2 / viewport.zoom, handleDotStroke);
            }

            // Draw vertex anchor (blue with white inner dot or square for sharp corners)
            if (bp.type == PointType.corner) {
              final rect = Rect.fromCenter(
                center: bp.point,
                width: handleRadius * 2,
                height: handleRadius * 2,
              );
              canvas.drawRect(rect, handleFill);
              canvas.drawRect(rect, handleStroke);
            } else {
              canvas.drawCircle(bp.point, handleRadius, handleFill);
              canvas.drawCircle(bp.point, handleRadius, handleStroke);
            }
          }
        }

        canvas.restore();
        continue;
      }

      if (node.type == NodeType.drawing && node.payload is DrawingPayload) {
        final dp = node.payload as DrawingPayload;
        if (dp.points.isNotEmpty) {
          final strokePath = dp.isSmoothed
              ? BrushPathSmoother.buildSmoothPath(dp.points)
              : BrushPathSmoother.buildLinearPath(dp.points);

          final strokeGlow = Paint()
            ..color = palette.selection.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(6.0, dp.strokeWidth + 6.0 / viewport.zoom)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;

          canvas.drawPath(strokePath, strokeGlow);

          final pStart = dp.points.first;
          final pEnd = dp.points.last;

          canvas.drawCircle(pStart, handleRadius, handleFill);
          canvas.drawCircle(pStart, handleRadius, handleStroke);
          canvas.drawCircle(pEnd, handleRadius, handleFill);
          canvas.drawCircle(pEnd, handleRadius, handleStroke);

          for (final idx in dp.controlPointIndices) {
            if (idx >= 0 && idx < dp.points.length) {
              final pt = dp.points[idx];
              final cpFill = Paint()
                ..color = const Color(0xFFF97316)
                ..style = PaintingStyle.fill;
              final cpStroke = Paint()
                ..color = Colors.white
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5 / viewport.zoom;
              canvas.drawCircle(pt, handleRadius * 1.1, cpFill);
              canvas.drawCircle(pt, handleRadius * 1.1, cpStroke);
            }
          }
        }

        canvas.restore();
        continue;
      }

      if (node.type == NodeType.line || node.type == NodeType.arrow) {
        final p = node.payload is ShapePayload
            ? node.payload as ShapePayload
            : null;
        final sx = p != null ? p.startXRatio : 0.0;
        final sy = p != null ? p.startYRatio : 0.0;
        final ex = p != null ? p.endXRatio : 1.0;
        final ey = p != null ? p.endYRatio : 1.0;
        final pStart = Offset(sx * node.width, sy * node.height);
        final pEnd = Offset(ex * node.width, ey * node.height);

        final linePath = Path();
        Offset? curveHandlePt;
        if (p?.lineRouting == LineRouting.orthogonal) {
          final midX = (pStart.dx + pEnd.dx) / 2;
          linePath.moveTo(pStart.dx, pStart.dy);
          linePath.lineTo(midX, pStart.dy);
          linePath.lineTo(midX, pEnd.dy);
          linePath.lineTo(pEnd.dx, pEnd.dy);
        } else if (p?.lineRouting == LineRouting.curved) {
          final midX = (pStart.dx + pEnd.dx) / 2;
          final midY = (pStart.dy + pEnd.dy) / 2;
          final dx = pEnd.dx - pStart.dx;
          final dy = pEnd.dy - pStart.dy;
          final depth = p?.curveDepth ?? 0.25;
          final perpX = -dy * depth;
          final perpY = dx * depth;
          curveHandlePt = Offset(midX + perpX, midY + perpY);
          linePath.moveTo(pStart.dx, pStart.dy);
          linePath.quadraticBezierTo(
            curveHandlePt.dx,
            curveHandlePt.dy,
            pEnd.dx,
            pEnd.dy,
          );
        } else {
          linePath.moveTo(pStart.dx, pStart.dy);
          linePath.lineTo(pEnd.dx, pEnd.dy);
        }

        final lineSelectionGlow = Paint()
          ..color = const Color(0xFF3B82F6).withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth =
              max(6.0, (p?.strokeWidth ?? 2.0) + 6.0) / viewport.zoom
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        canvas.drawPath(linePath, lineSelectionGlow);

        canvas.drawCircle(pStart, handleRadius, handleFill);
        canvas.drawCircle(pStart, handleRadius, handleStroke);
        canvas.drawCircle(pEnd, handleRadius, handleFill);
        canvas.drawCircle(pEnd, handleRadius, handleStroke);

        if (curveHandlePt != null) {
          final curveHandleFill = Paint()
            ..color = const Color(0xFFF97316)
            ..style = PaintingStyle.fill;
          final curveHandleInner = Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill;
          canvas.drawCircle(
            curveHandlePt,
            4.5 / viewport.zoom,
            curveHandleFill,
          );
          canvas.drawCircle(
            curveHandlePt,
            2.0 / viewport.zoom,
            curveHandleInner,
          );
        }

        canvas.restore();
        continue;
      }

      final rect = Rect.fromLTWH(0, 0, node.width, node.height);
      canvas.drawRect(rect, outlinePaint);

      final handles = [
        rect.topLeft,
        rect.topCenter,
        rect.topRight,
        rect.centerRight,
        rect.bottomRight,
        rect.bottomCenter,
        rect.bottomLeft,
        rect.centerLeft,
      ];

      for (final h in handles) {
        canvas.drawCircle(h, handleRadius, handleFill);
        canvas.drawCircle(h, handleRadius, handleStroke);
      }

      // Figma-style interactive corner radius handle (inner circle)
      final shapePayload = node.payload is ShapePayload
          ? node.payload as ShapePayload
          : null;
      final diagramDefinition = shapePayload == null
          ? null
          : DiagramShapeCatalog.resolve(
              shapePayload.diagramShapeId ?? 'rectangle',
            );
      final cornerHandle = diagramDefinition?.cornerRadiusHandlePosition(
        Size(node.width, node.height),
        shapePayload?.cornerRadius ?? 0.0,
      );
      if (cornerHandle != null) {
        final cornerFill = Paint()
          ..color = const Color(0xFF3B82F6)
          ..style = PaintingStyle.fill;
        final cornerInner = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;

        canvas.drawCircle(cornerHandle, 3.5 / viewport.zoom, cornerFill);
        canvas.drawCircle(cornerHandle, 1.8 / viewport.zoom, cornerInner);
      }

      if (node.type == NodeType.ellipse && node.payload is ShapePayload) {
        final payload = node.payload as ShapePayload;
        Offset polar(double angle, double ratio) {
          final radians = (angle - 90.0) * pi / 180.0;
          return Offset(
            rect.center.dx + cos(radians) * rect.width / 2 * ratio,
            rect.center.dy + sin(radians) * rect.height / 2 * ratio,
          );
        }

        final arcHandles = [
          polar(payload.startAngle, 1.0),
          polar(payload.startAngle + payload.sweepAngle, 1.0),
          polar(
            payload.startAngle + payload.sweepAngle / 2,
            payload.innerRadiusRatio,
          ),
        ];
        final arcColors = [
          const Color(0xFFF97316),
          const Color(0xFFF97316),
          const Color(0xFF3B82F6),
        ];
        for (var i = 0; i < arcHandles.length; i++) {
          canvas.drawCircle(
            arcHandles[i],
            4.0 / viewport.zoom,
            Paint()..color = arcColors[i],
          );
          canvas.drawCircle(
            arcHandles[i],
            1.8 / viewport.zoom,
            Paint()..color = Colors.white,
          );
        }
      } else if (node.type == NodeType.parallelogram &&
          node.payload is ShapePayload) {
        final payload = node.payload as ShapePayload;
        final skewOffset = (payload.skewRatio * node.width).clamp(
          -node.width * 0.48,
          node.width * 0.48,
        );
        final baseTopLeftX = skewOffset >= 0 ? skewOffset : 0.0;
        final skewHandlePos = Offset(baseTopLeftX, 0);

        final skewFill = Paint()
          ..color = const Color(0xFF10B981)
          ..style = PaintingStyle.fill;
        final skewInner = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;

        canvas.drawCircle(skewHandlePos, 4.0 / viewport.zoom, skewFill);
        canvas.drawCircle(skewHandlePos, 1.8 / viewport.zoom, skewInner);
      }

      canvas.restore();
    }
  }

  void _paintRotationHandle(
    Canvas canvas,
    CanvasNode node,
    CanvasRenderTokens palette,
  ) {
    final safeZoom = viewport.zoom.isFinite && viewport.zoom > 0
        ? viewport.zoom
        : 1.0;
    final handleDistance =
        CanvasSelectionGeometry.rotationHandleDistance / safeZoom;
    final handleCenter = Offset(node.width / 2, -handleDistance);
    final topCenter = Offset(node.width / 2, 0);
    final handleRadius = 7.0 / safeZoom;
    final stemPaint = Paint()
      ..color = palette.selection
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / safeZoom;
    final fillPaint = Paint()
      ..color = palette.handle
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = palette.selection
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / safeZoom;
    final iconPaint = Paint()
      ..color = palette.selection
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 / safeZoom
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      topCenter,
      handleCenter + Offset(0, handleRadius),
      stemPaint,
    );
    canvas.drawCircle(handleCenter, handleRadius, fillPaint);
    canvas.drawCircle(handleCenter, handleRadius, borderPaint);

    final iconRadius = 3.4 / safeZoom;
    final iconRect = Rect.fromCircle(center: handleCenter, radius: iconRadius);
    const startAngle = -math.pi * 0.85;
    const sweepAngle = math.pi * 1.45;
    canvas.drawArc(iconRect, startAngle, sweepAngle, false, iconPaint);
    const arrowAngle = startAngle + sweepAngle;
    final arrowTip = Offset(
      handleCenter.dx + math.cos(arrowAngle) * iconRadius,
      handleCenter.dy + math.sin(arrowAngle) * iconRadius,
    );
    final tangent = Offset(-math.sin(arrowAngle), math.cos(arrowAngle));
    final arrowPath = Path()
      ..moveTo(arrowTip.dx, arrowTip.dy)
      ..lineTo(
        arrowTip.dx - tangent.dx * 2.4 / safeZoom,
        arrowTip.dy - tangent.dy * 2.4 / safeZoom,
      )
      ..lineTo(
        arrowTip.dx -
            tangent.dx * 2.4 / safeZoom -
            math.cos(arrowAngle) * 2.4 / safeZoom,
        arrowTip.dy -
            tangent.dy * 2.4 / safeZoom -
            math.sin(arrowAngle) * 2.4 / safeZoom,
      );
    canvas.drawPath(arrowPath, iconPaint);
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges ||
        oldDelegate.cursors != cursors ||
        oldDelegate.viewport != viewport ||
        oldDelegate.selectedNodeIds != selectedNodeIds ||
        oldDelegate.selectionMarquee != selectionMarquee ||
        oldDelegate.snapGuides != snapGuides ||
        oldDelegate.measurements != measurements ||
        oldDelegate.activeBrushStroke != activeBrushStroke ||
        oldDelegate.activeBrushType != activeBrushType ||
        oldDelegate.activeBrushColor != activeBrushColor ||
        oldDelegate.activeBrushWidth != activeBrushWidth ||
        oldDelegate.activeBrushOpacity != activeBrushOpacity ||
        oldDelegate.activeBrushSmooth != activeBrushSmooth ||
        oldDelegate.activeCreationTool != activeCreationTool ||
        oldDelegate.activeDiagramShapeId != activeDiagramShapeId ||
        oldDelegate.creationPreviewRect != creationPreviewRect ||
        oldDelegate.creationPreviewLine != creationPreviewLine ||
        oldDelegate.connectorPreview != connectorPreview ||
        oldDelegate.connectorEditPreview != connectorEditPreview ||
        oldDelegate.connectorSnapNodeId != connectorSnapNodeId ||
        oldDelegate.connectorSnapPoint != connectorSnapPoint ||
        oldDelegate.activePenPoints != activePenPoints ||
        oldDelegate.penHoverPosition != penHoverPosition ||
        oldDelegate.brushCursorPosition != brushCursorPosition ||
        oldDelegate.renderTokens != renderTokens ||
        oldDelegate.renderEdges != renderEdges ||
        oldDelegate.renderNodes != renderNodes ||
        oldDelegate.renderForeground != renderForeground ||
        oldDelegate.showRotationHandle != showRotationHandle;
  }
}
