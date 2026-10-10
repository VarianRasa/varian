import 'dart:math' as math;

import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter/services.dart';
import '../../../../app/theme.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../../../domain/models/connector_edge.dart';
import '../../../../domain/models/node.dart';
import '../../../../domain/models/node_payload.dart';
import '../../../../domain/models/viewport.dart';
import '../../utils/connector_router.dart';
import '../../utils/minimap_geometry.dart';

class CanvasMinimap extends StatefulWidget {
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final Viewport viewport;
  final Set<String> selectedNodeIds;
  final Size canvasSize;
  final ValueChanged<Offset> onViewportCenterChanged;
  final VoidCallback onFit;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final bool showEdges;
  final bool initiallyCollapsed;

  const CanvasMinimap({
    super.key,
    required this.nodes,
    this.edges = const [],
    required this.viewport,
    this.selectedNodeIds = const {},
    required this.canvasSize,
    required this.onViewportCenterChanged,
    required this.onFit,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    this.showEdges = true,
    this.initiallyCollapsed = false,
  });

  @override
  State<CanvasMinimap> createState() => _CanvasMinimapState();
}

class _CanvasMinimapState extends State<CanvasMinimap> {
  late bool _collapsed = widget.initiallyCollapsed;
  Offset? _dragStart;
  Offset? _dragGrabOffset;
  MinimapTransform? _gestureTransform;
  bool _draggingViewport = false;
  bool _didDrag = false;

  @override
  void didUpdateWidget(covariant CanvasMinimap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyCollapsed != widget.initiallyCollapsed) {
      _collapsed = widget.initiallyCollapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(230.0, constraints.maxWidth);
        final height = math.min(170.0, constraints.maxHeight);
        if (width < 96 || height < AppControlSize.minimumHitTarget) {
          return const SizedBox.shrink();
        }

        if (_collapsed) {
          return Align(
            alignment: Alignment.bottomRight,
            child: _CollapsedMinimapButton(
              onPressed: () => setState(() => _collapsed = false),
            ),
          );
        }

        final size = Size(width, height);
        final transform = _buildTransform(size);
        final viewportWorld = _viewportWorldRect();
        final viewportMini = transform.worldRectToMinimap(viewportWorld);

        return Semantics(
          container: true,
          explicitChildNodes: true,
          label:
              'Canvas minimap. Tap or drag to navigate. When focused, use arrow keys to pan.',
          hint: 'Tab through the zoom, fit, reset, and collapse controls.',
          child: Focus(
            canRequestFocus: true,
            skipTraversal: false,
            onKeyEvent: _handleKeyboardNavigation,
            child: Listener(
              child: DecoratedBox(
                key: const ValueKey('canvas-minimap-frame'),
                decoration: BoxDecoration(
                  color: tokens.panelElevated.withValues(alpha: 0.97),
                  borderRadius: BorderRadius.circular(tokens.controlRadius),
                  border: Border.all(
                    color: tokens.panelBorder,
                    width: AppBorder.thin,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.raisedShadow.withValues(alpha: 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(tokens.controlRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          if (_didDrag) return;
                          widget.onViewportCenterChanged(
                            transform.minimapToWorld(details.localPosition),
                          );
                        },
                        onPanStart: (details) {
                          _didDrag = false;
                          _gestureTransform = transform;
                          _dragStart = details.localPosition;
                          _draggingViewport = viewportMini.contains(
                            details.localPosition,
                          );
                          final pointerWorld = transform.minimapToWorld(
                            details.localPosition,
                          );
                          _dragGrabOffset = _draggingViewport
                              ? viewportWorld.center - pointerWorld
                              : Offset.zero;
                          if (!_draggingViewport) {
                            widget.onViewportCenterChanged(pointerWorld);
                          }
                        },
                        onPanUpdate: (details) {
                          final start = _dragStart;
                          final gestureTransform = _gestureTransform;
                          if (start == null || gestureTransform == null) return;
                          if ((details.localPosition - start).distance > 2) {
                            _didDrag = true;
                          }

                          final pointerWorld = gestureTransform.minimapToWorld(
                            details.localPosition,
                          );
                          widget.onViewportCenterChanged(
                            pointerWorld + (_dragGrabOffset ?? Offset.zero),
                          );
                        },
                        onPanEnd: (_) {
                          _dragStart = null;
                          _dragGrabOffset = null;
                          _gestureTransform = null;
                          _draggingViewport = false;
                          _didDrag = false;
                        },
                        onPanCancel: () {
                          _dragStart = null;
                          _dragGrabOffset = null;
                          _gestureTransform = null;
                          _draggingViewport = false;
                          _didDrag = false;
                        },
                        child: CustomPaint(
                          painter: _CanvasMinimapPainter(
                            nodes: widget.nodes,
                            edges: widget.edges,
                            selectedNodeIds: widget.selectedNodeIds,
                            transform: transform,
                            viewportRect: viewportMini,
                            tokens: tokens,
                            showEdges: widget.showEdges,
                            emptyStateStyle: Theme.of(context)
                                .textTheme
                                .labelSmall!
                                .copyWith(
                                  color: tokens.textMuted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      if (height >= 52)
                        Positioned(
                          left: AppSpacing.sm,
                          bottom: AppSpacing.xs + AppSpacing.xxs,
                          child: IgnorePointer(
                            child: Text(
                              'MINIMAP',
                              style: Theme.of(context).textTheme.labelSmall!
                                  .copyWith(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                  ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: AppSpacing.xs,
                        top: 0,
                        width: math.max(0.0, width - AppSpacing.sm),
                        height: AppControlSize.minimumHitTarget,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MiniMapIconButton(
                                icon: Icons.remove,
                                tooltip: 'Zoom out canvas',
                                onPressed: widget.onZoomOut,
                              ),
                              _MiniMapIconButton(
                                icon: Icons.add,
                                tooltip: 'Zoom in canvas',
                                onPressed: widget.onZoomIn,
                              ),
                              _MiniMapIconButton(
                                icon: Icons.fit_screen_outlined,
                                tooltip: 'Fit canvas content',
                                onPressed: widget.onFit,
                              ),
                              _MiniMapIconButton(
                                icon: Icons.refresh,
                                tooltip: 'Reset canvas view',
                                onPressed: widget.onReset,
                              ),
                              _MiniMapIconButton(
                                icon: Icons.close_fullscreen,
                                tooltip: 'Collapse minimap',
                                onPressed: () =>
                                    setState(() => _collapsed = true),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  KeyEventResult _handleKeyboardNavigation(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final viewport = _viewportWorldRect();
    final step = Offset(viewport.width * 0.1, viewport.height * 0.1);
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => Offset(-step.dx, 0),
      LogicalKeyboardKey.arrowRight => Offset(step.dx, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step.dy),
      LogicalKeyboardKey.arrowDown => Offset(0, step.dy),
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;
    widget.onViewportCenterChanged(viewport.center + delta);
    return KeyEventResult.handled;
  }

  Rect _viewportWorldRect() {
    final zoom = widget.viewport.zoom.isFinite && widget.viewport.zoom > 0
        ? widget.viewport.zoom
        : 1.0;
    final width =
        widget.canvasSize.width.isFinite && widget.canvasSize.width > 0
        ? widget.canvasSize.width / zoom
        : 1.0;
    final height =
        widget.canvasSize.height.isFinite && widget.canvasSize.height > 0
        ? widget.canvasSize.height / zoom
        : 1.0;
    final x = widget.viewport.x.isFinite ? -widget.viewport.x / zoom : 0.0;
    final y = widget.viewport.y.isFinite ? -widget.viewport.y / zoom : 0.0;
    return Rect.fromLTWH(x, y, width, height);
  }

  MinimapTransform _buildTransform(Size mapSize) {
    return MinimapTransform.fromWorldBounds(
      MinimapTransform.worldBoundsFor(
        nodeBounds: widget.nodes
            .where((node) => node.visible)
            .map((node) => node.bounds),
        viewportBounds: _viewportWorldRect(),
      ),
      mapSize,
    );
  }
}

class _CollapsedMinimapButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _CollapsedMinimapButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Semantics(
      button: true,
      label: 'Expand minimap',
      child: DecoratedBox(
        key: const ValueKey('canvas-minimap-collapsed-frame'),
        decoration: BoxDecoration(
          color: tokens.panelElevated.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          border: Border.all(color: tokens.panelBorder, width: AppBorder.thin),
        ),
        child: UiIconButton(
          icon: Icons.map_outlined,
          tooltip: 'Expand minimap',
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _MiniMapIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _MiniMapIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return UiIconButton(
      icon: icon,
      tooltip: tooltip,
      size: UiButtonSize.lg,
      onPressed: onPressed,
    );
  }
}

class _CanvasMinimapPainter extends CustomPainter {
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final Set<String> selectedNodeIds;
  final MinimapTransform transform;
  final Rect viewportRect;
  final AppTokens tokens;
  final bool showEdges;
  final TextStyle emptyStateStyle;
  const _CanvasMinimapPainter({
    required this.nodes,
    required this.edges,
    required this.selectedNodeIds,
    required this.transform,
    required this.viewportRect,
    required this.tokens,
    required this.showEdges,
    required this.emptyStateStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = tokens.canvas.withValues(alpha: 0.58);
    canvas.drawRect(Offset.zero & size, background);

    final mapRect = transform.mapRect;
    canvas.save();
    canvas.clipRect(mapRect);
    _paintGrid(canvas, mapRect);

    final visibleNodes = nodes.where((node) => node.visible).toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    final nodeMap = {for (final node in visibleNodes) node.id: node};

    if (showEdges) {
      _paintEdges(canvas, nodeMap);
    }
    for (final node in visibleNodes) {
      _paintNode(canvas, node);
    }

    final viewportPaint = Paint()
      ..color = tokens.accent.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final viewportStroke = Paint()
      ..color = tokens.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final visibleViewport = viewportRect.intersect(mapRect);
    if (!visibleViewport.isEmpty) {
      canvas.drawRect(visibleViewport, viewportPaint);
      canvas.drawRect(visibleViewport, viewportStroke);
    }
    canvas.restore();

    if (visibleNodes.isEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(text: 'NO NODES', style: emptyStateStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
    }
  }

  void _paintGrid(Canvas canvas, Rect mapRect) {
    final paint = Paint()
      ..color = tokens.canvasGrid.withValues(alpha: 0.16)
      ..strokeWidth = 0.5;
    const step = 16.0;
    for (double x = mapRect.left; x <= mapRect.right; x += step) {
      canvas.drawLine(Offset(x, mapRect.top), Offset(x, mapRect.bottom), paint);
    }
    for (double y = mapRect.top; y <= mapRect.bottom; y += step) {
      canvas.drawLine(Offset(mapRect.left, y), Offset(mapRect.right, y), paint);
    }
  }

  void _paintEdges(Canvas canvas, Map<String, CanvasNode> nodeMap) {
    for (final edge in edges) {
      final points = ConnectorRouter.routePointsForEdge(edge, nodeMap);
      if (points.length < 2) continue;
      final path = ConnectorRouter.routeEdge(
        points.first,
        edge.sourceAnchor,
        points.last,
        edge.targetAnchor,
        edge.routing,
        waypoints: edge.waypoints,
      );
      final mapped = _mapPath(path);
      final paint = Paint()
        ..color = edge.strokeColor.withValues(alpha: 0.52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selectedNodeIds.contains(edge.id) ? 1.5 : 0.8;
      canvas.drawPath(mapped, paint);
    }
  }

  Path _mapPath(Path path) {
    final result = Path();
    for (final metric in path.computeMetrics()) {
      final length = metric.length;
      final steps = math.max(2, (length / 24).ceil());
      for (int i = 0; i <= steps; i++) {
        final tangent = metric.getTangentForOffset(length * i / steps);
        if (tangent == null) continue;
        final point = transform.worldToMinimap(tangent.position);
        if (i == 0) {
          result.moveTo(point.dx, point.dy);
        } else {
          result.lineTo(point.dx, point.dy);
        }
      }
    }
    return result;
  }

  void _paintNode(Canvas canvas, CanvasNode node) {
    final rect = transform.worldRectToMinimap(node.bounds);
    if (rect.isEmpty) return;
    final color = _nodeColor(node.type);
    final isSelected = selectedNodeIds.contains(node.id);
    final fill = Paint()
      ..color = color.withValues(
        alpha: node.type == NodeType.frame ? 0.16 : 0.78,
      )
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = isSelected ? tokens.selection : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 1.8 : 0.7;

    if (node.type == NodeType.ellipse) {
      canvas.drawOval(rect, fill);
      canvas.drawOval(rect, stroke);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        stroke,
      );
    }
  }

  Color _nodeColor(NodeType type) {
    switch (type) {
      case NodeType.frame:
      case NodeType.group:
      case NodeType.nestedBoard:
        return tokens.info;
      case NodeType.stickyNote:
      case NodeType.todoList:
        return tokens.warning;
      case NodeType.image:
      case NodeType.annotatedImage:
      case NodeType.model3d:
      case NodeType.videoCard:
      case NodeType.audioCard:
        return tokens.success;
      case NodeType.line:
      case NodeType.arrow:
        return tokens.textMuted;
      default:
        return tokens.accent;
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasMinimapPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges ||
        oldDelegate.selectedNodeIds != selectedNodeIds ||
        oldDelegate.transform != transform ||
        oldDelegate.viewportRect != viewportRect ||
        oldDelegate.tokens != tokens ||
        oldDelegate.showEdges != showEdges ||
        oldDelegate.emptyStateStyle != emptyStateStyle;
  }
}
