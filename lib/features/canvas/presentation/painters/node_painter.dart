import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'grid_painter.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/domain/models/design_tokens.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/drawing_payload.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_persistence.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_renderer.dart';
import 'package:varian/domain/models/rich_text.dart';
import 'package:varian/domain/models/table_formula.dart';
import 'package:varian/domain/models/vector_path_payload.dart';
import 'package:varian/features/diagrams/domain/diagram_shape_catalog.dart';
import 'package:varian/features/charts/presentation/chart_canvas_painter.dart';
import 'package:varian/features/canvas/domain/text_on_path.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import '../../utils/brush_path_smoother.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';

class NodePainter {
  static final Expando<Map<String, String>> _workspacePreviewReferences =
      Expando<Map<String, String>>();

  static String _workspacePreviewReference(
    DrawingPaperPayload payload,
    String nodeId,
  ) {
    final references = _workspacePreviewReferences[payload] ??=
        <String, String>{};
    return references[nodeId] ??=
        DrawingPaperPersistence.previewReferenceForPayload(
          payload,
          nodeId: nodeId,
        );
  }

  static void paint(
    Canvas canvas,
    CanvasNode node, {
    CanvasRenderTokens renderTokens = CanvasRenderTokens.dark,
    CanvasNode? textPathNode,
    DesignTokenSet? designTokens,
    CanvasImageCache? imageCache,
  }) {
    final cache = imageCache ?? CanvasImageCache.instance;
    if (!node.visible) return;

    canvas.save();
    canvas.translate(node.x, node.y);
    if (node.rotation != 0.0) {
      canvas.translate(node.width / 2, node.height / 2);
      canvas.rotate(node.rotation);
      canvas.translate(-node.width / 2, -node.height / 2);
    }

    final double effectiveOpacity = node.opacity.clamp(0.0, 1.0);
    if (effectiveOpacity < 1.0) {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, node.width, node.height),
        Paint()..color = Color.fromRGBO(255, 255, 255, effectiveOpacity),
      );
    }

    switch (node.type) {
      case NodeType.rectangle:
        _paintRectangle(canvas, node);
        break;
      case NodeType.ellipse:
        _paintEllipse(canvas, node);
        break;
      case NodeType.line:
        _paintLine(canvas, node);
        break;
      case NodeType.arrow:
        _paintArrow(canvas, node);
        break;
      case NodeType.stickyNote:
        _paintStickyNote(canvas, node);
        break;
      case NodeType.text:
        _paintText(canvas, node, textPathNode: textPathNode);
        break;
      case NodeType.frame:
        _paintFrame(canvas, node);
        break;
      case NodeType.diamond:
        _paintDiamond(canvas, node);
        break;
      case NodeType.cylinder:
        _paintCylinder(canvas, node);
        break;
      case NodeType.parallelogram:
        _paintParallelogram(canvas, node);
        break;
      case NodeType.drawing:
        _paintDrawing(canvas, node);
        break;
      case NodeType.vectorPath:
        _paintVectorPath(canvas, node);
        break;
      case NodeType.component:
        _paintComponent(
          canvas,
          node,
          designTokens: designTokens,
          renderTokens: renderTokens,
        );
        break;
      case NodeType.drawingPaper:
        _paintDrawingPaper(canvas, node, imageCache: cache);
        break;
      case NodeType.group:
        _paintGroup(canvas, node);
        break;
      case NodeType.image:
        _paintImage(canvas, node, imageCache: cache);
        break;
      case NodeType.fileCard:
        _paintFileCard(canvas, node);
        break;
      case NodeType.model3d:
        _paintModel3D(canvas, node);
        break;
      case NodeType.linkCard:
        _paintLinkCard(canvas, node);
        break;
      case NodeType.videoCard:
        _paintVideoCard(canvas, node, imageCache: cache);
        break;
      case NodeType.audioCard:
        _paintAudioCard(canvas, node);
        break;
      case NodeType.mapCard:
        _paintMapCard(canvas, node);
        break;
      case NodeType.colorSwatch:
        _paintColorSwatch(canvas, node);
        break;
      case NodeType.sketchCard:
        _paintSketchCard(canvas, node);
        break;
      case NodeType.annotatedImage:
        _paintAnnotatedImage(canvas, node);
        break;
      case NodeType.columnContainer:
        _paintColumnContainer(canvas, node);
        break;
      case NodeType.nestedBoard:
        _paintNestedBoard(canvas, node);
        break;
      case NodeType.tableGrid:
        _paintTableGrid(canvas, node);
        break;
      case NodeType.todoList:
        _paintTodoList(canvas, node);
        break;
      case NodeType.chart:
        ChartCanvasPainter.paint(
          canvas,
          node,
          node.payload is ChartPayload
              ? node.payload as ChartPayload
              : ChartPayload(),
          tokens: renderTokens,
        );
        break;
      case NodeType.document:
        _paintDocument(canvas, node);
        break;
      case NodeType.embed:
        _paintEmbed(canvas, node);
        break;
      case NodeType.mermaid:
        _paintMermaid(canvas, node);
        break;
    }

    // Paint universal node pins if present (on any node type)
    if (node.pins.isNotEmpty) {
      _paintNodeAnnotationPins(canvas, node, renderTokens);
    }

    if (effectiveOpacity < 1.0) {
      canvas.restore();
    }
    canvas.restore();
  }

  static void _paintNodeAnnotationPins(
    Canvas canvas,
    CanvasNode node,
    CanvasRenderTokens renderTokens,
  ) {
    // Top-Right Corner Pin Badge Indicator placed outside top-right corner
    final unresolvedCount = node.pins.where((p) => !p.isResolved).length;
    final badgeColor = unresolvedCount > 0
        ? renderTokens.warning
        : renderTokens.success;
    final badgeWidth = unresolvedCount > 9 ? 48.0 : 40.0;
    const badgeHeight = 22.0;
    final badgeRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        node.width - badgeWidth,
        -badgeHeight - 6,
        badgeWidth,
        badgeHeight,
      ),
      topLeft: const Radius.circular(11),
      topRight: const Radius.circular(11),
      bottomLeft: const Radius.circular(11),
      bottomRight: const Radius.circular(11),
    );

    // Subtle drop shadow for outside badge
    canvas.drawRRect(
      badgeRect.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.drawRRect(badgeRect, Paint()..color = badgeColor);
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final badgeText = unresolvedCount > 0 ? '📌 $unresolvedCount' : '✓ All';
    final badgeSpan = TextSpan(
      text: badgeText,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
    final badgePainter = TextPainter(
      text: badgeSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    badgePainter.paint(
      canvas,
      Offset(
        (node.width - badgeWidth) + (badgeWidth - badgePainter.width) / 2,
        -badgeHeight - 6 + (badgeHeight - badgePainter.height) / 2,
      ),
    );

    // Render pin markers and tooltips placed outside the right edge of the node
    for (int i = 0; i < node.pins.length; i++) {
      final pin = node.pins[i];
      final targetPoint = pin.position;

      Color markerColor = pin.color;
      if (pin.isResolved) {
        markerColor = const Color(0xFF10B981);
      } else if (pin.status == AnnotationPinStatus.issue) {
        markerColor = const Color(0xFFEF4444);
      } else if (pin.status == AnnotationPinStatus.inProgress) {
        markerColor = const Color(0xFFF59E0B);
      }

      // Pin badge position on the outside right margin of the item
      final pinBadgeCenter = Offset(
        node.width + 16.0,
        (targetPoint.dy).clamp(12.0, node.height - 12.0),
      );

      // 1. Small dot target on the exact clicked position inside the item
      canvas.drawCircle(targetPoint, 3.5, Paint()..color = markerColor);
      canvas.drawCircle(
        targetPoint,
        3.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      // 2. Leader connection line from target point to outside pin badge
      final leaderPaint = Paint()
        ..color = markerColor.withValues(alpha: 0.65)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      final leaderPath = Path()
        ..moveTo(targetPoint.dx, targetPoint.dy)
        ..cubicTo(
          targetPoint.dx + (pinBadgeCenter.dx - targetPoint.dx) * 0.5,
          targetPoint.dy,
          pinBadgeCenter.dx - 10,
          pinBadgeCenter.dy,
          pinBadgeCenter.dx - 12,
          pinBadgeCenter.dy,
        );
      canvas.drawPath(leaderPath, leaderPaint);

      // 3. Shadow for outside pin badge
      canvas.drawCircle(
        pinBadgeCenter.translate(0, 2),
        12,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );

      // 4. Pin Pinhead outside
      canvas.drawCircle(pinBadgeCenter, 12, Paint()..color = markerColor);
      canvas.drawCircle(
        pinBadgeCenter,
        12,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );

      // 5. Pin number / check icon
      final pinLabel = pin.isResolved ? '✓' : '${i + 1}';
      final numSpan = TextSpan(
        text: pinLabel,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      );
      final numPainter = TextPainter(
        text: numSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      numPainter.paint(
        canvas,
        Offset(
          pinBadgeCenter.dx - numPainter.width / 2,
          pinBadgeCenter.dy - numPainter.height / 2,
        ),
      );

      // 6. Comment bubble beside the outside pin badge
      if (pin.text.trim().isNotEmpty) {
        final commentText = pin.text.trim();
        final tooltipSpan = TextSpan(
          text: commentText.length > 20
              ? '${commentText.substring(0, 18)}...'
              : commentText,
          style: TextStyle(
            color: pin.isResolved ? const Color(0xFF94A3B8) : Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w500,
            decoration: pin.isResolved ? TextDecoration.lineThrough : null,
          ),
        );
        final tooltipPainter = TextPainter(
          text: tooltipSpan,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 140);
        final tooltipWidth = tooltipPainter.width + 12;
        const tooltipHeight = 20.0;

        final tooltipX = pinBadgeCenter.dx + 16.0;
        final tooltipY = pinBadgeCenter.dy - tooltipHeight / 2;

        final bubbleRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(tooltipX, tooltipY, tooltipWidth, tooltipHeight),
          const Radius.circular(4),
        );
        canvas.drawRRect(
          bubbleRect.shift(const Offset(0, 2)),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawRRect(
          bubbleRect,
          Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.95),
        );
        canvas.drawRRect(
          bubbleRect,
          Paint()
            ..color = markerColor.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
        tooltipPainter.paint(
          canvas,
          Offset(
            tooltipX + 6,
            tooltipY + (tooltipHeight - tooltipPainter.height) / 2,
          ),
        );
      }
    }
  }

  static void _paintVectorPath(Canvas canvas, CanvasNode node) {
    final payload = node.payload as VectorPathPayload;
    final subpaths = payload.allSubpaths;
    if (subpaths.isEmpty) return;

    final path = payload.toPath();
    final fillPath = payload.toPath(closeOpenSubpaths: true);
    final innerEffects = <VectorEffect>[];
    for (final effect in payload.effects) {
      if (!effect.enabled) continue;
      if (effect.type == VectorEffectType.innerShadow) {
        innerEffects.add(effect);
        continue;
      }
      final effectPaint = Paint()..style = PaintingStyle.fill;
      switch (effect.type) {
        case VectorEffectType.dropShadow:
          effectPaint.color = effect.color;
          if (effect.blurRadius > 0) {
            effectPaint.maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              effect.blurRadius,
            );
          }
          canvas.drawPath(fillPath.shift(effect.offset), effectPaint);
        case VectorEffectType.blur:
          canvas.saveLayer(
            Rect.fromLTWH(0, 0, node.width, node.height),
            Paint()
              ..imageFilter = ui.ImageFilter.blur(
                sigmaX: effect.blurRadius,
                sigmaY: effect.blurRadius,
              ),
          );
          canvas.drawPath(fillPath, effectPaint..color = Colors.white);
          canvas.restore();
        case VectorEffectType.outline:
          canvas.drawPath(
            path,
            Paint()
              ..color = effect.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = effect.spread.clamp(1.0, 1000.0),
          );
        case VectorEffectType.innerShadow:
          break;
      }
    }
    if (payload.allSubpaths.isNotEmpty) {
      final fillPaint = Paint()..style = PaintingStyle.fill;
      if (payload.isGradientFill) {
        final colors = [payload.fill, payload.gradientEndColor];
        fillPaint.shader = switch (payload.gradientType) {
          FillType.radialGradient => RadialGradient(
            colors: colors,
          ).createShader(Rect.fromLTWH(0, 0, node.width, node.height)),
          FillType.angularGradient => SweepGradient(
            colors: colors,
          ).createShader(Rect.fromLTWH(0, 0, node.width, node.height)),
          _ => LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ).createShader(Rect.fromLTWH(0, 0, node.width, node.height)),
        };
      } else {
        fillPaint.color = payload.fill;
      }
      canvas.drawPath(fillPath, fillPaint);
    }

    if (payload.strokeWidth > 0) {
      final strokePaint = Paint()
        ..color = payload.stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = payload.strokeWidth
        ..strokeCap = payload.strokeCap == VectorStrokeCap.butt
            ? StrokeCap.butt
            : (payload.strokeCap == VectorStrokeCap.square
                  ? StrokeCap.square
                  : StrokeCap.round)
        ..strokeJoin = payload.strokeJoin == VectorStrokeJoin.miter
            ? StrokeJoin.miter
            : (payload.strokeJoin == VectorStrokeJoin.bevel
                  ? StrokeJoin.bevel
                  : StrokeJoin.round);

      if (payload.dashPattern.length >= 2) {
        final dashPath = Path();
        final metrics = path.computeMetrics();
        final dashOn = payload.dashPattern[0];
        final dashOff = payload.dashPattern[1];
        if (dashOn > 0 && dashOff > 0) {
          final cycle = dashOn + dashOff;
          var phase = payload.dashOffset % cycle;
          if (phase < 0) phase += cycle;
          var phaseIndex = 0;
          while (phase >= (phaseIndex == 0 ? dashOn : dashOff)) {
            phase -= phaseIndex == 0 ? dashOn : dashOff;
            phaseIndex = 1 - phaseIndex;
          }
          for (final metric in metrics) {
            double distance = 0.0;
            var patternIndex = phaseIndex;
            var remaining = (patternIndex == 0 ? dashOn : dashOff) - phase;
            while (distance < metric.length) {
              final length = min(remaining, metric.length - distance);
              if (patternIndex == 0 && length > 0) {
                dashPath.addPath(
                  metric.extractPath(distance, distance + length),
                  Offset.zero,
                );
              }
              distance += length;
              patternIndex = 1 - patternIndex;
              remaining = patternIndex == 0 ? dashOn : dashOff;
            }
          }
          canvas.drawPath(dashPath, strokePaint);
        } else {
          canvas.drawPath(path, strokePaint);
        }
      } else {
        canvas.drawPath(path, strokePaint);
      }
    }

    for (final effect in innerEffects) {
      _paintInnerShadow(canvas, fillPath, node, effect);
    }
  }

  static void _paintInnerShadow(
    Canvas canvas,
    Path fillPath,
    CanvasNode node,
    VectorEffect effect,
  ) {
    final blurRadius = effect.blurRadius.clamp(0.0, 1000.0).toDouble();
    final spread = max(0.0, effect.spread);
    if (effect.color.a == 0.0 ||
        (blurRadius == 0.0 && spread == 0.0 && effect.offset == Offset.zero)) {
      return;
    }

    final padding =
        blurRadius * 3.0 +
        max(effect.offset.dx.abs(), effect.offset.dy.abs()) +
        spread +
        4.0;
    final layerBounds = Rect.fromLTWH(
      -padding,
      -padding,
      node.width + padding * 2.0,
      node.height + padding * 2.0,
    );

    final shadowPaint = Paint()
      ..color = effect.color
      ..style = PaintingStyle.fill;
    if (blurRadius > 0.0) {
      shadowPaint.maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius);
    }

    final erasePaint = Paint()
      ..color = Colors.white
      ..blendMode = BlendMode.dstOut
      ..style = PaintingStyle.fill;
    if (blurRadius > 0.0) {
      erasePaint.maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius);
    }

    canvas.saveLayer(layerBounds, Paint());
    _drawSpreadPath(canvas, fillPath, shadowPaint, spread);
    _drawSpreadPath(canvas, fillPath.shift(effect.offset), erasePaint, spread);
    canvas.restore();
  }

  static void _drawSpreadPath(
    Canvas canvas,
    Path path,
    Paint paint,
    double spread,
  ) {
    canvas.drawPath(path, paint);
    if (spread <= 0.0) return;
    final outlinePaint = Paint()
      ..color = paint.color
      ..blendMode = paint.blendMode
      ..style = PaintingStyle.stroke
      ..strokeWidth = spread * 2.0
      ..maskFilter = paint.maskFilter;
    canvas.drawPath(path, outlinePaint);
  }

  static void _paintComponent(
    Canvas canvas,
    CanvasNode node, {
    DesignTokenSet? designTokens,
    CanvasRenderTokens renderTokens = CanvasRenderTokens.dark,
  }) {
    final payload = node.payload is ComponentPayload
        ? node.payload as ComponentPayload
        : ComponentPayload(
            masterComponentId: node.id,
            componentName: node.name ?? 'Component',
          );
    final resolvedBackground = _resolveComponentColor(
      payload,
      'backgroundColor',
      designTokens,
    );
    final resolvedBorder = _resolveComponentColor(
      payload,
      'borderColor',
      designTokens,
    );
    final resolvedTheme = _resolveComponentColor(
      payload,
      'themeColor',
      designTokens,
    );
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(payload.cornerRadius),
    );

    // Figma Purple glow & background
    final bgPaint = Paint()
      ..color = (resolvedBackground ?? payload.backgroundColor).withValues(
        alpha: 0.92,
      )
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    // Component Border: Purple for Master ❖, Blue for Instance ◇
    final borderColor =
        resolvedBorder ??
        resolvedTheme ??
        (payload.isMaster ? const Color(0xFF9333EA) : const Color(0xFF38BDF8));
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = payload.borderWidth > 0 ? payload.borderWidth : 1.5;
    canvas.drawRRect(rrect, borderPaint);

    // Header Badge with Figma-style Symbol: ❖ (Master) vs ◇ (Instance)
    if (payload.showBadge) {
      final badgeBg = RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, min(node.width, 140.0), 22),
        topLeft: Radius.circular(payload.cornerRadius),
        bottomRight: const Radius.circular(6),
      );
      canvas.drawRRect(
        badgeBg,
        Paint()..color = borderColor.withValues(alpha: 0.25),
      );

      final badgeSymbol = payload.isMaster ? '❖' : '◇';
      final badgeSpan = TextSpan(
        children: [
          TextSpan(
            text: '$badgeSymbol ',
            style: TextStyle(
              color: borderColor,
              fontSize: 11.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: payload.componentName,
            style: TextStyle(
              color: payload.isMaster
                  ? const Color(0xFFE9D5FF)
                  : const Color(0xFFBAE6FD),
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
      final badgePainter = TextPainter(
        text: badgeSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '..',
      )..layout(maxWidth: max(10, node.width - 12));
      badgePainter.paint(canvas, const Offset(6, 4));
    }

    // Render actual graphics of template children shapes & text (Figma-engine render)
    if (payload.templateChildren.isNotEmpty) {
      canvas.save();
      // Clip to component bounding box to prevent visual overflow
      canvas.clipRRect(rrect);

      for (final child in payload.templateChildren) {
        if (!child.visible) continue;

        final effectiveChild = _resolveComponentChild(
          child,
          payload,
          designTokens: designTokens,
        );

        canvas.save();
        canvas.translate(effectiveChild.x, effectiveChild.y);
        _paintChildShape(
          canvas,
          effectiveChild,
          designTokens: designTokens,
          renderTokens: renderTokens,
        );
        canvas.restore();
      }

      for (final slot in payload.slots) {
        final slotChildren = payload.resolvedSlotChildren(slot.id);
        if (slotChildren.isEmpty) {
          if (payload.isMaster) _paintSlotPlaceholder(canvas, slot);
          continue;
        }
        for (final child in slotChildren) {
          if (!child.visible) continue;
          final effectiveChild = _resolveComponentChild(
            child,
            payload,
            designTokens: designTokens,
          );
          canvas.save();
          canvas.clipRect(
            Rect.fromLTWH(slot.x, slot.y, slot.width, slot.height),
          );
          canvas.translate(
            slot.x + effectiveChild.x,
            slot.y + effectiveChild.y,
          );
          _paintChildShape(
            canvas,
            effectiveChild,
            designTokens: designTokens,
            renderTokens: renderTokens,
          );
          canvas.restore();
        }
      }

      canvas.restore();
    } else {
      // Show Props or Default content
      final propKeys = payload.propertyValues.keys.toList();
      if (propKeys.isNotEmpty) {
        for (int i = 0; i < min(propKeys.length, 2); i++) {
          final k = propKeys[i];
          final v = payload.propertyValues[k];
          final propY = 32.0 + (i * 18.0);
          if (propY + 14 <= node.height) {
            final propSpan = TextSpan(
              text: '$k: $v',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 9.5,
                fontFamily: 'monospace',
              ),
            );
            final pp = TextPainter(
              text: propSpan,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: max(10, node.width - 20));
            pp.paint(canvas, Offset(12, propY));
          }
        }
      }
    }

    // Bottom subtitle hint
    if (node.height > 60) {
      final hintSpan = TextSpan(
        text: payload.isMaster
            ? 'Master Component • Double-click'
            : 'Instance (Linked) • Double-click',
        style: TextStyle(
          color: borderColor.withValues(alpha: 0.7),
          fontSize: 8.5,
          fontStyle: FontStyle.italic,
        ),
      );
      final hintPainter = TextPainter(
        text: hintSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      hintPainter.paint(canvas, Offset(10, max(20.0, node.height - 16)));
    }
  }

  static void _paintChildShape(
    Canvas canvas,
    CanvasNode node, {
    DesignTokenSet? designTokens,
    CanvasRenderTokens renderTokens = CanvasRenderTokens.dark,
  }) {
    switch (node.type) {
      case NodeType.rectangle:
        _paintRectangle(canvas, node);
        break;
      case NodeType.ellipse:
        _paintEllipse(canvas, node);
        break;
      case NodeType.diamond:
        _paintDiamond(canvas, node);
        break;
      case NodeType.cylinder:
        _paintCylinder(canvas, node);
        break;
      case NodeType.parallelogram:
        _paintParallelogram(canvas, node);
        break;
      case NodeType.text:
        _paintText(canvas, node);
        break;
      case NodeType.frame:
        _paintFrame(canvas, node);
        break;
      case NodeType.component:
        _paintComponent(
          canvas,
          node,
          designTokens: designTokens,
          renderTokens: renderTokens,
        );
        break;
      case NodeType.chart:
        ChartCanvasPainter.paint(
          canvas,
          node,
          node.payload is ChartPayload
              ? node.payload as ChartPayload
              : ChartPayload(),
          tokens: renderTokens,
        );
        break;
      default:
        final rect = Rect.fromLTWH(0, 0, node.width, node.height);
        canvas.drawRect(rect, Paint()..color = const Color(0xFF334155));
    }
  }

  static CanvasNode _resolveComponentChild(
    CanvasNode child,
    ComponentPayload component, {
    DesignTokenSet? designTokens,
  }) {
    var resolvedNode = child;
    final childPayload = child.payload;
    if (childPayload is TextPayload) {
      final targets = <String>{
        child.id.toLowerCase(),
        if (child.name != null) child.name!.toLowerCase(),
        'label',
        'text',
        'content',
      };
      for (final property in component.properties) {
        if (!targets.contains(property.id.toLowerCase()) &&
            !targets.contains(property.name.toLowerCase())) {
          continue;
        }
        final value = component.resolvedPropertyValue(
          property.id,
          designTokens: designTokens,
        );
        if (value != null) {
          resolvedNode = resolvedNode.copyWith(
            payload: childPayload.copyWith(text: value.toString()),
          );
        }
        break;
      }
      final color = _resolveComponentColor(
        component,
        '${child.id}.color',
        designTokens,
      );
      if (color != null && resolvedNode.payload is TextPayload) {
        resolvedNode = resolvedNode.copyWith(
          payload: (resolvedNode.payload as TextPayload).copyWith(color: color),
        );
      }
    } else if (childPayload is ShapePayload) {
      final fill = _resolveComponentColor(
        component,
        '${child.id}.fill',
        designTokens,
      );
      final stroke = _resolveComponentColor(
        component,
        '${child.id}.stroke',
        designTokens,
      );
      final label = component.resolvedTargetValue(
        '${child.id}.label',
        designTokens: designTokens,
      );
      final nextShape = childPayload.copyWith(
        fill: fill,
        stroke: stroke,
        label: label?.toString(),
      );
      resolvedNode = resolvedNode.copyWith(payload: nextShape);
    }

    final opacity = _resolveComponentNumber(
      component,
      '${child.id}.opacity',
      designTokens,
    );
    final visible = _resolveComponentBool(
      component,
      '${child.id}.visible',
      designTokens,
    );
    if (opacity != null || visible != null) {
      resolvedNode = resolvedNode.copyWith(
        opacity: opacity?.clamp(0.0, 1.0),
        visible: visible,
      );
    }
    return resolvedNode;
  }

  static Color? _resolveComponentColor(
    ComponentPayload component,
    String target,
    DesignTokenSet? designTokens,
  ) {
    final value = component.resolvedTargetValue(
      target,
      designTokens: designTokens,
    );
    return _colorFromValue(value);
  }

  static double? _resolveComponentNumber(
    ComponentPayload component,
    String target,
    DesignTokenSet? designTokens,
  ) {
    final value = component.resolvedTargetValue(
      target,
      designTokens: designTokens,
    );
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static bool? _resolveComponentBool(
    ComponentPayload component,
    String target,
    DesignTokenSet? designTokens,
  ) {
    final value = component.resolvedTargetValue(
      target,
      designTokens: designTokens,
    );
    if (value is bool) return value;
    if (value is String) {
      if (value.toLowerCase() == 'true') return true;
      if (value.toLowerCase() == 'false') return false;
    }
    return null;
  }

  static Color? _colorFromValue(Object? value) {
    if (value is Color) return value;
    if (value is num) return Color(value.toInt());
    if (value is! String) return null;
    var hex = value.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  static void _paintSlotPlaceholder(Canvas canvas, ComponentSlot slot) {
    final paint = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Rect.fromLTWH(slot.x, slot.y, slot.width, slot.height);
    canvas.drawRect(rect, paint);
    final labelPainter = TextPainter(
      text: TextSpan(
        text: slot.name,
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: max(10, slot.width - 8));
    labelPainter.paint(canvas, Offset(slot.x + 4, slot.y + 4));
  }

  static void _paintDrawing(Canvas canvas, CanvasNode node) {
    final payload = node.payload as DrawingPayload;
    if (payload.points.isEmpty) return;

    final paint = Paint()
      ..strokeWidth = payload.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    switch (payload.brushType) {
      case BrushType.ink:
        paint.color = payload.strokeColor.withValues(alpha: payload.opacity);
        break;
      case BrushType.marker:
        paint.color = payload.strokeColor.withValues(
          alpha: (payload.opacity * 0.55).clamp(0.0, 1.0),
        );
        paint.strokeCap = StrokeCap.square;
        break;
      case BrushType.airbrush:
        paint.color = payload.strokeColor.withValues(
          alpha: (payload.opacity * 0.4).clamp(0.0, 1.0),
        );
        paint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          payload.strokeWidth * 0.5,
        );
        break;
      case BrushType.highlighter:
        paint.color = payload.strokeColor.withValues(
          alpha: (payload.opacity * 0.4).clamp(0.0, 1.0),
        );
        paint.strokeCap = StrokeCap.square;
        paint.strokeWidth = payload.strokeWidth * 2.5;
        break;
      case BrushType.calligraphy:
        paint.color = payload.strokeColor.withValues(alpha: payload.opacity);
        paint.strokeCap = StrokeCap.butt;
        break;
      case BrushType.pencil:
        paint.color = payload.strokeColor.withValues(
          alpha: (payload.opacity * 0.7).clamp(0.0, 1.0),
        );
        paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.4);
        paint.strokeWidth = payload.strokeWidth * 0.8;
        break;
      case BrushType.eraser:
        return;
    }

    final path = payload.isSmoothed
        ? BrushPathSmoother.buildSmoothPath(payload.points)
        : BrushPathSmoother.buildLinearPath(payload.points);

    if (payload.cutouts.isNotEmpty) {
      // Paint with cutout masks subtracted
      canvas.saveLayer(
        Rect.fromLTWH(
          0,
          0,
          node.width,
          node.height,
        ).inflate(payload.strokeWidth * 2.0),
        Paint(),
      );

      if (payload.brushType == BrushType.calligraphy) {
        const ribbonOffset = Offset(1.5, 1.5);
        canvas.drawPath(path.shift(-ribbonOffset), paint);
        canvas.drawPath(path, paint);
        canvas.drawPath(path.shift(ribbonOffset), paint);
      } else {
        canvas.drawPath(path, paint);
      }

      final clearPaint = Paint()..blendMode = BlendMode.clear;
      for (final cut in payload.cutouts) {
        canvas.drawCircle(cut.position, cut.radius, clearPaint);
      }

      canvas.restore();
    } else {
      if (payload.brushType == BrushType.calligraphy) {
        canvas.save();
        const ribbonOffset = Offset(1.5, 1.5);
        canvas.drawPath(path.shift(-ribbonOffset), paint);
        canvas.drawPath(path, paint);
        canvas.drawPath(path.shift(ribbonOffset), paint);
        canvas.restore();
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  static bool _paintDiagramShape(
    Canvas canvas,
    CanvasNode node,
    ShapePayload payload,
  ) {
    final shapeId = payload.diagramShapeId;
    if (shapeId == null ||
        shapeId == 'rectangle' ||
        shapeId == 'roundedRectangle' ||
        shapeId == 'ellipse' ||
        shapeId == 'circle' ||
        shapeId == 'rhombus' ||
        shapeId == 'flowchart.decision' ||
        shapeId == 'mxgraph.bpmn.gateway' ||
        shapeId == 'cylinder' ||
        shapeId == 'database' ||
        shapeId == 'flowchart.storedData' ||
        shapeId == 'parallelogram' ||
        shapeId == 'flowchart.data') {
      return false;
    }

    final definition = DiagramShapeCatalog.resolve(shapeId);
    final path = definition.buildPath(
      Size(node.width, node.height),
      cornerRadius: payload.cornerRadius,
    );
    if (payload.hasShadow && payload.shadowBlur > 0) {
      canvas.drawPath(
        path.shift(Offset(payload.shadowOffsetX, payload.shadowOffsetY)),
        Paint()
          ..color = payload.shadowColor
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, payload.shadowBlur),
      );
    }

    final fill = payload.fill.withValues(
      alpha: (payload.fill.a * payload.fillOpacity).clamp(0.0, 1.0),
    );
    if (fill.a > 0) {
      final fillPaint = Paint()..color = fill;
      if (payload.fillType == FillType.linearGradient &&
          payload.fillGradientEnd != null) {
        fillPaint.shader = LinearGradient(
          colors: [fill, payload.fillGradientEnd!],
        ).createShader(Offset.zero & Size(node.width, node.height));
      }
      canvas.drawPath(path, fillPaint);
    }

    if (payload.strokeWidth > 0 && payload.stroke.a > 0) {
      final strokePaint = Paint()
        ..color = payload.stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = payload.strokeWidth
        ..strokeJoin = StrokeJoin.round;
      if (payload.strokeStyle == StrokeStyle.solid) {
        canvas.drawPath(path, strokePaint);
      } else {
        _drawDashedPath(
          canvas,
          path,
          strokePaint,
          dashWidth: payload.strokeStyle == StrokeStyle.dotted ? 2 : 6,
          dashSpace: payload.strokeStyle == StrokeStyle.dotted ? 3 : 4,
        );
      }
    }

    _paintShapeLabel(canvas, node, payload);
    return true;
  }

  static void _paintShapeLabel(
    Canvas canvas,
    CanvasNode node,
    ShapePayload payload,
  ) {
    if (payload.label.isEmpty) return;
    final textPainter = TextPainter(
      text: TextSpan(
        text: payload.label,
        style: TextStyle(
          color: payload.labelColor,
          fontSize: payload.labelFontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: max(0.0, node.width - 16.0));
    textPainter.paint(
      canvas,
      Offset(
        (node.width - textPainter.width) / 2,
        (node.height - textPainter.height) / 2,
      ),
    );
  }

  static void _paintRectangle(Canvas canvas, CanvasNode node) {
    final payload = node.payload as ShapePayload;
    if (_paintDiagramShape(canvas, node, payload)) return;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);

    final rrect = payload.independentCorners
        ? RRect.fromRectAndCorners(
            rect,
            topLeft: Radius.circular(payload.topLeftRadius),
            topRight: Radius.circular(payload.topRightRadius),
            bottomRight: Radius.circular(payload.bottomRightRadius),
            bottomLeft: Radius.circular(payload.bottomLeftRadius),
          )
        : RRect.fromRectAndRadius(rect, Radius.circular(payload.cornerRadius));

    // Drop Shadow
    if (payload.hasShadow && payload.shadowBlur > 0) {
      final shadowPaint = Paint()
        ..color = payload.shadowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, payload.shadowBlur);
      canvas.drawRRect(
        rrect.shift(Offset(payload.shadowOffsetX, payload.shadowOffsetY)),
        shadowPaint,
      );
    }

    // Fill (Solid, Linear Gradient, Radial Gradient) with Fill Opacity
    final effectiveFillColor = payload.fill.withValues(
      alpha: (payload.fill.a * payload.fillOpacity).clamp(0.0, 1.0),
    );
    final fillPaint = Paint()..style = PaintingStyle.fill;

    if (payload.fillType == FillType.linearGradient &&
        payload.fillGradientEnd != null) {
      final endColor = payload.fillGradientEnd!.withValues(
        alpha: (payload.fillGradientEnd!.a * payload.fillOpacity).clamp(
          0.0,
          1.0,
        ),
      );
      fillPaint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [effectiveFillColor, endColor],
      ).createShader(rect);
    } else if (payload.fillType == FillType.radialGradient &&
        payload.fillGradientEnd != null) {
      final endColor = payload.fillGradientEnd!.withValues(
        alpha: (payload.fillGradientEnd!.a * payload.fillOpacity).clamp(
          0.0,
          1.0,
        ),
      );
      fillPaint.shader = RadialGradient(
        center: Alignment.center,
        radius: 0.8,
        colors: [effectiveFillColor, endColor],
      ).createShader(rect);
    } else {
      fillPaint.color = effectiveFillColor;
    }
    canvas.drawRRect(rrect, fillPaint);

    // Stroke
    if (payload.strokeWidth > 0) {
      final strokePaint = Paint()
        ..color = payload.stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = payload.strokeWidth;

      if (payload.strokeStyle == StrokeStyle.dashed) {
        final path = Path()..addRRect(rrect);
        _drawDashedPath(canvas, path, strokePaint, dashWidth: 6, dashSpace: 4);
      } else if (payload.strokeStyle == StrokeStyle.dotted) {
        final path = Path()..addRRect(rrect);
        _drawDashedPath(canvas, path, strokePaint, dashWidth: 2, dashSpace: 3);
      } else {
        canvas.drawRRect(rrect, strokePaint);
      }
    }

    // Embedded Text Label (if present)
    if (payload.label.isNotEmpty) {
      final textSpan = TextSpan(
        text: payload.label,
        style: TextStyle(
          color: payload.labelColor,
          fontSize: payload.labelFontSize,
          fontWeight: FontWeight.w500,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: max(0.0, node.width - 16.0));

      final textOffset = Offset(
        (node.width - tp.width) / 2,
        (node.height - tp.height) / 2,
      );
      tp.paint(canvas, textOffset);
    }
  }

  static void _paintEllipse(Canvas canvas, CanvasNode node) {
    final payload = node.payload as ShapePayload;
    if (_paintDiagramShape(canvas, node, payload)) return;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final start = (payload.startAngle - 90.0) * pi / 180.0;
    final sweepDegrees = payload.sweepAngle.clamp(0.1, 360.0);
    final sweep = sweepDegrees * pi / 180.0;
    final innerRatio = payload.innerRadiusRatio.clamp(0.0, 0.99);
    final isFull = sweepDegrees >= 359.999;
    final path = Path();

    if (isFull && innerRatio == 0) {
      path.addOval(rect);
    } else if (innerRatio == 0) {
      path.moveTo(rect.center.dx, rect.center.dy);
      path.arcTo(rect, start, sweep, false);
      path.close();
    } else {
      final innerRect = Rect.fromCenter(
        center: rect.center,
        width: rect.width * innerRatio,
        height: rect.height * innerRatio,
      );
      path.arcTo(rect, start, sweep, true);
      final end = start + sweep;
      path.lineTo(
        innerRect.center.dx + cos(end) * innerRect.width / 2,
        innerRect.center.dy + sin(end) * innerRect.height / 2,
      );
      path.arcTo(innerRect, end, -sweep, false);
      path.close();
    }

    if (payload.hasShadow && payload.shadowBlur > 0) {
      final shadowPaint = Paint()
        ..color = payload.shadowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, payload.shadowBlur);
      canvas.drawPath(
        path.shift(Offset(payload.shadowOffsetX, payload.shadowOffsetY)),
        shadowPaint,
      );
    }

    final fillStart = payload.fill.withValues(
      alpha: (payload.fill.a * payload.fillOpacity).clamp(0.0, 1.0),
    );
    final fillEnd = (payload.fillGradientEnd ?? payload.fill).withValues(
      alpha: ((payload.fillGradientEnd ?? payload.fill).a * payload.fillOpacity)
          .clamp(0.0, 1.0),
    );
    final fillPaint = Paint()..style = PaintingStyle.fill;
    switch (payload.fillType) {
      case FillType.linearGradient:
        fillPaint.shader = LinearGradient(
          colors: [fillStart, fillEnd],
        ).createShader(rect);
        break;
      case FillType.radialGradient:
        fillPaint.shader = RadialGradient(
          colors: [fillStart, fillEnd],
        ).createShader(rect);
        break;
      case FillType.angularGradient:
        fillPaint.shader = SweepGradient(
          colors: [fillStart, fillEnd, fillStart],
        ).createShader(rect);
        break;
      case FillType.solid:
        fillPaint.color = fillStart;
        break;
    }
    canvas.drawPath(path, fillPaint);

    if (payload.strokeWidth > 0) {
      final strokePaint = Paint()
        ..color = payload.stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = payload.strokeWidth;
      if (payload.strokeStyle == StrokeStyle.dashed) {
        _drawDashedPath(canvas, path, strokePaint, dashWidth: 6, dashSpace: 4);
      } else if (payload.strokeStyle == StrokeStyle.dotted) {
        _drawDashedPath(canvas, path, strokePaint, dashWidth: 2, dashSpace: 3);
      } else {
        canvas.drawPath(path, strokePaint);
      }
    }

    if (payload.label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: payload.label,
          style: TextStyle(
            color: payload.labelColor,
            fontSize: payload.labelFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: max(0.0, node.width - 16.0));
      tp.paint(
        canvas,
        Offset((node.width - tp.width) / 2, (node.height - tp.height) / 2),
      );
    }
  }

  static void _paintLine(Canvas canvas, CanvasNode node) {
    _renderLineOrArrow(canvas, node, isArrowDefault: false);
  }

  static void _paintArrow(Canvas canvas, CanvasNode node) {
    _renderLineOrArrow(canvas, node, isArrowDefault: true);
  }

  static void _renderLineOrArrow(
    Canvas canvas,
    CanvasNode node, {
    required bool isArrowDefault,
  }) {
    final payload = node.payload is ShapePayload
        ? node.payload as ShapePayload
        : ShapePayload();
    final strokePaint = Paint()
      ..color = payload.stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, payload.strokeWidth)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pStart = Offset(
      payload.startXRatio * node.width,
      payload.startYRatio * node.height,
    );
    final pEnd = Offset(
      payload.endXRatio * node.width,
      payload.endYRatio * node.height,
    );

    final path = Path();
    if (payload.lineRouting == LineRouting.orthogonal) {
      final midX = (pStart.dx + pEnd.dx) / 2;
      path.moveTo(pStart.dx, pStart.dy);
      path.lineTo(midX, pStart.dy);
      path.lineTo(midX, pEnd.dy);
      path.lineTo(pEnd.dx, pEnd.dy);
    } else if (payload.lineRouting == LineRouting.curved) {
      final midX = (pStart.dx + pEnd.dx) / 2;
      final midY = (pStart.dy + pEnd.dy) / 2;
      final dx = pEnd.dx - pStart.dx;
      final dy = pEnd.dy - pStart.dy;
      final depth = payload.curveDepth;
      final perpX = -dy * depth;
      final perpY = dx * depth;
      path.moveTo(pStart.dx, pStart.dy);
      path.quadraticBezierTo(midX + perpX, midY + perpY, pEnd.dx, pEnd.dy);
    } else {
      path.moveTo(pStart.dx, pStart.dy);
      path.lineTo(pEnd.dx, pEnd.dy);
    }

    if (payload.hasShadow && payload.shadowBlur > 0) {
      final shadowPaint = Paint()
        ..color = payload.shadowColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokePaint.strokeWidth
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, payload.shadowBlur);
      canvas.save();
      canvas.translate(payload.shadowOffsetX, payload.shadowOffsetY);
      canvas.drawPath(path, shadowPaint);
      canvas.restore();
    }

    if (payload.strokeStyle == StrokeStyle.dashed) {
      _drawDashedPath(canvas, path, strokePaint, dashWidth: 6, dashSpace: 4);
    } else if (payload.strokeStyle == StrokeStyle.dotted) {
      _drawDashedPath(canvas, path, strokePaint, dashWidth: 2, dashSpace: 3);
    } else {
      canvas.drawPath(path, strokePaint);
    }

    // Determine markers
    final startM = payload.startMarker;
    final endM = payload.endMarker != LineMarker.none
        ? payload.endMarker
        : (isArrowDefault ? LineMarker.arrow : LineMarker.none);

    void drawMarker(Offset tip, double angle, LineMarker marker) {
      if (marker == LineMarker.none) return;
      final markerSize = max(8.0, payload.strokeWidth * 3.5);
      final fillPaint = Paint()
        ..color = payload.stroke
        ..style = PaintingStyle.fill;

      if (marker == LineMarker.arrow) {
        final arrowP = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(
            tip.dx - markerSize * cos(angle - pi / 6.5),
            tip.dy - markerSize * sin(angle - pi / 6.5),
          )
          ..lineTo(
            tip.dx - markerSize * 0.75 * cos(angle),
            tip.dy - markerSize * 0.75 * sin(angle),
          )
          ..lineTo(
            tip.dx - markerSize * cos(angle + pi / 6.5),
            tip.dy - markerSize * sin(angle + pi / 6.5),
          )
          ..close();
        canvas.drawPath(arrowP, fillPaint);
      } else if (marker == LineMarker.circle) {
        canvas.drawCircle(tip, markerSize * 0.4, fillPaint);
      } else if (marker == LineMarker.diamond) {
        final dP = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(
            tip.dx - markerSize * 0.6 * cos(angle - pi / 4),
            tip.dy - markerSize * 0.6 * sin(angle - pi / 4),
          )
          ..lineTo(
            tip.dx - markerSize * cos(angle),
            tip.dy - markerSize * sin(angle),
          )
          ..lineTo(
            tip.dx - markerSize * 0.6 * cos(angle + pi / 4),
            tip.dy - markerSize * 0.6 * sin(angle + pi / 4),
          )
          ..close();
        canvas.drawPath(dP, fillPaint);
      }
    }

    // Calculate true tangent angles at endpoints according to line routing
    double startAngle;
    double endAngle;

    if (payload.lineRouting == LineRouting.curved) {
      final midX = (pStart.dx + pEnd.dx) / 2;
      final midY = (pStart.dy + pEnd.dy) / 2;
      final dx = pEnd.dx - pStart.dx;
      final dy = pEnd.dy - pStart.dy;
      final depth = payload.curveDepth;
      final cx = midX - dy * depth;
      final cy = midY + dx * depth;

      // Start tangent is from control point to start point: atan2(pStart.dy - cy, pStart.dx - cx)
      startAngle = atan2(pStart.dy - cy, pStart.dx - cx);
      // End tangent is from control point to end point: atan2(pEnd.dy - cy, pEnd.dx - cx)
      endAngle = atan2(pEnd.dy - cy, pEnd.dx - cx);
    } else if (payload.lineRouting == LineRouting.orthogonal) {
      final midX = (pStart.dx + pEnd.dx) / 2;
      // Start segment is horizontal towards midX
      startAngle = atan2(0, pStart.dx - midX);
      // End segment is horizontal from midX to pEnd.dx
      endAngle = atan2(0, pEnd.dx - midX);
    } else {
      final lineAngle = atan2(pEnd.dy - pStart.dy, pEnd.dx - pStart.dx);
      startAngle = lineAngle + pi;
      endAngle = lineAngle;
    }

    drawMarker(pStart, startAngle, startM);
    drawMarker(pEnd, endAngle, endM);

    // Embedded label on line
    if (payload.label.isNotEmpty) {
      final labelPainter = TextPainter(
        text: TextSpan(
          text: payload.label,
          style: TextStyle(
            color: payload.labelColor,
            fontSize: payload.labelFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final mid = Offset((pStart.dx + pEnd.dx) / 2, (pStart.dy + pEnd.dy) / 2);
      final bgRect = Rect.fromCenter(
        center: mid,
        width: labelPainter.width + 12,
        height: labelPainter.height + 6,
      );

      final bgPaint = Paint()..color = const Color(0xFF1E293B);
      final borderPaint = Paint()
        ..color = payload.stroke.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
        bgPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
        borderPaint,
      );
      labelPainter.paint(canvas, Offset(bgRect.left + 6, bgRect.top + 3));
    }
  }

  static void _paintStickyNote(Canvas canvas, CanvasNode node) {
    final payload = node.payload as StickyNotePayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawRect(rect.shift(const Offset(2, 4)), shadowPaint);

    final bgPaint = Paint()
      ..color = payload.backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, bgPaint);

    if (payload.blocks != null && payload.blocks!.isNotEmpty) {
      double y = 8.0;
      final maxWidth = max(10.0, node.width - 16.0);
      for (final block in payload.blocks!) {
        y += _richTextSpacing(block.spacingBefore);
        final blockIndent = block.indent.clamp(0, 12).toDouble() * 16.0;
        final blockWidth = max(10.0, maxWidth - blockIndent);
        final blockFontSize = _blockFontSize(block.type, payload.fontSize);
        final List<InlineSpan> inlineSpans = [];
        for (final span in block.spans) {
          final spanDecorations = <TextDecoration>[];
          if (span.underline) spanDecorations.add(TextDecoration.underline);
          if (span.strikethrough) {
            spanDecorations.add(TextDecoration.lineThrough);
          }

          final spanFontFamily = span.fontFamily?.trim();
          final spanFontSize =
              span.fontSize != null &&
                  span.fontSize!.isFinite &&
                  span.fontSize! > 0
              ? span.fontSize!
              : blockFontSize;
          inlineSpans.add(
            TextSpan(
              text: span.text,
              style: _resolveTextStyle(
                fontFamily: spanFontFamily == null || spanFontFamily.isEmpty
                    ? (block.type == RichTextBlockType.code
                          ? 'Fira Code'
                          : payload.fontFamily)
                    : spanFontFamily,
                fontSize: spanFontSize,
                fontWeight:
                    span.fontWeight ??
                    (span.bold ? FontWeight.bold : FontWeight.normal),
                fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
                color: span.color ?? payload.textColor,
                decoration: spanDecorations.isEmpty
                    ? null
                    : TextDecoration.combine(spanDecorations),
                backgroundColor: span.highlight,
                fontAxes: span.fontAxes,
              ),
            ),
          );
        }

        final tp = TextPainter(
          text: TextSpan(children: inlineSpans),
          textAlign: block.alignment ?? payload.textAlign,
          textDirection: TextDirection.ltr,
          maxLines: 15,
          ellipsis: '...',
        );
        tp.layout(minWidth: blockWidth, maxWidth: blockWidth);
        tp.paint(canvas, Offset(8.0 + blockIndent, y));
        final defaultSpacing = block.type == RichTextBlockType.heading
            ? 8.0
            : 4.0;
        y +=
            tp.height +
            max(defaultSpacing, _richTextSpacing(block.spacingAfter));
        if (y >= node.height - 12.0) break;
      }
    } else {
      final textSpan = TextSpan(
        text: payload.text,
        style: _resolveTextStyle(
          fontFamily: payload.fontFamily,
          fontSize: payload.fontSize,
          fontWeight: FontWeight.w500,
          fontStyle: FontStyle.normal,
          color: payload.textColor,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: payload.textAlign,
        textDirection: TextDirection.ltr,
        maxLines: 15,
        ellipsis: '...',
      );
      textPainter.layout(maxWidth: max(10.0, node.width - 16.0));
      textPainter.paint(canvas, const Offset(8, 8));
    }
  }

  static TextStyle _resolveTextStyle({
    required String fontFamily,
    required double fontSize,
    required FontWeight fontWeight,
    required FontStyle fontStyle,
    required Color color,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
    Color? backgroundColor,
    Paint? foreground,
    List<Shadow>? shadows,
    Map<String, double>? fontAxes,
    String? localeTag,
  }) {
    final fontVariations = fontAxes == null || fontAxes.isEmpty
        ? null
        : fontAxes.entries
              .map((entry) => ui.FontVariation(entry.key, entry.value))
              .toList(growable: false);
    TextStyle fallbackStyle = TextStyle(
      fontFamily: fontFamily.isEmpty ? 'Inter' : fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      color: foreground == null ? color : null,
      foreground: foreground,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
      backgroundColor: backgroundColor,
      shadows: shadows,
      fontVariations: fontVariations,
      locale: _localeFromTag(localeTag),
    );

    try {
      switch (fontFamily.toLowerCase().trim()) {
        case 'roboto':
          return GoogleFonts.roboto(
            textStyle: fallbackStyle,
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: foreground == null ? color : null,
            height: height,
            letterSpacing: letterSpacing,
            decoration: decoration,
            backgroundColor: backgroundColor,
            shadows: shadows,
          );
        case 'poppins':
          return GoogleFonts.poppins(
            textStyle: fallbackStyle,
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: foreground == null ? color : null,
            height: height,
            letterSpacing: letterSpacing,
            decoration: decoration,
            backgroundColor: backgroundColor,
            shadows: shadows,
          );
        case 'fira code':
        case 'firacode':
          return GoogleFonts.firaCode(
            textStyle: fallbackStyle,
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: foreground == null ? color : null,
            height: height,
            letterSpacing: letterSpacing,
            decoration: decoration,
            backgroundColor: backgroundColor,
            shadows: shadows,
          );
        case 'caveat':
          return GoogleFonts.caveat(
            textStyle: fallbackStyle,
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: foreground == null ? color : null,
            height: height,
            letterSpacing: letterSpacing,
            decoration: decoration,
            backgroundColor: backgroundColor,
            shadows: shadows,
          );
        case 'playfair display':
        case 'playfair':
          return GoogleFonts.playfairDisplay(
            textStyle: fallbackStyle,
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: foreground == null ? color : null,
            height: height,
            letterSpacing: letterSpacing,
            decoration: decoration,
            backgroundColor: backgroundColor,
            shadows: shadows,
          );
        case 'arial':
        case 'monospace':
        case 'sans-serif':
        case 'system':
          return fallbackStyle;
        case 'inter':
        default:
          return GoogleFonts.inter(
            textStyle: fallbackStyle,
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: foreground == null ? color : null,
            height: height,
            letterSpacing: letterSpacing,
            decoration: decoration,
            backgroundColor: backgroundColor,
            shadows: shadows,
          );
      }
    } catch (_) {
      return fallbackStyle;
    }
  }

  static Locale? _localeFromTag(String? tag) {
    final value = tag?.trim();
    if (value == null || value.isEmpty) return null;
    final parts = value.split(RegExp(r'[-_]'));
    if (parts.first.isEmpty) return null;
    return Locale.fromSubtags(
      languageCode: parts.first,
      countryCode: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
      scriptCode: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
    );
  }

  static String _transformText(String text, TextTransformCase transform) {
    switch (transform) {
      case TextTransformCase.uppercase:
        return text.toUpperCase();
      case TextTransformCase.lowercase:
        return text.toLowerCase();
      case TextTransformCase.capitalize:
        return text
            .split(' ')
            .map((word) {
              if (word.isEmpty) return word;
              return word[0].toUpperCase() + word.substring(1).toLowerCase();
            })
            .join(' ');
      case TextTransformCase.none:
        return text;
    }
  }

  static void _paintText(
    Canvas canvas,
    CanvasNode node, {
    CanvasNode? textPathNode,
  }) {
    final payload = node.payload as TextPayload;

    if (payload.textPathNodeId != null && textPathNode != null) {
      _paintTextOnPath(canvas, node, payload, textPathNode);
      return;
    }

    final clipText = payload.wrapMode != TextWrapMode.wrap;
    if (clipText) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, node.width, node.height));
    }

    if (payload.isMarkdown ||
        payload.text.contains(
          RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|~~[^~]+~~|<u>[^<]+<\/u>|`[^`]+`)'),
        )) {
      _paintMarkdownText(canvas, node, payload);
      if (clipText) canvas.restore();
      return;
    }

    if (payload.isRichText) {
      _paintRichText(canvas, node, payload);
      if (clipText) canvas.restore();
      return;
    }

    final displayText = _transformText(payload.text, payload.textTransform);

    // Render background badge if specified
    if (payload.backgroundColor != null) {
      final bgPaint = Paint()..color = payload.backgroundColor!;
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, node.width, node.height),
        Radius.circular(payload.backgroundRadius),
      );
      canvas.drawRRect(bgRect, bgPaint);
    }

    final List<Shadow> shadows = [];
    if (payload.shadowColor != null && payload.shadowBlurRadius > 0) {
      shadows.add(
        Shadow(
          color: payload.shadowColor!,
          offset: payload.shadowOffset,
          blurRadius: payload.shadowBlurRadius,
        ),
      );
    }

    final decorations = <TextDecoration>[];
    if (payload.underline) decorations.add(TextDecoration.underline);
    if (payload.strikethrough) decorations.add(TextDecoration.lineThrough);
    final decoration = decorations.isEmpty
        ? null
        : TextDecoration.combine(decorations);

    // Stroke / Outline pass (paint first under fill if enabled)
    final double padding = payload.backgroundColor != null
        ? payload.backgroundPadding
        : 0.0;
    final double availableWidth = max(10.0, node.width - (padding * 2));
    final double maxWidthConstraint = payload.sizeMode == TextSizeMode.autoWidth
        ? double.infinity
        : availableWidth;

    if (payload.strokeColor != null && payload.strokeWidth > 0) {
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = payload.strokeWidth * 2
        ..color = payload.strokeColor!
        ..strokeJoin = StrokeJoin.round;

      final strokeStyle = _resolveTextStyle(
        fontFamily: payload.fontFamily,
        fontSize: payload.fontSize,
        fontWeight: payload.fontWeight,
        fontStyle: payload.fontStyle,
        color: payload.strokeColor!,
        foreground: strokePaint,
        height: payload.lineHeight,
        letterSpacing: payload.letterSpacing,
        decoration: decoration,
        fontAxes: payload.fontAxes,
        localeTag: payload.localeTag,
      );

      final strokePainter = TextPainter(
        text: TextSpan(text: displayText, style: strokeStyle),
        textAlign: payload.textAlign,
        textDirection: TextDirection.ltr,
        maxLines: payload.wrapMode == TextWrapMode.ellipsis ? 1 : null,
        ellipsis: payload.wrapMode == TextWrapMode.ellipsis ? '\u2026' : null,
      );
      strokePainter.layout(
        minWidth: payload.sizeMode == TextSizeMode.autoWidth
            ? 0.0
            : availableWidth,
        maxWidth: maxWidthConstraint,
      );

      double strokeOffsetX = padding;
      if (payload.sizeMode == TextSizeMode.autoWidth) {
        if (payload.textAlign == TextAlign.center) {
          strokeOffsetX =
              padding +
              max(0.0, (node.width - (padding * 2) - strokePainter.width) / 2);
        } else if (payload.textAlign == TextAlign.right) {
          strokeOffsetX =
              padding +
              max(0.0, node.width - (padding * 2) - strokePainter.width);
        }
      }

      double offsetY = padding;
      if (payload.verticalAlign == TextVerticalAlign.middle) {
        offsetY = max(padding, (node.height - strokePainter.height) / 2);
      } else if (payload.verticalAlign == TextVerticalAlign.bottom) {
        offsetY = max(padding, node.height - strokePainter.height - padding);
      }
      strokePainter.paint(canvas, Offset(strokeOffsetX, offsetY));
    }

    final fillStyle = _resolveTextStyle(
      fontFamily: payload.fontFamily,
      fontSize: payload.fontSize,
      fontWeight: payload.fontWeight,
      fontStyle: payload.fontStyle,
      color: payload.color,
      height: payload.lineHeight,
      letterSpacing: payload.letterSpacing,
      decoration: decoration,
      shadows: shadows.isEmpty ? null : shadows,
      fontAxes: payload.fontAxes,
      localeTag: payload.localeTag,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: displayText, style: fillStyle),
      textAlign: payload.textAlign,
      textDirection: TextDirection.ltr,
      maxLines: payload.wrapMode == TextWrapMode.ellipsis ? 1 : null,
      ellipsis: payload.wrapMode == TextWrapMode.ellipsis ? '\u2026' : null,
    );
    textPainter.layout(
      minWidth: payload.sizeMode == TextSizeMode.autoWidth
          ? 0.0
          : availableWidth,
      maxWidth: maxWidthConstraint,
    );

    double offsetX = padding;
    if (payload.sizeMode == TextSizeMode.autoWidth) {
      if (payload.textAlign == TextAlign.center) {
        offsetX =
            padding +
            max(0.0, (node.width - (padding * 2) - textPainter.width) / 2);
      } else if (payload.textAlign == TextAlign.right) {
        offsetX =
            padding + max(0.0, node.width - (padding * 2) - textPainter.width);
      }
    }

    double offsetY = padding;
    if (payload.verticalAlign == TextVerticalAlign.middle) {
      offsetY = max(padding, (node.height - textPainter.height) / 2);
    } else if (payload.verticalAlign == TextVerticalAlign.bottom) {
      offsetY = max(padding, node.height - textPainter.height - padding);
    }

    textPainter.paint(canvas, Offset(offsetX, offsetY));
    if (clipText) canvas.restore();
  }

  static void _paintTextOnPath(
    Canvas canvas,
    CanvasNode node,
    TextPayload payload,
    CanvasNode pathNode,
  ) {
    final pathPayload = pathNode.payload;
    if (pathPayload is! VectorPathPayload) return;

    final style = _resolveTextStyle(
      fontFamily: payload.fontFamily,
      fontSize: payload.fontSize,
      fontWeight: payload.fontWeight,
      fontStyle: payload.fontStyle,
      color: payload.color,
      height: payload.lineHeight,
      letterSpacing: payload.letterSpacing,
      fontAxes: payload.fontAxes,
      localeTag: payload.localeTag,
      decoration: payload.underline
          ? TextDecoration.underline
          : (payload.strikethrough ? TextDecoration.lineThrough : null),
    );
    final richBlocks = payload.blocks;
    final hasRichBlocks = richBlocks != null && richBlocks.isNotEmpty;
    final glyphStyles = <TextStyle>[];
    final textBuffer = StringBuffer();
    if (hasRichBlocks) {
      for (var blockIndex = 0; blockIndex < richBlocks.length; blockIndex++) {
        final block = richBlocks[blockIndex];
        for (final span in block.spans) {
          final transformed = _transformText(span.text, payload.textTransform);
          textBuffer.write(transformed);
          final spanDecorations = <TextDecoration>[];
          if (span.underline || span.linkUrl != null || payload.underline) {
            spanDecorations.add(TextDecoration.underline);
          }
          if (span.strikethrough || payload.strikethrough) {
            spanDecorations.add(TextDecoration.lineThrough);
          }
          final spanFontFamily = span.fontFamily?.trim();
          final spanAxes = <String, double>{
            ...payload.fontAxes,
            ...span.fontAxes,
          };
          final spanFontSize =
              span.fontSize != null &&
                  span.fontSize!.isFinite &&
                  span.fontSize! > 0
              ? span.fontSize!
              : _blockFontSize(block.type, payload.fontSize);
          final spanStyle = _resolveTextStyle(
            fontFamily: spanFontFamily == null || spanFontFamily.isEmpty
                ? (block.type == RichTextBlockType.code
                      ? 'Fira Code'
                      : payload.fontFamily)
                : spanFontFamily,
            fontSize: spanFontSize,
            fontWeight:
                span.fontWeight ??
                _blockFontWeight(block.type, span, payload.fontWeight),
            fontStyle: (span.italic || payload.fontStyle == FontStyle.italic)
                ? FontStyle.italic
                : FontStyle.normal,
            color: span.linkUrl != null
                ? const Color(0xFF38BDF8)
                : (span.color ?? payload.color),
            height: payload.lineHeight,
            letterSpacing: payload.letterSpacing,
            decoration: spanDecorations.isEmpty
                ? null
                : TextDecoration.combine(spanDecorations),
            backgroundColor: span.highlight,
            fontAxes: spanAxes,
            localeTag: payload.localeTag,
          );
          glyphStyles.addAll(
            List<TextStyle>.filled(transformed.runes.length, spanStyle),
          );
        }
        if (blockIndex < richBlocks.length - 1) {
          textBuffer.write('\n');
          glyphStyles.add(style);
        }
      }
    } else {
      textBuffer.write(_transformText(payload.text, payload.textTransform));
    }
    final text = textBuffer.toString();
    final path = pathPayload.toPath();
    final placements = TextOnPathLayout.layout(
      text: text,
      path: path,
      style: style,
      glyphStyles: hasRichBlocks ? glyphStyles : null,
      alignment: payload.textPathAlignment,
      offset: payload.textPathOffset,
      reversed: payload.textPathReversed,
    );
    if (placements.isEmpty) return;

    canvas.save();
    canvas.translate(pathNode.x - node.x, pathNode.y - node.y);
    if (pathNode.rotation != 0.0) {
      canvas.translate(pathNode.width / 2, pathNode.height / 2);
      canvas.rotate(pathNode.rotation);
      canvas.translate(-pathNode.width / 2, -pathNode.height / 2);
    }
    for (final placement in placements) {
      final painter = TextPainter(
        text: TextSpan(text: placement.glyph, style: placement.style),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(placement.position.dx, placement.position.dy);
      canvas.rotate(placement.angle);
      painter.paint(
        canvas,
        Offset(-placement.width / 2, -placement.height / 2),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  static List<InlineSpan> _parseInlineMarkdown(
    String rawText,
    TextStyle baseStyle,
    TextPayload payload,
  ) {
    final List<InlineSpan> spans = [];
    final pattern = RegExp(
      r'(\*\*[^*]+\*\*|\*[^*]+\*|~~[^~]+~~|<u>[^<]+<\/u>|`[^`]+`)',
    );
    int lastEnd = 0;

    for (final match in pattern.allMatches(rawText)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: rawText.substring(lastEnd, match.start),
            style: baseStyle,
          ),
        );
      }
      final token = match.group(0)!;
      if (token.startsWith('**') && token.endsWith('**')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: baseStyle.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      } else if (token.startsWith('*') && token.endsWith('*')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else if (token.startsWith('~~') && token.endsWith('~~')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
          ),
        );
      } else if (token.startsWith('<u>') && token.endsWith('</u>')) {
        spans.add(
          TextSpan(
            text: token.substring(3, token.length - 4),
            style: baseStyle.copyWith(decoration: TextDecoration.underline),
          ),
        );
      } else if (token.startsWith('`') && token.endsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: _resolveTextStyle(
              fontFamily: 'Fira Code',
              fontSize: baseStyle.fontSize ?? payload.fontSize,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.normal,
              color: const Color(0xFF38BDF8),
            ),
          ),
        );
      }
      lastEnd = match.end;
    }

    if (lastEnd < rawText.length) {
      spans.add(TextSpan(text: rawText.substring(lastEnd), style: baseStyle));
    }
    return spans;
  }

  static void _paintMarkdownText(
    Canvas canvas,
    CanvasNode node,
    TextPayload payload,
  ) {
    final double padding = payload.backgroundColor != null
        ? payload.backgroundPadding
        : 0.0;
    final double availableWidth = max(10.0, node.width - (padding * 2));
    final double maxWidth = payload.sizeMode == TextSizeMode.autoWidth
        ? double.infinity
        : availableWidth;

    if (payload.backgroundColor != null) {
      final bgPaint = Paint()..color = payload.backgroundColor!;
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, node.width, node.height),
        Radius.circular(payload.backgroundRadius),
      );
      canvas.drawRRect(bgRect, bgPaint);
    }

    final lines = payload.text.split('\n');
    double y = padding;

    for (final line in lines) {
      if (line.isEmpty) {
        y += payload.fontSize * 0.8;
        continue;
      }

      TextStyle style;
      String text = line;
      double lineSpacing = 4.0;

      if (line.startsWith('# ')) {
        text = line.substring(2);
        style = _resolveTextStyle(
          fontFamily: payload.fontFamily,
          fontSize: payload.fontSize * 1.6,
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.normal,
          color: payload.color,
        );
        lineSpacing = 8.0;
      } else if (line.startsWith('## ')) {
        text = line.substring(3);
        style = _resolveTextStyle(
          fontFamily: payload.fontFamily,
          fontSize: payload.fontSize * 1.3,
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.normal,
          color: payload.color,
        );
        lineSpacing = 6.0;
      } else if (line.startsWith('### ')) {
        text = line.substring(4);
        style = _resolveTextStyle(
          fontFamily: payload.fontFamily,
          fontSize: payload.fontSize * 1.1,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.normal,
          color: payload.color,
        );
        lineSpacing = 4.0;
      } else if (line.startsWith('> ')) {
        text = '│ ${line.substring(2)}';
        style = _resolveTextStyle(
          fontFamily: payload.fontFamily,
          fontSize: payload.fontSize * 0.95,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.italic,
          color: const Color(0xFF94A3B8),
        );
      } else if (line.startsWith('- [ ] ') || line.startsWith('* [ ] ')) {
        text = '☐ ${line.substring(6)}';
        style = _resolveTextStyle(
          fontFamily: payload.fontFamily,
          fontSize: payload.fontSize,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
          color: payload.color,
        );
      } else if (line.startsWith('- [x] ') || line.startsWith('* [x] ')) {
        text = '☑ ${line.substring(6)}';
        style = _resolveTextStyle(
          fontFamily: payload.fontFamily,
          fontSize: payload.fontSize,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF10B981),
          decoration: TextDecoration.lineThrough,
        );
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        text = '• ${line.substring(2)}';
        style = _resolveTextStyle(
          fontFamily: payload.fontFamily,
          fontSize: payload.fontSize,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
          color: payload.color,
        );
      } else {
        style = _resolveTextStyle(
          fontFamily: payload.fontFamily,
          fontSize: payload.fontSize,
          fontWeight: payload.fontWeight,
          fontStyle: payload.fontStyle,
          color: payload.color,
          height: payload.lineHeight,
          letterSpacing: payload.letterSpacing,
        );
      }

      final inlineSpans = _parseInlineMarkdown(text, style, payload);
      final textPainter = TextPainter(
        text: TextSpan(children: inlineSpans, style: style),
        textAlign: payload.textAlign,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(
        minWidth: payload.sizeMode == TextSizeMode.autoWidth
            ? 0.0
            : availableWidth,
        maxWidth: maxWidth,
      );

      double offsetX = padding;
      if (payload.sizeMode == TextSizeMode.autoWidth) {
        if (payload.textAlign == TextAlign.center) {
          offsetX =
              padding +
              max(0.0, (node.width - (padding * 2) - textPainter.width) / 2);
        } else if (payload.textAlign == TextAlign.right) {
          offsetX =
              padding +
              max(0.0, node.width - (padding * 2) - textPainter.width);
        }
      }

      textPainter.paint(canvas, Offset(offsetX, y));
      y += textPainter.height + lineSpacing;
    }
  }

  static void _paintRichText(
    Canvas canvas,
    CanvasNode node,
    TextPayload payload,
  ) {
    final baseFontSize = payload.fontSize;
    final baseColor = payload.color;
    final double padding = payload.backgroundColor != null
        ? payload.backgroundPadding
        : 0.0;
    double y = padding;

    if (payload.backgroundColor != null) {
      final bgPaint = Paint()..color = payload.backgroundColor!;
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, node.width, node.height),
        Radius.circular(payload.backgroundRadius),
      );
      canvas.drawRRect(bgRect, bgPaint);
    }

    final blocks = payload.blocks != null && payload.blocks!.isNotEmpty
        ? payload.blocks!
        : [
            RichTextBlock(spans: [RichTextSpan(text: payload.text)]),
          ];
    for (final block in blocks) {
      y += _richTextSpacing(block.spacingBefore);

      final blockSpans = block.spans.isEmpty
          ? [const RichTextSpan(text: '')]
          : block.spans;
      final blockFontSize = _blockFontSize(block.type, baseFontSize);
      final blockIndent = block.indent.clamp(0, 12).toDouble() * 24.0;
      final blockAlignment = block.alignment ?? payload.textAlign;
      final availableWidth = max(
        10.0,
        node.width - (padding * 2) - blockIndent,
      );
      final maxWidth = payload.sizeMode == TextSizeMode.autoWidth
          ? double.infinity
          : availableWidth;
      final maxLines = payload.wrapMode == TextWrapMode.wrap ? null : 1;

      final List<InlineSpan> inlineSpans = [];
      for (final span in blockSpans) {
        final spanDecorations = <TextDecoration>[];
        if (span.underline || span.linkUrl != null || payload.underline) {
          spanDecorations.add(TextDecoration.underline);
        }
        if (span.strikethrough || payload.strikethrough) {
          spanDecorations.add(TextDecoration.lineThrough);
        }

        final spanFontFamily = span.fontFamily?.trim();
        final spanAxes = <String, double>{
          ...payload.fontAxes,
          ...span.fontAxes,
        };
        final spanFontSize =
            span.fontSize != null &&
                span.fontSize!.isFinite &&
                span.fontSize! > 0
            ? span.fontSize!
            : blockFontSize;
        final spanStyle = _resolveTextStyle(
          fontFamily: spanFontFamily == null || spanFontFamily.isEmpty
              ? (block.type == RichTextBlockType.code
                    ? 'Fira Code'
                    : payload.fontFamily)
              : spanFontFamily,
          fontSize: spanFontSize,
          fontWeight:
              span.fontWeight ??
              _blockFontWeight(block.type, span, payload.fontWeight),
          fontStyle: (span.italic || payload.fontStyle == FontStyle.italic)
              ? FontStyle.italic
              : FontStyle.normal,
          color: span.linkUrl != null
              ? const Color(0xFF38BDF8)
              : (span.color ?? baseColor),
          height: payload.lineHeight,
          letterSpacing: payload.letterSpacing,
          decoration: spanDecorations.isEmpty
              ? null
              : TextDecoration.combine(spanDecorations),
          backgroundColor: span.highlight,
          fontAxes: spanAxes,
          localeTag: payload.localeTag,
        );

        inlineSpans.add(
          TextSpan(
            text: _transformText(span.text, payload.textTransform),
            style: spanStyle,
          ),
        );
      }

      final String prefix = switch (block.type) {
        RichTextBlockType.bullet => '\u2022 ',
        RichTextBlockType.numbered => '${_numberedIndex(blocks, block)}. ',
        RichTextBlockType.quote => '\u2502 ',
        _ => '',
      };

      final prefixStyle = _resolveTextStyle(
        fontFamily: block.type == RichTextBlockType.code
            ? 'Fira Code'
            : payload.fontFamily,
        fontSize: blockFontSize,
        fontWeight: _blockFontWeight(
          block.type,
          const RichTextSpan(text: ''),
          payload.fontWeight,
        ),
        fontStyle: FontStyle.normal,
        color: block.type == RichTextBlockType.quote
            ? const Color(0xFF94A3B8)
            : baseColor,
        height: payload.lineHeight,
        letterSpacing: payload.letterSpacing,
        fontAxes: payload.fontAxes,
        localeTag: payload.localeTag,
      );

      final TextSpan blockSpan = TextSpan(
        text: prefix,
        style: prefixStyle,
        children: inlineSpans,
      );

      final tp = TextPainter(
        text: blockSpan,
        textAlign: blockAlignment,
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: maxLines == 1 && payload.wrapMode == TextWrapMode.ellipsis
            ? '\u2026'
            : null,
      );

      tp.layout(
        minWidth: payload.sizeMode == TextSizeMode.autoWidth
            ? 0.0
            : availableWidth,
        maxWidth: maxWidth,
      );

      final blockX = padding + blockIndent;

      if (block.type == RichTextBlockType.code) {
        final codeBgPaint = Paint()..color = const Color(0xFF1E293B);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(blockX, y, availableWidth, tp.height + 8),
            const Radius.circular(4),
          ),
          codeBgPaint,
        );
        tp.paint(canvas, Offset(blockX + 6, y + 4));
        y += tp.height + max(12.0, _richTextSpacing(block.spacingAfter));
      } else {
        tp.paint(canvas, Offset(blockX, y));
        final defaultSpacing = block.type == RichTextBlockType.heading
            ? 8.0
            : 4.0;
        y +=
            tp.height +
            max(defaultSpacing, _richTextSpacing(block.spacingAfter));
      }
    }
  }

  static double _richTextSpacing(double value) {
    if (!value.isFinite) return 0.0;
    return value.clamp(0.0, 500.0).toDouble();
  }

  static double _blockFontSize(RichTextBlockType type, double base) {
    switch (type) {
      case RichTextBlockType.heading:
        return base * 1.5;
      case RichTextBlockType.quote:
        return base * 0.9;
      case RichTextBlockType.code:
        return base * 0.85;
      default:
        return base;
    }
  }

  static FontWeight _blockFontWeight(
    RichTextBlockType type,
    RichTextSpan span,
    FontWeight base,
  ) {
    if (type == RichTextBlockType.heading) return FontWeight.bold;
    if (span.bold) return FontWeight.bold;
    return base;
  }

  static int _numberedIndex(List<RichTextBlock> blocks, RichTextBlock target) {
    int count = 0;
    for (final b in blocks) {
      if (b.type == RichTextBlockType.numbered) count++;
      if (identical(b, target)) break;
    }
    return count;
  }

  static void _paintDiamond(Canvas canvas, CanvasNode node) {
    final payload = node.payload as ShapePayload;
    if (_paintDiagramShape(canvas, node, payload)) return;
    final w = node.width;
    final h = node.height;
    final rect = Rect.fromLTWH(0, 0, w, h);
    final r = payload.cornerRadius.clamp(0.0, min(w, h) / 4);

    final path = Path();
    if (r <= 0) {
      path
        ..moveTo(w / 2, 0)
        ..lineTo(w, h / 2)
        ..lineTo(w / 2, h)
        ..lineTo(0, h / 2)
        ..close();
    } else {
      final pT = Offset(w / 2, 0);
      final pR = Offset(w, h / 2);
      final pB = Offset(w / 2, h);
      final pL = Offset(0, h / 2);

      Offset interpolate(Offset a, Offset b, double dist) {
        final total = (b - a).distance;
        if (total == 0) return a;
        final t = (dist / total).clamp(0.0, 0.5);
        return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
      }

      path.moveTo(interpolate(pT, pR, r).dx, interpolate(pT, pR, r).dy);
      path.lineTo(interpolate(pR, pT, r).dx, interpolate(pR, pT, r).dy);
      path.quadraticBezierTo(
        pR.dx,
        pR.dy,
        interpolate(pR, pB, r).dx,
        interpolate(pR, pB, r).dy,
      );
      path.lineTo(interpolate(pB, pR, r).dx, interpolate(pB, pR, r).dy);
      path.quadraticBezierTo(
        pB.dx,
        pB.dy,
        interpolate(pB, pL, r).dx,
        interpolate(pB, pL, r).dy,
      );
      path.lineTo(interpolate(pL, pB, r).dx, interpolate(pL, pB, r).dy);
      path.quadraticBezierTo(
        pL.dx,
        pL.dy,
        interpolate(pL, pT, r).dx,
        interpolate(pL, pT, r).dy,
      );
      path.lineTo(interpolate(pT, pL, r).dx, interpolate(pT, pL, r).dy);
      path.quadraticBezierTo(
        pT.dx,
        pT.dy,
        interpolate(pT, pR, r).dx,
        interpolate(pT, pR, r).dy,
      );
      path.close();
    }

    if (payload.hasShadow && payload.shadowBlur > 0) {
      final shadowPaint = Paint()
        ..color = payload.shadowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, payload.shadowBlur);
      canvas.drawPath(
        path.shift(Offset(payload.shadowOffsetX, payload.shadowOffsetY)),
        shadowPaint,
      );
    }

    final fillStart = payload.fill.withValues(
      alpha: (payload.fill.a * payload.fillOpacity).clamp(0.0, 1.0),
    );
    final fillEnd = (payload.fillGradientEnd ?? payload.fill).withValues(
      alpha: ((payload.fillGradientEnd ?? payload.fill).a * payload.fillOpacity)
          .clamp(0.0, 1.0),
    );
    final fillPaint = Paint()..style = PaintingStyle.fill;
    switch (payload.fillType) {
      case FillType.linearGradient:
        fillPaint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fillStart, fillEnd],
        ).createShader(rect);
        break;
      case FillType.radialGradient:
        fillPaint.shader = RadialGradient(
          colors: [fillStart, fillEnd],
        ).createShader(rect);
        break;
      case FillType.angularGradient:
        fillPaint.shader = SweepGradient(
          colors: [fillStart, fillEnd, fillStart],
        ).createShader(rect);
        break;
      case FillType.solid:
        fillPaint.color = fillStart;
        break;
    }
    canvas.drawPath(path, fillPaint);

    if (payload.strokeWidth > 0) {
      final strokePaint = Paint()
        ..color = payload.stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = payload.strokeWidth;
      if (payload.strokeStyle == StrokeStyle.dashed) {
        _drawDashedPath(canvas, path, strokePaint, dashWidth: 6, dashSpace: 4);
      } else if (payload.strokeStyle == StrokeStyle.dotted) {
        _drawDashedPath(canvas, path, strokePaint, dashWidth: 2, dashSpace: 3);
      } else {
        canvas.drawPath(path, strokePaint);
      }
    }

    if (payload.label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: payload.label,
          style: TextStyle(
            color: payload.labelColor,
            fontSize: payload.labelFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: max(0.0, w * 0.6));
      tp.paint(canvas, Offset((w - tp.width) / 2, (h - tp.height) / 2));
    }

    void paintBranchBadge(String text, Offset pos) {
      if (text.isEmpty) return;
      final badgeSpan = TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFFF9FAFB),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      final badgeTp = TextPainter(
        text: badgeSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      final badgeRect = Rect.fromCenter(
        center: pos,
        width: badgeTp.width + 10,
        height: badgeTp.height + 4,
      );
      final bg = Paint()..color = const Color(0xFF1F2937);
      final border = Paint()
        ..color = const Color(0xFF4B5563)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
        bg,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
        border,
      );
      badgeTp.paint(canvas, Offset(badgeRect.left + 5, badgeRect.top + 2));
    }

    paintBranchBadge(payload.branchTop, Offset(w / 2, -10));
    paintBranchBadge(payload.branchRight, Offset(w + 14, h / 2));
    paintBranchBadge(payload.branchBottom, Offset(w / 2, h + 10));
    paintBranchBadge(payload.branchLeft, Offset(-14, h / 2));
  }

  static void _paintCylinder(Canvas canvas, CanvasNode node) {
    final payload = node.payload as ShapePayload;
    if (_paintDiagramShape(canvas, node, payload)) return;
    final w = node.width;
    final h = node.height;
    final capRatio = payload.cylinderCapRatio.clamp(0.1, 0.5);
    final double capHeight = (h * capRatio).clamp(8.0, h * 0.45);
    final partitions = payload.cylinderPartitions.clamp(1, 6);

    final topCapRect = Rect.fromLTWH(0, 0, w, capHeight);
    final botCapRect = Rect.fromLTWH(0, h - capHeight, w, capHeight);
    final bodyRect = Rect.fromLTWH(0, capHeight / 2, w, h - capHeight);

    final fullPath = Path()
      ..moveTo(0, capHeight / 2)
      ..arcTo(topCapRect, pi, pi, false)
      ..lineTo(w, h - capHeight / 2)
      ..arcTo(botCapRect, 0, pi, false)
      ..close();

    if (payload.hasShadow && payload.shadowBlur > 0) {
      final shadowPaint = Paint()
        ..color = payload.shadowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, payload.shadowBlur);
      canvas.drawPath(
        fullPath.shift(Offset(payload.shadowOffsetX, payload.shadowOffsetY)),
        shadowPaint,
      );
    }

    final fillStart = payload.fill.withValues(
      alpha: (payload.fill.a * payload.fillOpacity).clamp(0.0, 1.0),
    );
    final fillEnd = (payload.fillGradientEnd ?? payload.fill).withValues(
      alpha: ((payload.fillGradientEnd ?? payload.fill).a * payload.fillOpacity)
          .clamp(0.0, 1.0),
    );

    final bodyPaint = Paint()..style = PaintingStyle.fill;
    final topCapPaint = Paint()..style = PaintingStyle.fill;

    if (payload.fillType == FillType.linearGradient) {
      bodyPaint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          fillEnd.withValues(alpha: (fillEnd.a * 0.75).clamp(0.0, 1.0)),
          fillStart,
          fillEnd.withValues(alpha: (fillEnd.a * 0.9).clamp(0.0, 1.0)),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
      topCapPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [fillStart, fillEnd],
      ).createShader(topCapRect);
    } else if (payload.fillType == FillType.radialGradient) {
      bodyPaint.shader = RadialGradient(
        center: Alignment.center,
        radius: 0.8,
        colors: [fillStart, fillEnd],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
      topCapPaint.shader = RadialGradient(
        center: Alignment.center,
        radius: 0.8,
        colors: [fillStart, fillEnd],
      ).createShader(topCapRect);
    } else if (payload.fillType == FillType.angularGradient) {
      bodyPaint.shader = SweepGradient(
        colors: [fillStart, fillEnd, fillStart],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
      topCapPaint.shader = SweepGradient(
        colors: [fillStart, fillEnd, fillStart],
      ).createShader(topCapRect);
    } else {
      bodyPaint.color = fillStart;
      topCapPaint.color = fillStart.withValues(
        alpha: min(1.0, fillStart.a * 1.15),
      );
    }

    canvas.drawRect(bodyRect, bodyPaint);
    canvas.drawOval(botCapRect, bodyPaint);
    canvas.drawOval(topCapRect, topCapPaint);

    if (payload.strokeWidth > 0) {
      final strokePaint = Paint()
        ..color = payload.stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = payload.strokeWidth;

      final isDashed = payload.strokeStyle == StrokeStyle.dashed;
      final isDotted = payload.strokeStyle == StrokeStyle.dotted;

      void drawStrokePath(Path p) {
        if (isDashed) {
          _drawDashedPath(canvas, p, strokePaint, dashWidth: 6, dashSpace: 4);
        } else if (isDotted) {
          _drawDashedPath(canvas, p, strokePaint, dashWidth: 2, dashSpace: 3);
        } else {
          canvas.drawPath(p, strokePaint);
        }
      }

      final leftLine = Path()
        ..moveTo(0, capHeight / 2)
        ..lineTo(0, h - capHeight / 2);
      final rightLine = Path()
        ..moveTo(w, capHeight / 2)
        ..lineTo(w, h - capHeight / 2);
      final topOval = Path()..addOval(topCapRect);
      final botArc = Path()..addArc(botCapRect, 0, pi);

      drawStrokePath(leftLine);
      drawStrokePath(rightLine);
      drawStrokePath(topOval);
      drawStrokePath(botArc);

      if (partitions > 1) {
        final availableBodyHeight = h - capHeight;
        final step = availableBodyHeight / partitions;
        for (var i = 1; i < partitions; i++) {
          final yOffset = step * i;
          final partitionRect = Rect.fromLTWH(0, yOffset, w, capHeight);
          final partitionArc = Path()..addArc(partitionRect, 0, pi);
          drawStrokePath(partitionArc);
        }
      }
    }

    if (payload.label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: payload.label,
          style: TextStyle(
            color: payload.labelColor,
            fontSize: payload.labelFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: max(0.0, w - 16.0));
      tp.paint(
        canvas,
        Offset((w - tp.width) / 2, (h - tp.height) / 2 + capHeight / 4),
      );
    }

    if (payload.badgeText.isNotEmpty) {
      final badgeSpan = TextSpan(
        text: payload.badgeText,
        style: const TextStyle(
          color: Color(0xFFF9FAFB),
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      );
      final badgeTp = TextPainter(
        text: badgeSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      final badgeRect = Rect.fromCenter(
        center: Offset(w - 10, capHeight / 2),
        width: badgeTp.width + 8,
        height: badgeTp.height + 4,
      );
      final bg = Paint()..color = const Color(0xFF047857);
      final border = Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(3)),
        bg,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(3)),
        border,
      );
      badgeTp.paint(canvas, Offset(badgeRect.left + 4, badgeRect.top + 2));
    }
  }

  static void _paintParallelogram(Canvas canvas, CanvasNode node) {
    final payload = node.payload as ShapePayload;
    if (_paintDiagramShape(canvas, node, payload)) return;
    final w = node.width;
    final h = node.height;
    final double skew = (payload.skewRatio * w).clamp(-w * 0.45, w * 0.45);

    final double p1x = skew >= 0 ? skew : 0.0;
    const double p1y = 0.0;
    final double p2x = skew >= 0 ? w : w + skew;
    const double p2y = 0.0;
    final double p3x = skew >= 0 ? w - skew : w;
    final double p3y = h;
    final double p4x = skew >= 0 ? 0.0 : -skew;
    final double p4y = h;

    Path path;
    final r = payload.cornerRadius.clamp(0.0, min(w, h) / 4);
    if (r <= 0) {
      path = Path()
        ..moveTo(p1x, p1y)
        ..lineTo(p2x, p2y)
        ..lineTo(p3x, p3y)
        ..lineTo(p4x, p4y)
        ..close();
    } else {
      Offset interpolate(Offset a, Offset b, double dist) {
        final total = (b - a).distance;
        if (total == 0) return a;
        final t = (dist / total).clamp(0.0, 0.45);
        return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
      }

      final p1 = Offset(p1x, p1y);
      final p2 = Offset(p2x, p2y);
      final p3 = Offset(p3x, p3y);
      final p4 = Offset(p4x, p4y);

      path = Path()
        ..moveTo(interpolate(p1, p2, r).dx, interpolate(p1, p2, r).dy)
        ..lineTo(interpolate(p2, p1, r).dx, interpolate(p2, p1, r).dy)
        ..quadraticBezierTo(
          p2.dx,
          p2.dy,
          interpolate(p2, p3, r).dx,
          interpolate(p2, p3, r).dy,
        )
        ..lineTo(interpolate(p3, p2, r).dx, interpolate(p3, p2, r).dy)
        ..quadraticBezierTo(
          p3.dx,
          p3.dy,
          interpolate(p3, p4, r).dx,
          interpolate(p3, p4, r).dy,
        )
        ..lineTo(interpolate(p4, p3, r).dx, interpolate(p4, p3, r).dy)
        ..quadraticBezierTo(
          p4.dx,
          p4.dy,
          interpolate(p4, p1, r).dx,
          interpolate(p4, p1, r).dy,
        )
        ..lineTo(interpolate(p1, p4, r).dx, interpolate(p1, p4, r).dy)
        ..quadraticBezierTo(
          p1.dx,
          p1.dy,
          interpolate(p1, p2, r).dx,
          interpolate(p1, p2, r).dy,
        )
        ..close();
    }

    if (payload.hasShadow) {
      final shadowPaint = Paint()
        ..color = payload.shadowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, payload.shadowBlur);
      canvas.save();
      canvas.translate(payload.shadowOffsetX, payload.shadowOffsetY);
      canvas.drawPath(path, shadowPaint);
      canvas.restore();
    }

    final fillStart = payload.fill.withValues(
      alpha: (payload.fill.a * payload.fillOpacity).clamp(0.0, 1.0),
    );
    final fillEnd = (payload.fillGradientEnd ?? payload.fill).withValues(
      alpha: ((payload.fillGradientEnd ?? payload.fill).a * payload.fillOpacity)
          .clamp(0.0, 1.0),
    );

    final fillPaint = Paint()..style = PaintingStyle.fill;
    final bounds = Rect.fromLTWH(0, 0, w, h);

    if (payload.fillType == FillType.linearGradient) {
      fillPaint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [fillStart, fillEnd],
      ).createShader(bounds);
    } else if (payload.fillType == FillType.radialGradient) {
      fillPaint.shader = RadialGradient(
        center: Alignment.center,
        radius: 0.8,
        colors: [fillStart, fillEnd],
      ).createShader(bounds);
    } else if (payload.fillType == FillType.angularGradient) {
      fillPaint.shader = SweepGradient(
        colors: [fillStart, fillEnd, fillStart],
      ).createShader(bounds);
    } else {
      fillPaint.color = fillStart;
    }

    canvas.drawPath(path, fillPaint);

    if (payload.strokeWidth > 0) {
      final strokePaint = Paint()
        ..color = payload.stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = payload.strokeWidth;

      if (payload.strokeStyle == StrokeStyle.dashed) {
        _drawDashedPath(canvas, path, strokePaint, dashWidth: 6, dashSpace: 4);
      } else if (payload.strokeStyle == StrokeStyle.dotted) {
        _drawDashedPath(canvas, path, strokePaint, dashWidth: 2, dashSpace: 3);
      } else {
        canvas.drawPath(path, strokePaint);
      }
    }

    // Direction/IO Type Badge
    if (payload.ioType.isNotEmpty || payload.badgeText.isNotEmpty) {
      final badgeText = payload.ioType.isNotEmpty
          ? payload.ioType
          : payload.badgeText;
      final isInput = badgeText.toLowerCase().contains('in');
      final isOutput = badgeText.toLowerCase().contains('out');

      final badgeColor = isInput
          ? const Color(0xFF3B82F6)
          : isOutput
          ? const Color(0xFF10B981)
          : const Color(0xFFF59E0B);

      final badgeTp = TextPainter(
        text: TextSpan(
          text: badgeText.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeRect = Rect.fromLTWH(
        (p1x + 8).clamp(0.0, w - badgeTp.width - 12),
        6,
        badgeTp.width + 8,
        badgeTp.height + 4,
      );

      final bg = Paint()..color = badgeColor.withValues(alpha: 0.85);
      final border = Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(3)),
        bg,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(3)),
        border,
      );
      badgeTp.paint(canvas, Offset(badgeRect.left + 4, badgeRect.top + 2));
    }

    // Embedded Main Label & Subtext / Schema Tag
    if (payload.label.isNotEmpty || payload.subText.isNotEmpty) {
      final textSpans = <InlineSpan>[];
      if (payload.label.isNotEmpty) {
        textSpans.add(
          TextSpan(
            text: payload.label,
            style: TextStyle(
              color: payload.labelColor,
              fontSize: payload.labelFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      if (payload.subText.isNotEmpty) {
        if (payload.label.isNotEmpty) {
          textSpans.add(const TextSpan(text: '\n'));
        }
        textSpans.add(
          TextSpan(
            text: '[ ${payload.subText} ]',
            style: TextStyle(
              color: payload.labelColor.withValues(alpha: 0.75),
              fontSize: (payload.labelFontSize * 0.75).clamp(8.0, 16.0),
              fontFamily: 'monospace',
              fontWeight: FontWeight.normal,
            ),
          ),
        );
      }

      final labelPainter = TextPainter(
        text: TextSpan(children: textSpans),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: max(10.0, w * 0.75));

      labelPainter.paint(
        canvas,
        Offset((w - labelPainter.width) / 2, (h - labelPainter.height) / 2),
      );
    }
  }

  static void _paintGroup(Canvas canvas, CanvasNode node) {
    final payload = node.payload as GroupPayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);

    final borderPaint = Paint()
      ..color = const Color(0xFFD97706).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(rect, borderPaint);

    final textSpan = TextSpan(
      text: '📁 ${payload.name}',
      style: const TextStyle(
        color: Color(0xFFD97706),
        fontSize: 10.0,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(4, -14));
  }

  static void _paintFrame(Canvas canvas, CanvasNode node) {
    final payload = node.payload as FramePayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(payload.cornerRadius),
    );

    // Shadow
    if (payload.hasShadow) {
      final shadowPaint = Paint()
        ..color = payload.shadowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, payload.shadowBlur);
      canvas.drawRRect(rrect.shift(const Offset(0, 4)), shadowPaint);
    }

    // Background (Solid or Gradient)
    final bgPaint = Paint()..style = PaintingStyle.fill;
    if (payload.backgroundGradientEnd != null) {
      bgPaint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [payload.background, payload.backgroundGradientEnd!],
      ).createShader(rect);
    } else {
      bgPaint.color = payload.background;
    }

    if (payload.cornerRadius > 0) {
      canvas.drawRRect(rrect, bgPaint);
    } else {
      canvas.drawRect(rect, bgPaint);
    }

    // Border / Stroke
    final borderPaint = Paint()
      ..color = payload.borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = payload.borderWidth;

    if (payload.isDashedBorder) {
      final path = Path();
      if (payload.cornerRadius > 0) {
        path.addRRect(rrect);
      } else {
        path.addRect(rect);
      }
      _drawDashedPath(canvas, path, borderPaint, dashWidth: 6, dashSpace: 4);
    } else {
      if (payload.cornerRadius > 0) {
        canvas.drawRRect(rrect, borderPaint);
      } else {
        canvas.drawRect(rect, borderPaint);
      }
    }

    // Figma-style Auto-Layout Guides (Padding box & direction flow dividers in red/coral)
    if (payload.layoutDirection != AutoLayoutDirection.none) {
      _paintAutoLayoutGuides(canvas, node, payload, rect);
    }

    // Top-left Frame Label Tag & Auto-layout Indicator (Figma style)
    String labelText = node.name ?? payload.name;
    if (payload.layoutDirection == AutoLayoutDirection.horizontal) {
      labelText =
          '$labelText  [||| ROW · ${payload.layoutAlign.name.toUpperCase()}]';
    } else if (payload.layoutDirection == AutoLayoutDirection.vertical) {
      labelText =
          '$labelText  [=== COL · ${payload.layoutAlign.name.toUpperCase()}]';
    }

    final textSpan = TextSpan(
      text: labelText,
      style: TextStyle(
        color: payload.layoutDirection != AutoLayoutDirection.none
            ? const Color(0xFFEF4444)
            : const Color(0xFF94A3B8),
        fontSize: 12.0,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(4, -18));
  }

  static void _paintAutoLayoutGuides(
    Canvas canvas,
    CanvasNode node,
    FramePayload payload,
    Rect rect,
  ) {
    const guideRed = Color(0xFFEF4444);
    final isHorizontal =
        payload.layoutDirection == AutoLayoutDirection.horizontal;

    // 1. Padding Content Box (dashed red boundary)
    final contentRect = Rect.fromLTRB(
      payload.paddingLeft,
      payload.paddingTop,
      node.width - payload.paddingRight,
      node.height - payload.paddingBottom,
    );

    if (contentRect.width > 0 && contentRect.height > 0) {
      // Soft red padding tint
      final padFill = Paint()
        ..color = guideRed.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill;
      canvas.drawRect(contentRect, padFill);

      final padStroke = Paint()
        ..color = guideRed.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      final padPath = Path()..addRect(contentRect);
      _drawDashedPath(canvas, padPath, padStroke, dashWidth: 4, dashSpace: 3);

      // 2. Draw Figma-style alignment axis and item slot guides
      final trackStroke = Paint()
        ..color = guideRed.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      final spacing = payload.itemSpacing;

      if (isHorizontal) {
        // Draw cross-axis center alignment line
        final midY = contentRect.top + contentRect.height / 2;
        final axisPath = Path()
          ..moveTo(contentRect.left, midY)
          ..lineTo(contentRect.right, midY);
        _drawDashedPath(
          canvas,
          axisPath,
          trackStroke,
          dashWidth: 4,
          dashSpace: 4,
        );

        // Draw slots based on Alignment
        const slotWidth = 70.0;
        double startX = contentRect.left;
        const totalSpan = slotWidth * 3 + 2 * 16.0;
        if (payload.layoutAlign == AutoLayoutAlign.center) {
          startX =
              contentRect.left +
              (contentRect.width - totalSpan).clamp(0.0, double.infinity) / 2;
        } else if (payload.layoutAlign == AutoLayoutAlign.end) {
          startX = contentRect.right - totalSpan.clamp(0.0, contentRect.width);
        }

        double x = startX;
        while (x < contentRect.right && x >= contentRect.left) {
          final slotPath = Path()
            ..moveTo(x, contentRect.top)
            ..lineTo(x, contentRect.bottom);
          _drawDashedPath(
            canvas,
            slotPath,
            trackStroke,
            dashWidth: 3,
            dashSpace: 3,
          );
          x += slotWidth + spacing;
        }
      } else {
        // Draw cross-axis center alignment line
        final midX = contentRect.left + contentRect.width / 2;
        final axisPath = Path()
          ..moveTo(midX, contentRect.top)
          ..lineTo(midX, contentRect.bottom);
        _drawDashedPath(
          canvas,
          axisPath,
          trackStroke,
          dashWidth: 4,
          dashSpace: 4,
        );

        // Draw slots based on Alignment
        const slotHeight = 50.0;
        double startY = contentRect.top;
        const totalSpan = slotHeight * 3 + 2 * 16.0;
        if (payload.layoutAlign == AutoLayoutAlign.center) {
          startY =
              contentRect.top +
              (contentRect.height - totalSpan).clamp(0.0, double.infinity) / 2;
        } else if (payload.layoutAlign == AutoLayoutAlign.end) {
          startY =
              contentRect.bottom - totalSpan.clamp(0.0, contentRect.height);
        }

        double y = startY;
        while (y < contentRect.bottom && y >= contentRect.top) {
          final slotPath = Path()
            ..moveTo(contentRect.left, y)
            ..lineTo(contentRect.right, y);
          _drawDashedPath(
            canvas,
            slotPath,
            trackStroke,
            dashWidth: 3,
            dashSpace: 3,
          );
          y += slotHeight + spacing;
        }
      }
    }
  }

  static void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dashWidth = 5.0,
    double dashSpace = 3.0,
  }) {
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double len = (distance + dashWidth < metric.length)
            ? dashWidth
            : metric.length - distance;
        final extract = metric.extractPath(distance, distance + len);
        canvas.drawPath(extract, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  static void _paintImage(
    Canvas canvas,
    CanvasNode node, {
    required CanvasImageCache imageCache,
  }) {
    final payload = node.payload is ImagePayload
        ? node.payload as ImagePayload
        : ImagePayload();
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);

    // Calculate corner radius RRect
    final RRect rrect;
    if (payload.independentCorners) {
      rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: Radius.circular(payload.topLeftRadius),
        topRight: Radius.circular(payload.topRightRadius),
        bottomRight: Radius.circular(payload.bottomRightRadius),
        bottomLeft: Radius.circular(payload.bottomLeftRadius),
      );
    } else {
      rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(payload.cornerRadius),
      );
    }

    // Drop shadow
    if (payload.hasShadow && payload.shadowBlur > 0) {
      final shadowPaint = Paint()
        ..color = payload.shadowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, payload.shadowBlur);
      canvas.save();
      canvas.translate(payload.shadowOffsetX, payload.shadowOffsetY);
      canvas.drawRRect(rrect, shadowPaint);
      canvas.restore();
    }

    final imageKey =
        (payload.imageArtifactReference != null &&
            payload.imageArtifactReference!.isNotEmpty)
        ? payload.imageArtifactReference
        : (payload.storagePath != null && payload.storagePath!.isNotEmpty)
        ? payload.storagePath
        : (payload.localPath != null && payload.localPath!.isNotEmpty)
        ? payload.localPath
        : payload.url;
    ui.Image? cachedImg;
    if (imageKey != null && imageKey.isNotEmpty) {
      cachedImg = imageCache.getImage(imageKey);
      if (cachedImg == null) {
        imageCache.requestImage(
          storagePath: payload.storagePath,
          localPath: payload.localPath,
          url: payload.url,
          imageArtifactReference: payload.imageArtifactReference,
        );
      }
    }

    ui.Image? cachedMask;
    final backgroundMask = payload.backgroundMask;
    final maskKey = backgroundMask?.sourceKey;
    if (backgroundMask != null &&
        backgroundMask.enabled &&
        maskKey != null &&
        maskKey.isNotEmpty) {
      cachedMask = imageCache.getImage(maskKey);
      if (cachedMask == null) {
        imageCache.requestImage(
          storagePath: backgroundMask.storagePath,
          localPath: backgroundMask.localPath,
          url: backgroundMask.url,
          imageArtifactReference: backgroundMask.imageArtifactReference,
        );
      }
    }

    // Clip to rounded borders
    canvas.save();
    canvas.clipRRect(rrect);

    if (cachedImg != null) {
      // Setup image paint with filter effects
      final imagePaint = Paint();

      // Flips
      if (payload.flipHorizontal || payload.flipVertical) {
        canvas.translate(
          payload.flipHorizontal ? node.width : 0,
          payload.flipVertical ? node.height : 0,
        );
        canvas.scale(
          payload.flipHorizontal ? -1 : 1,
          payload.flipVertical ? -1 : 1,
        );
      }

      // Matrix color filter (Grayscale, Sepia, Invert, Brightness, Contrast)
      final matrix = _calculateColorFilterMatrix(payload);
      if (matrix != null) {
        imagePaint.colorFilter = ColorFilter.matrix(matrix);
      }

      // Blur filter
      final effectiveBlur = _effectiveBlur(payload);
      if (effectiveBlur > 0) {
        imagePaint.imageFilter = ui.ImageFilter.blur(
          sigmaX: effectiveBlur,
          sigmaY: effectiveBlur,
          tileMode: TileMode.clamp,
        );
      }

      // Calculate source & destination rect based on BoxFit & crop factors
      final srcRect = _imageCropRect(payload, cachedImg);

      final dstRect = _applyBoxFit(
        payload.fit,
        srcRect.size,
        rect.size,
        focalPointX: payload.focalPointX,
        focalPointY: payload.focalPointY,
      );

      final maskIsReady =
          backgroundMask != null &&
          backgroundMask.enabled &&
          cachedMask != null;
      if (maskIsReady) {
        canvas.saveLayer(rect, Paint());
      }
      canvas.drawImageRect(cachedImg, srcRect, dstRect, imagePaint);
      if (maskIsReady) {
        final maskImage = cachedMask;
        final maskSrcRect = _imageCropRect(payload, maskImage);
        final maskPaint = Paint()
          ..blendMode = BlendMode.dstIn
          ..colorFilter = ColorFilter.matrix(
            _maskColorFilterMatrix(backgroundMask.mode, backgroundMask.opacity),
          );
        canvas.drawImageRect(maskImage, maskSrcRect, dstRect, maskPaint);
        canvas.restore();
      }
    } else {
      // Placeholder background when loading or without image
      final bgPaint = Paint()..color = const Color(0xFF262C38);
      canvas.drawRect(rect, bgPaint);

      // Grid background accent
      final linePaint = Paint()
        ..color = const Color(0xFF333C4D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawLine(
        const Offset(0, 0),
        Offset(node.width, node.height),
        linePaint,
      );
      canvas.drawLine(Offset(0, node.height), Offset(node.width, 0), linePaint);

      // Placeholder icon & label
      final textSpan = TextSpan(
        text:
            (payload.imageArtifactReference != null ||
                payload.storagePath != null ||
                payload.localPath != null ||
                payload.url != null)
            ? '⏳ Loading Image...'
            : '🖼 Image Asset\n(Double-click or Inspector to edit)',
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 11.0,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: max(10.0, node.width - 24));

      textPainter.paint(
        canvas,
        Offset(
          (node.width - textPainter.width) / 2,
          (node.height - textPainter.height) / 2,
        ),
      );
    }

    // Caption overlay at bottom
    if (payload.caption != null && payload.caption!.isNotEmpty) {
      const captionHeight = 24.0;
      final captionBar = Rect.fromLTWH(
        0,
        node.height - captionHeight,
        node.width,
        captionHeight,
      );
      canvas.drawRect(
        captionBar,
        Paint()..color = Colors.black.withValues(alpha: 0.65),
      );

      final captionSpan = TextSpan(
        text: payload.caption!,
        style: const TextStyle(
          color: Color(0xFFF3F4F6),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      );
      final captionPainter = TextPainter(
        text: captionSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: max(10.0, node.width - 16));
      captionPainter.paint(
        canvas,
        Offset(
          8,
          node.height -
              captionHeight +
              (captionHeight - captionPainter.height) / 2,
        ),
      );
    }

    canvas.restore();

    // Border Stroke
    if (payload.strokeColor != null && payload.strokeWidth > 0) {
      final borderPaint = Paint()
        ..color = payload.strokeColor!
        ..style = PaintingStyle.stroke
        ..strokeWidth = payload.strokeWidth;

      if (payload.strokeStyle == StrokeStyle.dashed) {
        final path = Path()..addRRect(rrect);
        _drawDashedPath(canvas, path, borderPaint, dashWidth: 6, dashSpace: 4);
      } else if (payload.strokeStyle == StrokeStyle.dotted) {
        final path = Path()..addRRect(rrect);
        _drawDashedPath(canvas, path, borderPaint, dashWidth: 2, dashSpace: 3);
      } else {
        canvas.drawRRect(rrect, borderPaint);
      }
    }
  }

  static Rect _imageCropRect(ImagePayload payload, ui.Image image) {
    final sourceWidth = image.width.toDouble();
    final sourceHeight = image.height.toDouble();
    final selection = ImageCropSelection(
      x: payload.cropX,
      y: payload.cropY,
      width: payload.cropWidth,
      height: payload.cropHeight,
    ).normalized;
    final left = (selection.x * sourceWidth)
        .clamp(0.0, max(0.0, sourceWidth - 1.0))
        .toDouble();
    final top = (selection.y * sourceHeight)
        .clamp(0.0, max(0.0, sourceHeight - 1.0))
        .toDouble();
    final width = (selection.width * sourceWidth)
        .clamp(1.0, max(1.0, sourceWidth - left))
        .toDouble();
    final height = (selection.height * sourceHeight)
        .clamp(1.0, max(1.0, sourceHeight - top))
        .toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  static Rect _applyBoxFit(
    String fit,
    Size inputSize,
    Size outputSize, {
    double focalPointX = 0.5,
    double focalPointY = 0.5,
  }) {
    if (inputSize.width <= 0 ||
        inputSize.height <= 0 ||
        outputSize.width <= 0 ||
        outputSize.height <= 0) {
      return Rect.fromLTWH(0, 0, outputSize.width, outputSize.height);
    }

    final double srcW = inputSize.width;
    final double srcH = inputSize.height;
    final double dstW = outputSize.width;
    final double dstH = outputSize.height;
    final focalX = focalPointX.clamp(0.0, 1.0).toDouble();
    final focalY = focalPointY.clamp(0.0, 1.0).toDouble();

    switch (fit) {
      case 'contain':
        final double scale = min(dstW / srcW, dstH / srcH);
        final double w = srcW * scale;
        final double h = srcH * scale;
        return Rect.fromLTWH((dstW - w) * focalX, (dstH - h) * focalY, w, h);

      case 'fitWidth':
        final double scale = dstW / srcW;
        final double w = dstW;
        final double h = srcH * scale;
        return Rect.fromLTWH(0, (dstH - h) * focalY, w, h);

      case 'fitHeight':
        final double scale = dstH / srcH;
        final double w = srcW * scale;
        final double h = dstH;
        return Rect.fromLTWH((dstW - w) * focalX, 0, w, h);

      case 'fill':
        return Rect.fromLTWH(0, 0, dstW, dstH);

      case 'cover':
      default:
        final double scale = max(dstW / srcW, dstH / srcH);
        final double w = srcW * scale;
        final double h = srcH * scale;
        return Rect.fromLTWH((dstW - w) * focalX, (dstH - h) * focalY, w, h);
    }
  }

  static List<double>? _calculateColorFilterMatrix(ImagePayload p) {
    final enabledAdjustments = p.adjustments.where(
      (adjustment) =>
          adjustment.enabled && adjustment.type != ImageAdjustmentType.blur,
    );
    if (!p.grayscale &&
        !p.sepia &&
        !p.invert &&
        p.brightness == 0.0 &&
        p.contrast == 1.0 &&
        enabledAdjustments.isEmpty) {
      return null;
    }

    // Base identity matrix with brightness & contrast
    // c' = (c - 0.5) * contrast + 0.5 + brightness * 255
    final double c = p.contrast;
    final double b = (p.brightness * 255.0) + (1.0 - c) * 128.0;

    List<double> matrix = [
      c,
      0,
      0,
      0,
      b,
      0,
      c,
      0,
      0,
      b,
      0,
      0,
      c,
      0,
      b,
      0,
      0,
      0,
      1,
      0,
    ];

    if (p.grayscale) {
      matrix = _multiplyMatrices(matrix, const [
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);
    }

    if (p.sepia) {
      matrix = _multiplyMatrices(matrix, const [
        0.393,
        0.769,
        0.189,
        0,
        0,
        0.349,
        0.686,
        0.168,
        0,
        0,
        0.272,
        0.534,
        0.131,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);
    }

    if (p.invert) {
      matrix = _multiplyMatrices(matrix, const [
        -1,
        0,
        0,
        0,
        255,
        0,
        -1,
        0,
        0,
        255,
        0,
        0,
        -1,
        0,
        255,
        0,
        0,
        0,
        1,
        0,
      ]);
    }

    for (final adjustment in enabledAdjustments) {
      final adjustmentMatrix = _adjustmentColorFilterMatrix(adjustment);
      if (adjustmentMatrix != null) {
        matrix = _multiplyMatrices(matrix, adjustmentMatrix);
      }
    }

    return matrix;
  }

  static double _effectiveBlur(ImagePayload payload) {
    var blur = payload.blur;
    for (final adjustment in payload.adjustments) {
      if (adjustment.enabled && adjustment.type == ImageAdjustmentType.blur) {
        blur += max(0.0, adjustment.amount);
      }
    }
    return blur;
  }

  static List<double>? _adjustmentColorFilterMatrix(
    ImageAdjustment adjustment,
  ) {
    final amount = adjustment.amount;
    switch (adjustment.type) {
      case ImageAdjustmentType.brightness:
        return [
          1,
          0,
          0,
          0,
          amount * 255,
          0,
          1,
          0,
          0,
          amount * 255,
          0,
          0,
          1,
          0,
          amount * 255,
          0,
          0,
          0,
          1,
          0,
        ];
      case ImageAdjustmentType.contrast:
        final contrast = amount.clamp(0.0, 4.0).toDouble();
        final offset = (1.0 - contrast) * 128.0;
        return [
          contrast,
          0,
          0,
          0,
          offset,
          0,
          contrast,
          0,
          0,
          offset,
          0,
          0,
          contrast,
          0,
          offset,
          0,
          0,
          0,
          1,
          0,
        ];
      case ImageAdjustmentType.saturation:
        final saturation = amount.clamp(0.0, 4.0).toDouble();
        final inverse = 1.0 - saturation;
        final red = 0.2126 * inverse;
        final green = 0.7152 * inverse;
        final blue = 0.0722 * inverse;
        return [
          red + saturation,
          green,
          blue,
          0,
          0,
          red,
          green + saturation,
          blue,
          0,
          0,
          red,
          green,
          blue + saturation,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ];
      case ImageAdjustmentType.exposure:
        final factor = pow(2.0, amount).toDouble();
        return [
          factor,
          0,
          0,
          0,
          0,
          0,
          factor,
          0,
          0,
          0,
          0,
          0,
          factor,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ];
      case ImageAdjustmentType.temperature:
        final shift = amount.clamp(-1.0, 1.0).toDouble() * 64.0;
        return [
          1,
          0,
          0,
          0,
          shift,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          -shift,
          0,
          0,
          0,
          1,
          0,
        ];
      case ImageAdjustmentType.highlights:
      case ImageAdjustmentType.shadows:
        final lift = amount.clamp(-1.0, 1.0).toDouble() * 80.0;
        return [
          1,
          0,
          0,
          0,
          lift,
          0,
          1,
          0,
          0,
          lift,
          0,
          0,
          1,
          0,
          lift,
          0,
          0,
          0,
          1,
          0,
        ];
      case ImageAdjustmentType.grayscale:
        final strength = amount.clamp(0.0, 1.0).toDouble();
        final inverse = 1.0 - strength;
        return [
          0.2126 * strength + inverse,
          0.7152 * strength,
          0.0722 * strength,
          0,
          0,
          0.2126 * strength,
          0.7152 * strength + inverse,
          0.0722 * strength,
          0,
          0,
          0.2126 * strength,
          0.7152 * strength,
          0.0722 * strength + inverse,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ];
      case ImageAdjustmentType.sepia:
        final strength = amount.clamp(0.0, 1.0).toDouble();
        final inverse = 1.0 - strength;
        return [
          0.393 * strength + inverse,
          0.769 * strength,
          0.189 * strength,
          0,
          0,
          0.349 * strength,
          0.686 * strength + inverse,
          0.168 * strength,
          0,
          0,
          0.272 * strength,
          0.534 * strength,
          0.131 * strength + inverse,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ];
      case ImageAdjustmentType.invert:
        final strength = amount.clamp(0.0, 1.0).toDouble();
        return [
          1 - 2 * strength,
          0,
          0,
          0,
          255 * strength,
          0,
          1 - 2 * strength,
          0,
          0,
          255 * strength,
          0,
          0,
          1 - 2 * strength,
          0,
          255 * strength,
          0,
          0,
          0,
          1,
          0,
        ];
      case ImageAdjustmentType.opacity:
        final opacity = amount.clamp(0.0, 1.0).toDouble();
        return [
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
          opacity,
          0,
        ];
      case ImageAdjustmentType.blur:
        return null;
    }
  }

  static List<double> _maskColorFilterMatrix(
    ImageMaskMode mode,
    double opacity,
  ) {
    final alpha = opacity.clamp(0.0, 1.0).toDouble();
    switch (mode) {
      case ImageMaskMode.alpha:
        return [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, alpha, 0];
      case ImageMaskMode.luminance:
        return [
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
          0.2126 * alpha,
          0.7152 * alpha,
          0.0722 * alpha,
          0,
          0,
        ];
      case ImageMaskMode.invertedLuminance:
        return [
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
          -0.2126 * alpha,
          -0.7152 * alpha,
          -0.0722 * alpha,
          0,
          255 * alpha,
        ];
    }
  }

  static List<double> _multiplyMatrices(List<double> m1, List<double> m2) {
    final result = List<double>.filled(20, 0.0);
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) {
          sum += m1[row * 5 + k] * m2[k * 5 + col];
        }
        result[row * 5 + col] = sum;
      }
      // Offset addition
      result[row * 5 + 4] =
          m1[row * 5 + 0] * m2[4] +
          m1[row * 5 + 1] * m2[9] +
          m1[row * 5 + 2] * m2[14] +
          m1[row * 5 + 3] * m2[19] +
          m1[row * 5 + 4];
    }
    return result;
  }

  // -------------------------------------------------------------
  // INFINITE BOARD - CONTENT NODES RENDERERS
  // -------------------------------------------------------------

  static Color _getFileTypeBadgeColor(String ext) {
    final clean = ext.replaceAll('.', '').toLowerCase();
    switch (clean) {
      case 'pdf':
        return const Color(0xFFEF4444); // Red
      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
      case 'odt':
        return const Color(0xFF3B82F6); // Blue
      case 'xls':
      case 'xlsx':
      case 'csv':
      case 'numbers':
        return const Color(0xFF10B981); // Green
      case 'ppt':
      case 'pptx':
      case 'keynote':
        return const Color(0xFFF97316); // Orange
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return const Color(0xFFA855F7); // Purple
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'html':
      case 'css':
      case 'js':
      case 'ts':
      case 'dart':
      case 'py':
      case 'cpp':
      case 'c':
      case 'java':
        return const Color(0xFF06B6D4); // Cyan
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'm4a':
      case 'flac':
        return const Color(0xFFEC4899); // Pink
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
        return const Color(0xFFE11D48); // Rose
      case 'fig':
      case 'sketch':
      case 'psd':
      case 'ai':
        return const Color(0xFF8B5CF6); // Indigo
      default:
        return const Color(0xFF6B7280); // Gray
    }
  }

  static void _paintFileCard(Canvas canvas, CanvasNode node) {
    final payload = node.payload as FilePayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(payload.cornerRadius),
    );

    // Shadow
    if (payload.hasShadow && payload.shadowBlur > 0) {
      final shadowPaint = Paint()
        ..color = payload.shadowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, payload.shadowBlur);
      canvas.drawRRect(rrect.shift(const Offset(0, 3)), shadowPaint);
    }

    // Background
    final bgPaint = Paint()..color = payload.backgroundColor;
    canvas.drawRRect(rrect, bgPaint);

    // Border
    if (payload.borderWidth > 0) {
      final borderPaint = Paint()
        ..color = payload.borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = payload.borderWidth;
      canvas.drawRRect(rrect, borderPaint);
    }

    // Badge color
    final badgeColor =
        payload.customBadgeColor ??
        _getFileTypeBadgeColor(payload.fileExtension);
    final badgeH = min(44.0, max(28.0, node.height - 24));
    final badgeW = badgeH;
    const badgeMargin = 12.0;

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeMargin, (node.height - badgeH) / 2, badgeW, badgeH),
      Radius.circular(max(4.0, payload.cornerRadius / 2)),
    );
    final badgePaint = Paint()..color = badgeColor;
    canvas.drawRRect(badgeRect, badgePaint);

    // Badge Text (Extension)
    String extText = payload.fileExtension.toUpperCase().replaceAll('.', '');
    if (extText.length > 5) extText = extText.substring(0, 5);
    final extSpan = TextSpan(
      text: extText.isEmpty ? 'FILE' : extText,
      style: TextStyle(
        color: Colors.white,
        fontSize: badgeW > 36 ? 11 : 9,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
    final extPainter = TextPainter(
      text: extSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    extPainter.paint(
      canvas,
      Offset(
        badgeMargin + (badgeW - extPainter.width) / 2,
        (node.height - extPainter.height) / 2,
      ),
    );

    final leftOffset = badgeMargin + badgeW + 12;
    final textMaxWidth = max(20.0, node.width - leftOffset - 16);

    final hasDesc =
        payload.description != null && payload.description!.trim().isNotEmpty;

    // File name
    final nameSpan = TextSpan(
      text: payload.fileName,
      style: const TextStyle(
        color: Color(0xFFF3F4F6),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
    final namePainter = TextPainter(
      text: nameSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '..',
    )..layout(maxWidth: textMaxWidth);

    if (node.height >= 75 && hasDesc) {
      namePainter.paint(canvas, Offset(leftOffset, 12));

      final descSpan = TextSpan(
        text: payload.description!,
        style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 10),
      );
      final descPainter = TextPainter(
        text: descSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '..',
      )..layout(maxWidth: textMaxWidth);
      descPainter.paint(canvas, Offset(leftOffset, 30));

      final sizeSpan = TextSpan(
        text: payload.fileSizeText,
        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10),
      );
      final sizePainter = TextPainter(
        text: sizeSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      sizePainter.paint(canvas, Offset(leftOffset, 46));
    } else {
      namePainter.paint(
        canvas,
        Offset(leftOffset, max(8.0, (node.height / 2) - 18)),
      );

      final sizeSpan = TextSpan(
        text: payload.fileSizeText,
        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
      );
      final sizePainter = TextPainter(
        text: sizeSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      sizePainter.paint(
        canvas,
        Offset(leftOffset, max(26.0, (node.height / 2) + 2)),
      );
    }
  }

  static void _paintModel3D(Canvas canvas, CanvasNode node) {
    final payload = node.payload is Model3DPayload
        ? node.payload as Model3DPayload
        : Model3DPayload();
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF172033));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    canvas.save();
    canvas.clipRRect(rrect);
    final gridPaint = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double x = 0; x < node.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, node.height), gridPaint);
    }
    for (double y = 0; y < node.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(node.width, y), gridPaint);
    }
    canvas.restore();

    final center = Offset(node.width / 2, node.height / 2 - 8);
    final cube = Path()
      ..moveTo(center.dx, center.dy - 38)
      ..lineTo(center.dx + 34, center.dy - 18)
      ..lineTo(center.dx + 34, center.dy + 20)
      ..lineTo(center.dx, center.dy + 40)
      ..lineTo(center.dx - 34, center.dy + 20)
      ..lineTo(center.dx - 34, center.dy - 18)
      ..close();
    canvas.drawPath(cube, Paint()..color = const Color(0xFF0EA5E9));
    canvas.drawLine(
      Offset(center.dx, center.dy - 38),
      Offset(center.dx, center.dy + 40),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      Offset(center.dx - 34, center.dy - 18),
      Offset(center.dx, center.dy),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      Offset(center.dx + 34, center.dy - 18),
      Offset(center.dx, center.dy),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 1.2,
    );

    final title = TextPainter(
      text: TextSpan(
        text: payload.displayName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: max(24, node.width - 24));
    title.paint(canvas, Offset(12, max(8, node.height - 34)));

    final subtitle = TextPainter(
      text: TextSpan(
        text: payload.sourceError?.trim().isNotEmpty == true
            ? 'Interactive preview unavailable'
            : 'GLB • ${payload.fileSizeText}',
        style: TextStyle(
          color: payload.sourceError?.trim().isNotEmpty == true
              ? const Color(0xFFFBBF24)
              : const Color(0xFFBAE6FD),
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: max(24, node.width - 24));
    subtitle.paint(canvas, Offset(12, max(8, node.height - 18)));
  }

  static void _paintLinkCard(Canvas canvas, CanvasNode node) {
    final payload = node.payload as LinkPayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    final bgPaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRRect(rrect, bgPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(rrect, borderPaint);

    // Title
    final titleSpan = TextSpan(
      text: '🔗 ${payload.title}',
      style: const TextStyle(
        color: Color(0xFF38BDF8),
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '..',
    )..layout(maxWidth: max(10, node.width - 24));
    titlePainter.paint(canvas, const Offset(12, 12));

    // URL
    final urlSpan = TextSpan(
      text: payload.url,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 11,
        decoration: TextDecoration.underline,
      ),
    );
    final urlPainter = TextPainter(
      text: urlSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '..',
    )..layout(maxWidth: max(10, node.width - 24));
    urlPainter.paint(canvas, const Offset(12, 32));

    // Description
    if (payload.description != null &&
        payload.description!.isNotEmpty &&
        node.height > 65) {
      final descSpan = TextSpan(
        text: payload.description!,
        style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
      );
      final descPainter = TextPainter(
        text: descSpan,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '..',
      )..layout(maxWidth: max(10, node.width - 24));
      descPainter.paint(canvas, const Offset(12, 52));
    }
  }

  static void _paintVideoCard(
    Canvas canvas,
    CanvasNode node, {
    required CanvasImageCache imageCache,
  }) {
    final payload = node.payload as VideoPayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    final bgPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRRect(rrect, bgPaint);

    final posterKey =
        payload.posterArtifactReference ??
        payload.posterStoragePath ??
        payload.posterPath ??
        payload.posterUrl;
    if (posterKey != null && posterKey.isNotEmpty) {
      final poster = imageCache.getImage(posterKey);
      if (poster == null) {
        imageCache.requestImage(
          storagePath: payload.posterStoragePath,
          localPath: payload.posterPath,
          url: payload.posterUrl,
          imageArtifactReference: payload.posterArtifactReference,
        );
      } else {
        canvas.save();
        canvas.clipRRect(rrect);
        final src = Rect.fromLTWH(
          0,
          0,
          poster.width.toDouble(),
          poster.height.toDouble(),
        );
        final dst = _applyBoxFit('cover', src.size, rect.size);
        canvas.drawImageRect(poster, src, dst, Paint());
        canvas.restore();
      }
    }

    if (payload.sourceError != null && payload.sourceError!.isNotEmpty) {
      final errorPainter = TextPainter(
        text: TextSpan(
          text: payload.sourceError,
          style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: max(10, node.width - 32));
      errorPainter.paint(
        canvas,
        Offset(16, node.height / 2 - errorPainter.height / 2),
      );
    }

    // Center Play Icon Button
    final center = Offset(node.width / 2, node.height / 2 - 8);
    final playBgPaint = Paint()..color = const Color(0xFFF97316);
    canvas.drawCircle(center, 20, playBgPaint);

    final playPath = Path()
      ..moveTo(center.dx - 5, center.dy - 8)
      ..lineTo(center.dx + 8, center.dy)
      ..lineTo(center.dx - 5, center.dy + 8)
      ..close();
    canvas.drawPath(playPath, Paint()..color = Colors.white);

    if (payload.caption != null && payload.caption!.trim().isNotEmpty) {
      final descriptionPainter = TextPainter(
        text: TextSpan(
          text: payload.caption!.trim(),
          style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: max(10, node.width - 16));
      final descriptionTop = max(8.0, node.height - 54.0);
      canvas.drawRect(
        Rect.fromLTWH(0, descriptionTop - 4, node.width, 24),
        Paint()..color = Colors.black54,
      );
      descriptionPainter.paint(canvas, Offset(8, descriptionTop));
    }

    // Title and Duration bottom bar
    final barRect = Rect.fromLTWH(0, node.height - 30, node.width, 30);
    canvas.drawRect(barRect, Paint()..color = Colors.black45);

    final titleSpan = TextSpan(
      text: '▶ ${payload.title}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: max(10, node.width - 60));
    titlePainter.paint(canvas, Offset(8, node.height - 22));

    final durSpan = TextSpan(
      text: payload.durationText,
      style: const TextStyle(
        color: Color(0xFFF97316),
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
    final durPainter = TextPainter(
      text: durSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    durPainter.paint(
      canvas,
      Offset(node.width - durPainter.width - 8, node.height - 22),
    );
  }

  static void _paintAudioCard(Canvas canvas, CanvasNode node) {
    final payload = node.payload as AudioPayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    final bgPaint = Paint()..color = const Color(0xFF18181B);
    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Audio waves visualizer bars
    final wavePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    const barCount = 14;
    final startX = node.width - (barCount * 7.0) - 12;
    for (int i = 0; i < barCount; i++) {
      final h = sin(i * 0.8) * 12 + 14;
      canvas.drawLine(
        Offset(startX + i * 7, node.height / 2 - h / 2),
        Offset(startX + i * 7, node.height / 2 + h / 2),
        wavePaint,
      );
    }

    final trackSpan = TextSpan(
      text: '🎵 ${payload.trackName}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
    final trackPainter = TextPainter(
      text: trackSpan,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: max(10, startX - 18));
    trackPainter.paint(canvas, const Offset(12, 14));

    final artistSpan = TextSpan(
      text: '${payload.artist} • ${payload.durationText}',
      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10),
    );
    final artistPainter = TextPainter(
      text: artistSpan,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: max(10, startX - 18));
    artistPainter.paint(canvas, const Offset(12, 34));
  }

  static void _paintMapCard(Canvas canvas, CanvasNode node) {
    final payload = node.payload as MapPayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    // Map background simulated grid
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF1E293B));
    final gridPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1;
    for (double gx = 0; gx < node.width; gx += 30) {
      canvas.drawLine(Offset(gx, 0), Offset(gx, node.height), gridPaint);
    }
    for (double gy = 0; gy < node.height; gy += 30) {
      canvas.drawLine(Offset(0, gy), Offset(node.width, gy), gridPaint);
    }

    final hasLocation =
        payload.locationTitle.trim().isNotEmpty ||
        payload.address.trim().isNotEmpty;
    if (!hasLocation) {
      final emptyPainter = TextPainter(
        text: const TextSpan(
          text: 'Set location',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: max(10, node.width - 24));
      emptyPainter.paint(
        canvas,
        Offset(
          (node.width - emptyPainter.width) / 2,
          (node.height - emptyPainter.height) / 2,
        ),
      );
      return;
    }

    final center = Offset(node.width / 2, node.height / 2 - 10);
    canvas.drawCircle(center, 12, Paint()..color = const Color(0xFFEF4444));
    canvas.drawCircle(center, 4, Paint()..color = Colors.white);

    final tagRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(node.width / 2, node.height / 2 + 18),
        width: node.width - 24,
        height: 22,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(tagRect, Paint()..color = Colors.black87);

    final titleSpan = TextSpan(
      text:
          '📍 ${payload.locationTitle.trim().isEmpty ? payload.address : payload.locationTitle}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '..',
    )..layout(maxWidth: max(10, node.width - 32));
    titlePainter.paint(
      canvas,
      Offset((node.width - titlePainter.width) / 2, node.height / 2 + 12),
    );
  }

  static void _paintColorSwatch(Canvas canvas, CanvasNode node) {
    final payload = node.payload as ColorSwatchPayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF1E2026));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF373A44)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Color sample box
    final sampleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, node.width, max(20.0, node.height - 40)),
      const Radius.circular(6),
    );
    canvas.drawRRect(sampleRect, Paint()..color = payload.color);

    // Label and Hex string
    final hexSpan = TextSpan(
      text: payload.colorHex,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
    final hexPainter = TextPainter(
      text: hexSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    hexPainter.paint(canvas, Offset(8, node.height - 34));

    final labelSpan = TextSpan(
      text: payload.label,
      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10),
    );
    final labelPainter = TextPainter(
      text: labelSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(canvas, Offset(8, node.height - 18));
  }

  // -------------------------------------------------------------
  // INFINITE BOARD - CREATIVE NODES RENDERERS
  // -------------------------------------------------------------

  static void _paintSketchCard(Canvas canvas, CanvasNode node) {
    final payload = node.payload as SketchCardPayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

    // 1. Background
    canvas.drawRRect(rrect, Paint()..color = payload.backgroundColor);

    // 2. Card Patterns (Dots or Grid)
    if (payload.cardPattern == 'dots') {
      final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.08);
      const spacing = 16.0;
      for (double x = 16.0; x < node.width - 8.0; x += spacing) {
        for (double y = 32.0; y < node.height - 8.0; y += spacing) {
          canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
        }
      }
    } else if (payload.cardPattern == 'grid') {
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      const spacing = 20.0;
      for (double x = 20.0; x < node.width; x += spacing) {
        canvas.drawLine(Offset(x, 28), Offset(x, node.height - 4), gridPaint);
      }
      for (double y = 40.0; y < node.height; y += spacing) {
        canvas.drawLine(Offset(8, y), Offset(node.width - 8, y), gridPaint);
      }
    }

    // 3. Card Border
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = payload.strokeColor.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // 4. Header title badge
    final titleSpan = TextSpan(
      text: '✏ ${payload.title}',
      style: TextStyle(
        color: payload.strokeColor,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.2,
      ),
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    titlePainter.paint(canvas, const Offset(10, 8));

    // 5. Internal Multi-Strokes Rendering with Smooth/Linear option & Clip to Card Bounds
    if (payload.strokes.isNotEmpty) {
      canvas.save();
      canvas.clipRRect(rrect);

      final strokePaint = Paint()
        ..color = payload.strokeColor
        ..strokeWidth = payload.strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      for (final stroke in payload.strokes) {
        if (stroke.isEmpty) continue;
        final Path path;
        if (payload.smoothCurves) {
          path = BrushPathSmoother.buildSmoothPath(stroke);
        } else {
          path = BrushPathSmoother.buildLinearPath(stroke);
        }
        canvas.drawPath(path, strokePaint);
      }

      canvas.restore();
    }
  }

  static void _paintAnnotatedImage(Canvas canvas, CanvasNode node) {
    final payload = node.payload as AnnotatedImagePayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    // Base background & container border
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF1E293B));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF64748B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    const span = TextSpan(
      text: '📷 Annotated Visual Layer',
      style: TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, const Offset(12, 10));

    // Top-Right Corner Pin Badge Indicator placed outside top-right corner
    if (payload.showCornerBadge && payload.pins.isNotEmpty) {
      final unresolvedCount = payload.pins.where((p) => !p.isResolved).length;
      final badgeColor = unresolvedCount > 0
          ? const Color(0xFFEC4899)
          : const Color(0xFF10B981);
      final badgeWidth = unresolvedCount > 9 ? 48.0 : 40.0;
      const badgeHeight = 22.0;
      final badgeRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          node.width - badgeWidth,
          -badgeHeight - 6,
          badgeWidth,
          badgeHeight,
        ),
        topLeft: const Radius.circular(11),
        topRight: const Radius.circular(11),
        bottomLeft: const Radius.circular(11),
        bottomRight: const Radius.circular(11),
      );

      // Subtle drop shadow for outside badge
      canvas.drawRRect(
        badgeRect.shift(const Offset(0, 2)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );

      canvas.drawRRect(badgeRect, Paint()..color = badgeColor);
      canvas.drawRRect(
        badgeRect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      final badgeText = unresolvedCount > 0 ? '📌 $unresolvedCount' : '✓ All';
      final badgeSpan = TextSpan(
        text: badgeText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      final badgePainter = TextPainter(
        text: badgeSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      badgePainter.paint(
        canvas,
        Offset(
          (node.width - badgeWidth) + (badgeWidth - badgePainter.width) / 2,
          -badgeHeight - 6 + (badgeHeight - badgePainter.height) / 2,
        ),
      );
    }

    // Render pins with teardrop / modern pin marker & optional callout leader lines
    for (int i = 0; i < payload.pins.length; i++) {
      final pin = payload.pins[i];
      final pinCenter = pin.position;

      // Status color resolution
      Color markerColor = pin.color;
      if (pin.isResolved) {
        markerColor = const Color(0xFF10B981);
      } else if (pin.status == AnnotationPinStatus.issue) {
        markerColor = const Color(0xFFEF4444);
      } else if (pin.status == AnnotationPinStatus.inProgress) {
        markerColor = const Color(0xFFF59E0B);
      }

      // Draw shadow
      canvas.drawCircle(
        pinCenter.translate(0, 2),
        12,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );

      // Pin Pinhead
      final pinPaint = Paint()..color = markerColor;
      canvas.drawCircle(pinCenter, 12, pinPaint);
      canvas.drawCircle(
        pinCenter,
        12,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );

      // Pin text/index
      final pinLabel = pin.isResolved ? '✓' : '${i + 1}';
      final numSpan = TextSpan(
        text: pinLabel,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      );
      final numPainter = TextPainter(
        text: numSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      numPainter.paint(
        canvas,
        Offset(
          pinCenter.dx - numPainter.width / 2,
          pinCenter.dy - numPainter.height / 2,
        ),
      );

      // Optional mini comment preview / leader tooltip beside pin placed outside the item
      if (payload.showLeaderLines && pin.text.trim().isNotEmpty) {
        final commentText = pin.text.trim();
        final tooltipSpan = TextSpan(
          text: commentText.length > 20
              ? '${commentText.substring(0, 18)}...'
              : commentText,
          style: TextStyle(
            color: pin.isResolved ? const Color(0xFF94A3B8) : Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w500,
            decoration: pin.isResolved ? TextDecoration.lineThrough : null,
          ),
        );
        final tooltipPainter = TextPainter(
          text: tooltipSpan,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 140);
        final tooltipWidth = tooltipPainter.width + 12;
        const tooltipHeight = 18.0;

        // Position comment bubble on the outside right of the node
        final tooltipX = node.width + 18.0;
        final tooltipY = (pinCenter.dy - tooltipHeight / 2).clamp(
          -10.0,
          node.height + 10.0,
        );

        final leaderPaint = Paint()
          ..color = markerColor.withValues(alpha: 0.65)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;

        final leaderPath = Path()
          ..moveTo(pinCenter.dx, pinCenter.dy)
          ..cubicTo(
            pinCenter.dx + (tooltipX - pinCenter.dx) * 0.5,
            pinCenter.dy,
            tooltipX - 10,
            tooltipY + tooltipHeight / 2,
            tooltipX,
            tooltipY + tooltipHeight / 2,
          );
        canvas.drawPath(leaderPath, leaderPaint);

        final bubbleRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(tooltipX, tooltipY, tooltipWidth, tooltipHeight),
          const Radius.circular(4),
        );
        // Bubble drop shadow
        canvas.drawRRect(
          bubbleRect.shift(const Offset(0, 2)),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawRRect(
          bubbleRect,
          Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.95),
        );
        canvas.drawRRect(
          bubbleRect,
          Paint()
            ..color = markerColor.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
        tooltipPainter.paint(
          canvas,
          Offset(
            tooltipX + 6,
            tooltipY + (tooltipHeight - tooltipPainter.height) / 2,
          ),
        );
      }
    }
  }

  // -------------------------------------------------------------
  // INFINITE BOARD - ORGANIZATION NODES RENDERERS
  // -------------------------------------------------------------

  static void _paintColumnContainer(Canvas canvas, CanvasNode node) {
    final payload = node.payload as ColumnPayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(payload.cornerRadius),
    );

    // Drop Shadow
    if (payload.hasShadow) {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawRRect(rrect.shift(const Offset(0, 4)), shadowPaint);
    }

    // Column background & border
    canvas.drawRRect(rrect, Paint()..color = payload.backgroundColor);
    if (payload.borderWidth > 0) {
      final isWipExceeded =
          payload.wipLimit > 0 && payload.cards.length > payload.wipLimit;
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isWipExceeded
              ? const Color(0xFFEF4444)
              : payload.borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = isWipExceeded
              ? payload.borderWidth + 0.8
              : payload.borderWidth,
      );
    }

    final totalCards = payload.cards.length;
    final isWipExceeded = payload.wipLimit > 0 && totalCards > payload.wipLimit;

    // Header bar
    const headerHeight = 38.0;
    final headerRRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, node.width, headerHeight),
      topLeft: Radius.circular(payload.cornerRadius),
      topRight: Radius.circular(payload.cornerRadius),
    );
    canvas.drawRRect(
      headerRRect,
      Paint()..color = payload.headerColor.withValues(alpha: 0.22),
    );

    // Header accent left indicator pill
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 10, 3, 18),
        const Radius.circular(2),
      ),
      Paint()..color = payload.headerColor,
    );

    final wipText = payload.wipLimit > 0 ? '/${payload.wipLimit}' : '';
    final headerSpan = TextSpan(
      text: '${payload.headerTitle.toUpperCase()} ($totalCards$wipText)',
      style: TextStyle(
        color: payload.headerColor,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
      ),
    );
    final headerPainter = TextPainter(
      text: headerSpan,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: max(10, node.width - (isWipExceeded ? 46 : 24)));
    headerPainter.paint(canvas, const Offset(16, 12));

    if (isWipExceeded) {
      const warnSpan = TextSpan(text: '⚠️', style: TextStyle(fontSize: 11));
      final warnPainter = TextPainter(
        text: warnSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      warnPainter.paint(canvas, Offset(node.width - 24, 11));
    }

    if (payload.isCollapsed) {
      const collapsedSpan = TextSpan(
        text: 'Lane Collapsed • Click to open',
        style: TextStyle(
          color: Color(0xFF9CA3AF),
          fontSize: 10,
          fontStyle: FontStyle.italic,
        ),
      );
      final collapsedPainter = TextPainter(
        text: collapsedSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      collapsedPainter.paint(canvas, const Offset(16, 46));
      return;
    }

    // Filter cards
    final visibleCards = payload.cards.where((c) {
      if (payload.filterMode == 'active') return !c.isDone;
      if (payload.filterMode == 'done') return c.isDone;
      return true;
    }).toList();

    double curY = 46.0;
    for (int i = 0; i < visibleCards.length; i++) {
      final card = visibleCards[i];
      final hasMetadata =
          card.tags.isNotEmpty ||
          card.dueDate != null ||
          card.assignee != null ||
          card.description.isNotEmpty;
      final cardHeight = hasMetadata ? 48.0 : 34.0;

      if (curY + cardHeight > node.height - 8) {
        // Overflow count
        final remaining = visibleCards.length - i;
        if (remaining > 0) {
          final overflowSpan = TextSpan(
            text: '+ $remaining more card${remaining > 1 ? 's' : ''}',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          );
          final overflowPainter = TextPainter(
            text: overflowSpan,
            textDirection: TextDirection.ltr,
          )..layout();
          overflowPainter.paint(canvas, Offset(12, curY + 2));
        }
        break;
      }

      final cardRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(8, curY, node.width - 16, cardHeight),
        const Radius.circular(5),
      );

      // Card Background
      final cardBgColor =
          card.cardColor?.withValues(alpha: 0.18) ?? const Color(0xFF232630);
      canvas.drawRRect(
        cardBgColor == const Color(0xFF232630) ? cardRect : cardRect,
        Paint()..color = cardBgColor,
      );

      // Card Border / Priority accent left border
      final cardBorderColor = card.cardColor ?? const Color(0xFF353946);
      canvas.drawRRect(
        cardRect,
        Paint()
          ..color = cardBorderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      if (card.priority != ColumnCardPriority.none) {
        Color pColor = const Color(0xFF9CA3AF);
        if (card.priority == ColumnCardPriority.high) {
          pColor = const Color(0xFFEF4444);
        }
        if (card.priority == ColumnCardPriority.medium) {
          pColor = const Color(0xFFF59E0B);
        }
        if (card.priority == ColumnCardPriority.low) {
          pColor = const Color(0xFF3B82F6);
        }

        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(8, curY, 3.5, cardHeight),
            topLeft: const Radius.circular(5),
            bottomLeft: const Radius.circular(5),
          ),
          Paint()..color = pColor,
        );
      }

      // Checkbox Box
      final boxRect = Rect.fromLTWH(16, curY + (hasMetadata ? 9 : 9), 15, 15);
      final boxRRect = RRect.fromRectAndRadius(
        boxRect,
        const Radius.circular(3),
      );
      if (card.isDone) {
        canvas.drawRRect(boxRRect, Paint()..color = payload.headerColor);
        // Draw Checkmark
        final checkPath = Path()
          ..moveTo(boxRect.left + 3.5, boxRect.top + 7.5)
          ..lineTo(boxRect.left + 6.5, boxRect.top + 11.0)
          ..lineTo(boxRect.left + 11.5, boxRect.top + 4.0);
        canvas.drawPath(
          checkPath,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      } else {
        canvas.drawRRect(
          boxRRect,
          Paint()
            ..color = const Color(0xFF4B5563)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }

      // Card Title
      final titleSpan = TextSpan(
        text: card.title,
        style: TextStyle(
          color: card.isDone
              ? const Color(0xFF6B7280)
              : const Color(0xFFF3F4F6),
          fontSize: 11,
          fontWeight: FontWeight.w500,
          decoration: card.isDone ? TextDecoration.lineThrough : null,
          decorationColor: const Color(0xFF6B7280),
        ),
      );
      final titlePainter = TextPainter(
        text: titleSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: max(10, node.width - 50));
      titlePainter.paint(canvas, Offset(36, curY + 8));

      // Metadata line (Tags / Assignee / Due date / Desc preview)
      if (hasMetadata) {
        String metaText = '';
        if (card.assignee != null && card.assignee!.isNotEmpty) {
          metaText += '@${card.assignee!}  ';
        }
        if (card.dueDate != null && card.dueDate!.isNotEmpty) {
          metaText += '📅 ${card.dueDate!}  ';
        }
        if (card.tags.isNotEmpty) {
          metaText += '#${card.tags.first}  ';
        }
        if (metaText.isEmpty && card.description.isNotEmpty) {
          metaText = card.description;
        }

        final metaSpan = TextSpan(
          text: metaText.trim(),
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 9.5),
        );
        final metaPainter = TextPainter(
          text: metaSpan,
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '...',
        )..layout(maxWidth: max(10, node.width - 50));
        metaPainter.paint(canvas, Offset(36, curY + 26));
      }

      curY += cardHeight + 6.0;
    }
  }

  static void _paintNestedBoard(Canvas canvas, CanvasNode node) {
    final payload = node.payload is NestedBoardPayload
        ? node.payload as NestedBoardPayload
        : NestedBoardPayload();
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(payload.cornerRadius),
    );

    // Drop Shadow
    if (payload.hasShadow) {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawRRect(rrect.shift(const Offset(0, 4)), shadowPaint);
    }

    // Board Card Background
    canvas.drawRRect(
      rrect,
      Paint()..color = payload.backgroundColor.withValues(alpha: 0.95),
    );

    // Outer Border
    if (payload.borderWidth > 0) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = payload.borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = payload.borderWidth,
      );
    }

    // Header Accent Bar
    final headerRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, node.width, 32),
      topLeft: Radius.circular(payload.cornerRadius),
      topRight: Radius.circular(payload.cornerRadius),
    );
    canvas.drawRRect(
      headerRect,
      Paint()..color = payload.borderColor.withValues(alpha: 0.25),
    );

    // Title Span with Emoji Badge
    final titleSpan = TextSpan(
      children: [
        TextSpan(
          text: '${payload.iconEmoji} ',
          style: const TextStyle(fontSize: 12),
        ),
        TextSpan(
          text: payload.boardName,
          style: TextStyle(
            color: payload.accentColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: max(10, node.width - 24));
    titlePainter.paint(canvas, const Offset(10, 8));

    // Sub-canvas Mini Viewport / Preview Box
    if (node.height > 80) {
      final previewRect = Rect.fromLTWH(
        10,
        38,
        node.width - 20,
        node.height - 70,
      );
      final previewRRect = RRect.fromRectAndRadius(
        previewRect,
        const Radius.circular(4),
      );

      // Dark sub-canvas container
      canvas.drawRRect(
        previewRRect,
        Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.9),
      );
      canvas.drawRRect(
        previewRRect,
        Paint()
          ..color = const Color(0xFF334155)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );

      // Grid Dots preview inside box
      if (payload.showGridPreview) {
        final dotPaint = Paint()
          ..color = const Color(0xFF475569).withValues(alpha: 0.35);
        for (
          double gx = previewRect.left + 8;
          gx < previewRect.right - 4;
          gx += 12
        ) {
          for (
            double gy = previewRect.top + 8;
            gy < previewRect.bottom - 4;
            gy += 12
          ) {
            canvas.drawCircle(Offset(gx, gy), 0.7, dotPaint);
          }
        }
      }

      // Render mini node thumbnails if subNodes present
      if (payload.subNodes.isNotEmpty) {
        for (int i = 0; i < min(payload.subNodes.length, 6); i++) {
          final subNode = payload.subNodes[i];
          final double miniX =
              previewRect.left + 8 + ((i % 3) * ((previewRect.width - 24) / 3));
          final double miniY =
              previewRect.top +
              8 +
              ((i ~/ 3) * ((previewRect.height - 20) / 2));
          final double miniW = max(10.0, (previewRect.width - 32) / 3);
          final double miniH = max(8.0, (previewRect.height - 24) / 2);

          if (miniY + miniH <= previewRect.bottom) {
            final miniCardRect = RRect.fromRectAndRadius(
              Rect.fromLTWH(miniX, miniY, miniW, miniH),
              const Radius.circular(2),
            );
            canvas.drawRRect(
              miniCardRect,
              Paint()..color = const Color(0xFF1E293B),
            );
            canvas.drawRRect(
              miniCardRect,
              Paint()
                ..color = const Color(0xFF64748B)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.5,
            );

            final miniText = TextPainter(
              text: TextSpan(
                text: subNode.name,
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 7),
              ),
              textDirection: TextDirection.ltr,
              maxLines: 1,
              ellipsis: '..',
            )..layout(maxWidth: max(4, miniW - 4));
            miniText.paint(canvas, Offset(miniX + 2, miniY + 2));
          }
        }
      } else {
        // Placeholder empty state in preview
        final emptySpan = TextSpan(
          text: 'Empty Sub-Canvas • Click to Open',
          style: TextStyle(
            color: const Color(0xFF64748B).withValues(alpha: 0.8),
            fontSize: 9,
            fontStyle: FontStyle.italic,
          ),
        );
        final emptyPainter = TextPainter(
          text: emptySpan,
          textDirection: TextDirection.ltr,
        )..layout();
        emptyPainter.paint(
          canvas,
          Offset(
            previewRect.left + (previewRect.width - emptyPainter.width) / 2,
            previewRect.top + (previewRect.height - emptyPainter.height) / 2,
          ),
        );
      }
    }

    // Bottom Status & Count Line
    final count = payload.subNodes.isNotEmpty
        ? payload.subNodes.length
        : payload.childNodeCount;
    final tagText = payload.tags.isNotEmpty ? ' • #${payload.tags.first}' : '';
    final countSpan = TextSpan(
      children: [
        TextSpan(
          text: 'Contains $count items$tagText',
          style: const TextStyle(color: Color(0xFFC7D2FE), fontSize: 9.5),
        ),
        const TextSpan(
          text: ' • Double-click to open ↗',
          style: TextStyle(
            color: Color(0xFF818CF8),
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
    final countPainter = TextPainter(
      text: countSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: max(10, node.width - 20));
    countPainter.paint(canvas, Offset(10, max(10.0, node.height - 22)));
  }

  static void _paintTableGrid(Canvas canvas, CanvasNode node) {
    final payload = node.payload as TablePayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(payload.cornerRadius),
    );

    // Drop Shadow
    if (payload.hasShadow) {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawRRect(rrect.shift(const Offset(0, 4)), shadowPaint);
    }

    // Card background
    canvas.drawRRect(rrect, Paint()..color = payload.backgroundColor);
    if (payload.borderWidth > 0) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = payload.borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = payload.borderWidth,
      );
    }

    final colCount = max(1, payload.columns.length);
    final colWidth = node.width / colCount;

    // Header background
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, node.width, 28),
        topLeft: Radius.circular(payload.cornerRadius),
        topRight: Radius.circular(payload.cornerRadius),
      ),
      Paint()..color = payload.headerBgColor,
    );

    // Header Column Labels
    for (int i = 0; i < colCount; i++) {
      final textSpan = TextSpan(
        text: payload.columns[i].toUpperCase(),
        style: TextStyle(
          color: payload.headerTextColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
        ..layout(maxWidth: colWidth - 8);
      tp.paint(canvas, Offset(i * colWidth + 8, 7));
    }

    // Data Rows
    double rowY = 28.0;
    const rowHeight = 24.0;
    final linePaint = Paint()
      ..color = payload.borderColor.withValues(alpha: 0.6)
      ..strokeWidth = 1;

    for (int r = 0; r < payload.rows.length; r++) {
      if (rowY + rowHeight > node.height - (payload.showSummaryRow ? 24 : 0)) {
        break;
      }

      final row = payload.rows[r];
      // Zebra background
      if (r % 2 == 1) {
        canvas.drawRect(
          Rect.fromLTWH(0, rowY, node.width, rowHeight),
          Paint()..color = payload.zebraColor,
        );
      }

      canvas.drawLine(Offset(0, rowY), Offset(node.width, rowY), linePaint);
      for (int c = 0; c < min(colCount, row.length); c++) {
        final cellType = payload.typeForColumn(c);
        final raw = row[c];
        final display = cellType == TableCellType.formula
            ? TableFormula.evaluate(raw, payload)
            : _formatTableCell(raw, cellType);
        final isCheckbox = cellType == TableCellType.checkbox;

        if (isCheckbox) {
          final boxRect = Rect.fromLTWH(c * colWidth + 8, rowY + 5, 14, 14);
          final checked =
              raw.toLowerCase() == 'true' ||
              raw == '1' ||
              raw.toLowerCase() == 'x';
          canvas.drawRRect(
            RRect.fromRectAndRadius(boxRect, const Radius.circular(3)),
            Paint()
              ..color = checked ? const Color(0xFF10B981) : Colors.transparent
              ..style = checked ? PaintingStyle.fill : PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
          if (checked) {
            final checkPaint = Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5;
            canvas.drawLine(
              Offset(boxRect.left + 3, boxRect.top + 7),
              Offset(boxRect.left + 6, boxRect.top + 10),
              checkPaint,
            );
            canvas.drawLine(
              Offset(boxRect.left + 6, boxRect.top + 10),
              Offset(boxRect.left + 11, boxRect.top + 4),
              checkPaint,
            );
          }
        } else {
          final isDark = payload.backgroundColor.computeLuminance() < 0.5;
          final isInvalid = !_isValidTableCell(raw, cellType);

          final valSpan = TextSpan(
            text: isInvalid ? '⚠️ $raw' : display,
            style: TextStyle(
              color: isInvalid
                  ? const Color(0xFFEF4444)
                  : (isDark
                        ? const Color(0xFFE5E7EB)
                        : const Color(0xFF1F2937)),
              fontSize: 10,
              fontFamily: cellType == TableCellType.formula
                  ? 'monospace'
                  : null,
              fontWeight: isInvalid ? FontWeight.bold : FontWeight.normal,
            ),
          );
          final valPainter = TextPainter(
            text: valSpan,
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '..',
          )..layout(maxWidth: colWidth - 8);
          valPainter.paint(canvas, Offset(c * colWidth + 8, rowY + 5));

          // Draw red underline for invalid cell
          if (isInvalid) {
            final errLinePaint = Paint()
              ..color = const Color(0xFFEF4444)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0;
            canvas.drawLine(
              Offset(c * colWidth + 8, rowY + rowHeight - 2),
              Offset(
                c * colWidth + min(colWidth - 8, valPainter.width + 8),
                rowY + rowHeight - 2,
              ),
              errLinePaint,
            );
          }
        }
      }
      rowY += rowHeight;
    }

    // Summary Row
    if (payload.showSummaryRow && rowY + 24 <= node.height + 1) {
      canvas.drawRect(
        Rect.fromLTWH(0, node.height - 24, node.width, 24),
        Paint()..color = payload.headerBgColor.withValues(alpha: 0.7),
      );
      canvas.drawLine(
        Offset(0, node.height - 24),
        Offset(node.width, node.height - 24),
        linePaint,
      );

      for (int c = 0; c < colCount; c++) {
        final cellType = payload.typeForColumn(c);
        String summaryText = '';
        if (cellType == TableCellType.number ||
            cellType == TableCellType.currency ||
            cellType == TableCellType.percentage) {
          double sum = 0;
          for (final r in payload.rows) {
            if (c < r.length) {
              final parsed = double.tryParse(
                r[c].replaceAll(RegExp(r'[^0-9.-]'), ''),
              );
              if (parsed != null) sum += parsed;
            }
          }
          summaryText =
              '∑ ${sum == sum.roundToDouble() ? sum.toInt() : sum.toStringAsFixed(2)}';
        } else if (c == 0) {
          summaryText = 'Total: ${payload.rows.length}';
        }

        if (summaryText.isNotEmpty) {
          final sumSpan = TextSpan(
            text: summaryText,
            style: TextStyle(
              color: payload.headerTextColor,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
            ),
          );
          final sumPainter = TextPainter(
            text: sumSpan,
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '..',
          )..layout(maxWidth: colWidth - 8);
          sumPainter.paint(canvas, Offset(c * colWidth + 8, node.height - 18));
        }
      }
    }
  }

  static bool _isValidTableCell(String val, TableCellType type) {
    if (val.trim().isEmpty) return true;
    switch (type) {
      case TableCellType.number:
        return double.tryParse(val.trim()) != null;
      case TableCellType.currency:
        final clean = val.replaceAll(RegExp(r'[\$,Rp\s]'), '');
        return double.tryParse(clean) != null;
      case TableCellType.percentage:
        final clean = val.replaceAll(RegExp(r'[%\s]'), '');
        return double.tryParse(clean) != null;
      case TableCellType.date:
        return DateTime.tryParse(val.trim()) != null ||
            RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(val.trim()) ||
            RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$').hasMatch(val.trim());
      case TableCellType.time:
        return RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(val.trim());
      case TableCellType.formula:
        return val.trim().startsWith('=');
      case TableCellType.checkbox:
      case TableCellType.text:
        return true;
    }
  }

  static String _formatTableCell(String raw, TableCellType type) {
    switch (type) {
      case TableCellType.currency:
        final v = double.tryParse(raw);
        return v == null ? raw : '\$${v.toStringAsFixed(2)}';
      case TableCellType.percentage:
        final v = double.tryParse(raw);
        return v == null ? raw : '${v.toStringAsFixed(1)}%';
      case TableCellType.number:
        return raw;
      case TableCellType.text:
      case TableCellType.checkbox:
      case TableCellType.date:
      case TableCellType.time:
      case TableCellType.formula:
        return raw;
    }
  }

  static void _paintTodoList(Canvas canvas, CanvasNode node) {
    final payload = node.payload as TodoListPayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(payload.cornerRadius),
    );

    // Optional Drop Shadow
    if (payload.hasShadow) {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawRRect(rrect.shift(const Offset(0, 4)), shadowPaint);
    }

    // Card background & border
    canvas.drawRRect(rrect, Paint()..color = payload.backgroundColor);
    if (payload.borderWidth > 0) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = payload.borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = payload.borderWidth,
      );
    }

    final isDarkCard = payload.backgroundColor.computeLuminance() < 0.5;
    final primaryTextColor = isDarkCard
        ? const Color(0xFFF3F4F6)
        : const Color(0xFF111827);
    final secondaryTextColor = isDarkCard
        ? const Color(0xFF9CA3AF)
        : const Color(0xFF6B7280);

    // Calculate completed statistics
    final totalItems = payload.items.length;
    final completedItems = payload.items.where((i) => i.isDone).length;
    final progress = totalItems > 0 ? (completedItems / totalItems) : 0.0;

    // Filter displayed items according to payload.filterMode
    final displayedItems = payload.items.where((item) {
      if (payload.filterMode == 'active') return !item.isDone;
      if (payload.filterMode == 'completed') return item.isDone;
      return true;
    }).toList();

    // 1. Header Title & Count Badge
    final titleSpan = TextSpan(
      children: [
        TextSpan(
          text: payload.title.isEmpty ? 'To-do List' : payload.title,
          style: TextStyle(
            color: payload.accentColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (totalItems > 0)
          TextSpan(
            text: '  ($completedItems/$totalItems)',
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 10,
              fontWeight: FontWeight.normal,
            ),
          ),
      ],
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '..',
    )..layout(maxWidth: max(10, node.width - 24));
    titlePainter.paint(canvas, const Offset(12, 10));

    double itemY = 28.0;

    // 2. Progress Bar
    if (payload.showProgressBar && totalItems > 0) {
      final barWidth = max(10.0, node.width - 24);
      final barRect = Rect.fromLTWH(12, itemY + 2, barWidth, 4);
      final barBgPaint = Paint()
        ..color = isDarkCard
            ? const Color(0xFF374151)
            : const Color(0xFFE5E7EB);
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, const Radius.circular(2)),
        barBgPaint,
      );

      if (progress > 0) {
        final fillWidth = barWidth * progress.clamp(0.0, 1.0);
        final fillRect = Rect.fromLTWH(12, itemY + 2, fillWidth, 4);
        final fillPaint = Paint()..color = payload.accentColor;
        canvas.drawRRect(
          RRect.fromRectAndRadius(fillRect, const Radius.circular(2)),
          fillPaint,
        );
      }
      itemY += 14.0;
    } else {
      itemY += 6.0;
    }

    // 3. Render items
    int visibleCount = 0;
    for (int i = 0; i < displayedItems.length; i++) {
      final item = displayedItems[i];
      final hasMeta =
          item.dueDate != null ||
          item.assignee != null ||
          item.priority != TodoPriority.none ||
          item.tags.isNotEmpty;
      final requiredHeight = hasMeta ? 36.0 : 24.0;

      if (itemY + requiredHeight > node.height - 8) {
        final remaining = displayedItems.length - visibleCount;
        if (remaining > 0) {
          final moreSpan = TextSpan(
            text: '+$remaining more tasks...',
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 9,
              fontStyle: FontStyle.italic,
            ),
          );
          final morePainter = TextPainter(
            text: moreSpan,
            textDirection: TextDirection.ltr,
          )..layout();
          morePainter.paint(canvas, Offset(12, itemY + 2));
        }
        break;
      }

      visibleCount++;

      // Checkbox Box
      final boxRect = Rect.fromLTWH(12, itemY + 3, 14, 14);
      const boxRadius = Radius.circular(3.5);
      if (item.isDone) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(boxRect, boxRadius),
          Paint()..color = payload.accentColor,
        );
        // Checkmark tick
        final checkPath = Path()
          ..moveTo(15.5, itemY + 10)
          ..lineTo(18.0, itemY + 13)
          ..lineTo(22.5, itemY + 7);
        canvas.drawPath(
          checkPath,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(boxRect, boxRadius),
          Paint()
            ..color = isDarkCard
                ? const Color(0xFF4B5563)
                : const Color(0xFFD1D5DB)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
      }

      // Main Item Text & Strikethrough
      final itemSpan = TextSpan(
        text: item.text.isEmpty ? 'Untitled task' : item.text,
        style: TextStyle(
          color: item.isDone ? secondaryTextColor : primaryTextColor,
          fontSize: 11,
          fontWeight: item.isDone ? FontWeight.normal : FontWeight.w500,
          decoration: item.isDone ? TextDecoration.lineThrough : null,
          decorationColor: secondaryTextColor,
        ),
      );
      final itemPainter = TextPainter(
        text: itemSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '..',
      )..layout(maxWidth: max(10, node.width - 40));
      itemPainter.paint(canvas, Offset(32, itemY + 3));

      // Metadata: Priority, DueDate, Assignee, Tags
      if (hasMeta) {
        double metaX = 32.0;
        final metaY = itemY + 18.0;

        // Priority Badge
        if (item.priority != TodoPriority.none) {
          Color pColor = const Color(0xFF6B7280);
          if (item.priority == TodoPriority.high) {
            pColor = const Color(0xFFEF4444);
          }
          if (item.priority == TodoPriority.medium) {
            pColor = const Color(0xFFF59E0B);
          }
          if (item.priority == TodoPriority.low) {
            pColor = const Color(0xFF3B82F6);
          }

          final pSpan = TextSpan(
            text: item.priority.label.toUpperCase(),
            style: TextStyle(
              color: pColor,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          );
          final pPainter = TextPainter(
            text: pSpan,
            textDirection: TextDirection.ltr,
          )..layout();
          final badgeRect = Rect.fromLTWH(
            metaX,
            metaY - 1,
            pPainter.width + 6,
            12,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(badgeRect, const Radius.circular(2)),
            Paint()..color = pColor.withValues(alpha: 0.15),
          );
          pPainter.paint(canvas, Offset(metaX + 3, metaY));
          metaX += pPainter.width + 10;
        }

        // Due date & Assignee & Tags text
        final metaParts = <String>[
          if (item.dueDate != null && item.dueDate!.isNotEmpty)
            '📅 ${item.dueDate}',
          if (item.assignee != null && item.assignee!.isNotEmpty)
            '👤 ${item.assignee}',
          if (item.tags.isNotEmpty) '#${item.tags.join(" #")}',
        ];

        if (metaParts.isNotEmpty && metaX < node.width - 20) {
          final metaSpan = TextSpan(
            text: metaParts.join('  '),
            style: TextStyle(color: secondaryTextColor, fontSize: 8.5),
          );
          final metaPainter = TextPainter(
            text: metaSpan,
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '..',
          )..layout(maxWidth: max(10, node.width - metaX - 8));
          metaPainter.paint(canvas, Offset(metaX, metaY));
        }

        itemY += 36.0;
      } else {
        itemY += 24.0;
      }
    }
  }

  static void _paintDocument(Canvas canvas, CanvasNode node) {
    final payload = node.payload as DocumentPayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(payload.cornerRadius),
    );

    // Optional Drop Shadow
    if (payload.hasShadow) {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawRRect(rrect.shift(const Offset(0, 4)), shadowPaint);
    }

    // Card background & border
    canvas.drawRRect(rrect, Paint()..color = payload.backgroundColor);
    if (payload.borderWidth > 0) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = payload.borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = payload.borderWidth,
      );
    }

    // Determine text colors based on card background brightness
    final isDarkCard = payload.backgroundColor.computeLuminance() < 0.5;
    final defaultTitleColor = isDarkCard
        ? const Color(0xFFF3F4F6)
        : const Color(0xFF111827);
    final defaultTextColor = isDarkCard
        ? const Color(0xFFD1D5DB)
        : const Color(0xFF374151);
    final defaultSubColor = isDarkCard
        ? const Color(0xFF9CA3AF)
        : const Color(0xFF6B7280);

    // Render document content directly matching editor page
    double y = 14.0;
    for (final block in payload.blocks) {
      if (y + 14 > node.height - 22) break;

      final text = block.plainText;
      if (text.isEmpty || text.trim().isEmpty) {
        y += 18.0; // Preserve blank lines
        continue;
      }

      final inlineSpans = <InlineSpan>[];
      for (final span in block.spans) {
        if (span.text.isEmpty) continue;
        inlineSpans.add(
          TextSpan(
            text: span.text,
            style: TextStyle(
              color:
                  span.color ??
                  (block.type == RichTextBlockType.heading
                      ? defaultTitleColor
                      : block.type == RichTextBlockType.quote
                      ? defaultSubColor
                      : defaultTextColor),
              fontSize: block.type == RichTextBlockType.heading ? 13 : 11,
              fontWeight: (block.type == RichTextBlockType.heading || span.bold)
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontStyle: (span.italic || block.type == RichTextBlockType.quote)
                  ? FontStyle.italic
                  : FontStyle.normal,
              decoration: TextDecoration.combine([
                if (span.underline || span.linkUrl != null)
                  TextDecoration.underline,
                if (span.strikethrough) TextDecoration.lineThrough,
              ]),
              backgroundColor: span.highlight,
              fontFamily: block.type == RichTextBlockType.code
                  ? 'monospace'
                  : null,
            ),
          ),
        );
      }

      final prefix = switch (block.type) {
        RichTextBlockType.bullet => '• ',
        RichTextBlockType.numbered => '1. ',
        RichTextBlockType.quote => '│ ',
        _ => '',
      };

      final blockSpan = TextSpan(
        text: prefix,
        style: TextStyle(
          color: defaultSubColor,
          fontSize: block.type == RichTextBlockType.heading ? 13 : 11,
          fontWeight: block.type == RichTextBlockType.heading
              ? FontWeight.bold
              : FontWeight.normal,
        ),
        children: inlineSpans,
      );

      final tp = TextPainter(
        text: blockSpan,
        textDirection: TextDirection.ltr,
        maxLines: 4,
        ellipsis: '…',
      )..layout(maxWidth: max(10.0, node.width - 24));

      if (block.type == RichTextBlockType.code) {
        final bgPaint = Paint()
          ..color = isDarkCard
              ? const Color(0xFF282B36)
              : const Color(0xFFF3F4F6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(10, y - 2, node.width - 20, tp.height + 4),
            const Radius.circular(3),
          ),
          bgPaint,
        );
        tp.paint(canvas, Offset(14, y));
        y += tp.height + 8;
      } else {
        tp.paint(canvas, Offset(12, y));
        y += tp.height + (block.type == RichTextBlockType.heading ? 6 : 4);
      }
    }

    // Footer hint
    final hintSpan = TextSpan(
      text: 'Double-click to open document',
      style: TextStyle(
        color: defaultSubColor.withValues(alpha: 0.6),
        fontSize: 9,
        fontStyle: FontStyle.italic,
      ),
    );
    final hintPainter = TextPainter(
      text: hintSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    hintPainter.paint(canvas, Offset(12, max(12.0, node.height - 18)));
  }

  static void _paintMermaid(Canvas canvas, CanvasNode node) {
    final payload = node.payload as MermaidPayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final border = Paint()
      ..color = const Color(0xFF7C3AED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF17121F));
    canvas.drawRect(rect, border);

    final title = payload.diagramType == 'unknown'
        ? 'Mermaid diagram'
        : payload.diagramType;
    final painter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          color: Color(0xFFE9D5FF),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: max(0.0, node.width - 24.0));
    painter.paint(canvas, const Offset(12, 10));

    final status = payload.lastError == null
        ? 'Preview unavailable'
        : 'Mermaid error';
    final statusPainter = TextPainter(
      text: TextSpan(
        text: status,
        style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: max(0.0, node.width - 24.0));
    statusPainter.paint(canvas, Offset(12, max(32, node.height / 2 - 8)));
  }

  static void _paintEmbed(Canvas canvas, CanvasNode node) {
    final payload = node.payload as EmbedPayload;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF111827));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFFF59E0B).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final center = Offset(node.width / 2, node.height / 2 - 10);
    canvas.drawCircle(center, 18, Paint()..color = const Color(0xFFF59E0B));
    final playPath = Path()
      ..moveTo(center.dx - 5, center.dy - 8)
      ..lineTo(center.dx + 8, center.dy)
      ..lineTo(center.dx - 5, center.dy + 8)
      ..close();
    canvas.drawPath(playPath, Paint()..color = Colors.black87);

    final titleSpan = TextSpan(
      text: '▶ ${payload.provider} Embed',
      style: const TextStyle(
        color: Color(0xFFFBBF24),
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '..',
    )..layout(maxWidth: max(10, node.width - 24));
    titlePainter.paint(canvas, const Offset(12, 12));

    final urlSpan = TextSpan(
      text: payload.title ?? payload.url,
      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10),
    );
    final urlPainter = TextPainter(
      text: urlSpan,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '..',
    )..layout(maxWidth: max(10, node.width - 24));
    urlPainter.paint(canvas, Offset(12, node.height - 34));
  }

  static bool _drawingLayerVisible(
    DrawingPaperPayload payload,
    DrawingLayer layer,
  ) {
    if (!layer.visible) return false;
    final visited = <String>{};
    var parentId = layer.parentFolderId;
    while (parentId != null && visited.add(parentId)) {
      final parent = payload.layers.firstWhere(
        (candidate) => candidate.id == parentId,
        orElse: () => const DrawingLayer(id: '', name: '', visible: false),
      );
      if (!parent.visible) return false;
      parentId = parent.parentFolderId;
    }
    return true;
  }

  static void _paintDrawingPaperOverlays(
    Canvas canvas,
    DrawingPaperPayload payload,
  ) => DrawingPaperRenderer.paintOverlays(canvas, payload);

  static void _paintDrawingPaperWorkspace(
    Canvas canvas,
    CanvasNode node,
    DrawingPaperPayload payload, {
    required CanvasImageCache imageCache,
  }) {
    final workspaceBounds = DrawingPaperRenderer.workspaceBounds(payload);
    if (workspaceBounds.isEmpty) return;
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);

    final shadowPath = Path()..addRect(rect);
    canvas.drawShadow(shadowPath, Colors.black, 8.0, true);
    canvas.drawRect(rect, Paint()..color = payload.paperColor);

    if (payload.showMangaBleed ||
        payload.presetName.toLowerCase().contains('manga')) {
      final bleedMargin = node.width * 0.05;
      final safeRect = Rect.fromLTWH(
        bleedMargin,
        bleedMargin,
        node.width - bleedMargin * 2,
        node.height - bleedMargin * 2,
      );
      canvas.drawRect(
        safeRect,
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    final scaleX = node.width / max(1.0, workspaceBounds.width);
    final scaleY = node.height / max(1.0, workspaceBounds.height);
    final previewReference = _workspacePreviewReference(payload, node.id);
    final cachedPreview = imageCache.getImage(previewReference);
    canvas.save();
    canvas.clipRect(rect);
    if (cachedPreview != null) {
      canvas.drawImageRect(
        cachedPreview,
        Rect.fromLTWH(
          0,
          0,
          cachedPreview.width.toDouble(),
          cachedPreview.height.toDouble(),
        ),
        rect,
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      DrawingPaperRenderer.paintWorkspaceVectorContent(
        canvas,
        payload,
        bounds: workspaceBounds,
        scaleX: scaleX,
        scaleY: scaleY,
      );
    }
    canvas.restore();

    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF94A3B8).withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final tagRect = Rect.fromLTWH(0, -22, min(node.width, 180.0), 20);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        tagRect,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF1E293B),
    );
    final infoSpan = TextSpan(
      text: '📄 ${payload.presetName} (${payload.dpi.toInt()} DPI)',
      style: const TextStyle(
        color: Color(0xFFF97316),
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: infoSpan,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 170);
    textPainter.paint(canvas, const Offset(6, -18));
  }

  static void _paintDrawingPaper(
    Canvas canvas,
    CanvasNode node, {
    required CanvasImageCache imageCache,
  }) {
    final payload = node.payload as DrawingPaperPayload;
    if (payload.studioPages.isNotEmpty) {
      _paintDrawingPaperWorkspace(
        canvas,
        node,
        payload,
        imageCache: imageCache,
      );
      return;
    }
    final rect = Rect.fromLTWH(0, 0, node.width, node.height);

    // 1. Drop shadow fisik kertas
    final shadowPath = Path()..addRect(rect);
    canvas.drawShadow(shadowPath, Colors.black, 8.0, true);

    // 2. Background Kertas
    canvas.drawRect(rect, Paint()..color = payload.paperColor);

    // 3. Border presisi kertas
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF94A3B8).withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // 4. Safe Bleed line guide jika manga page
    if (payload.showMangaBleed ||
        payload.presetName.toLowerCase().contains('manga')) {
      final bleedMargin = node.width * 0.05;
      final safeRect = Rect.fromLTWH(
        bleedMargin,
        bleedMargin,
        node.width - bleedMargin * 2,
        node.height - bleedMargin * 2,
      );
      canvas.drawRect(
        safeRect,
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // 5. Render Layers preview (strokes scaling)
    final scaleX = node.width / max(1.0, payload.pixelWidth);
    final scaleY = node.height / max(1.0, payload.pixelHeight);
    final previewReference = _workspacePreviewReference(payload, node.id);
    final cachedPreview = imageCache.getImage(previewReference);

    canvas.save();
    canvas.clipRect(rect);
    if (cachedPreview != null) {
      canvas.drawImageRect(
        cachedPreview,
        Rect.fromLTWH(
          0,
          0,
          cachedPreview.width.toDouble(),
          cachedPreview.height.toDouble(),
        ),
        rect,
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      canvas.scale(scaleX, scaleY);

      for (final layer in payload.layers) {
        if (!_drawingLayerVisible(payload, layer)) continue;
        final layerOpacity = layer.opacity.clamp(0.0, 1.0);
        if (layerOpacity <= 0.0) continue;

        for (final stroke in layer.strokes) {
          if (stroke.points.length < 2) continue;

          final paint = Paint()
            ..color = stroke.isEraser
                ? payload.paperColor
                : stroke.color.withValues(alpha: stroke.opacity * layerOpacity)
            ..strokeWidth = max(1.0, stroke.size)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke
            ..blendMode = stroke.blendMode;

          if (stroke.brush == StudioBrushCategory.bucketFill ||
              stroke.brush == StudioBrushCategory.lassoFill) {
            final fillPath = Path();
            fillPath.moveTo(stroke.points.first.x, stroke.points.first.y);
            for (int i = 1; i < stroke.points.length; i++) {
              fillPath.lineTo(stroke.points[i].x, stroke.points[i].y);
            }
            fillPath.close();
            final fPaint = Paint()
              ..color = stroke.color.withValues(
                alpha: stroke.opacity * layerOpacity,
              )
              ..style = PaintingStyle.fill;
            canvas.drawPath(fillPath, fPaint);
          } else {
            final path = Path();
            path.moveTo(stroke.points.first.x, stroke.points.first.y);
            for (int i = 1; i < stroke.points.length; i++) {
              path.lineTo(stroke.points[i].x, stroke.points[i].y);
            }
            canvas.drawPath(path, paint);
          }
        }
      }
      _paintDrawingPaperOverlays(canvas, payload);
    }
    canvas.restore();

    // 6. Header Tag Preset Kertas di atas sudut kiri
    final tagRect = Rect.fromLTWH(0, -22, min(node.width, 180.0), 20);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        tagRect,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF1E293B),
    );

    final infoSpan = TextSpan(
      text: '📄 ${payload.presetName} (${payload.dpi.toInt()} DPI)',
      style: const TextStyle(
        color: Color(0xFFF97316),
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
    final tp = TextPainter(text: infoSpan, textDirection: TextDirection.ltr)
      ..layout(maxWidth: 170);
    tp.paint(canvas, const Offset(6, -18));
  }
}
