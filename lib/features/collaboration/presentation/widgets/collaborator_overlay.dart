import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/collaboration.dart';
import '../../../../domain/models/node.dart';
import '../../../../domain/models/viewport.dart' as canvas_model;
import '../painters/cursor_painter.dart';
import '../../state/collaboration_provider.dart';

class CollaboratorOverlay extends ConsumerStatefulWidget {
  final List<CanvasNode> nodes;
  final canvas_model.Viewport viewport;
  final CollaborationProjectionScope projectionScope;

  const CollaboratorOverlay({
    super.key,
    required this.nodes,
    required this.viewport,
    required this.projectionScope,
  });

  @override
  ConsumerState<CollaboratorOverlay> createState() =>
      _CollaboratorOverlayState();
}

class _CollaboratorOverlayState extends ConsumerState<CollaboratorOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  bool _reduceMotion = false;
  List<RemoteCursor> _previous = const [];
  List<RemoteCursor> _current = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _current = ref.read(
      collaborationRemoteCursorsProvider(widget.projectionScope),
    );
  }

  @override
  void didUpdateWidget(covariant CollaboratorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewport != widget.viewport) {
      _animationController.stop();
    }
  }

  void _updateCursors(List<RemoteCursor> cursors) {
    if (_samePositions(_current, cursors)) {
      _current = cursors;
      return;
    }
    final progress = Curves.easeOut.transform(_animationController.value);
    _previous = _current
        .map((cursor) => _interpolate(cursor, progress, _previous))
        .toList(growable: false);
    _current = cursors;
    if (_reduceMotion) {
      _previous = const [];
      _animationController.stop();
      return;
    }
    _animationController.forward(from: 0);
  }

  bool _samePositions(List<RemoteCursor> a, List<RemoteCursor> b) {
    if (a.length != b.length) return false;
    for (final cursor in a) {
      final next = b
          .where((value) => value.userId == cursor.userId)
          .firstOrNull;
      if (next == null ||
          next.x != cursor.x ||
          next.y != cursor.y ||
          next.selectedNodeIds.length != cursor.selectedNodeIds.length) {
        return false;
      }
    }
    return true;
  }

  RemoteCursor _interpolate(
    RemoteCursor current,
    double progress,
    List<RemoteCursor> previousCursors,
  ) {
    final previous = previousCursors
        .where((value) => value.userId == current.userId)
        .firstOrNull;
    if (previous == null) return current;
    return current.copyWith(
      x: previous.x + (current.x - previous.x) * progress,
      y: previous.y + (current.y - previous.y) * progress,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion != _reduceMotion) {
      _reduceMotion = reduceMotion;
      if (reduceMotion) {
        _previous = const [];
        _animationController.stop();
      }
    }
    final cursors = ref.watch(
      collaborationRemoteCursorsProvider(widget.projectionScope),
    );
    _updateCursors(cursors);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, _) {
          final progress = Curves.easeOut.transform(_animationController.value);
          final visible = _current
              .map((cursor) => _interpolate(cursor, progress, _previous))
              .toList(growable: false);
          return CustomPaint(
            painter: _CollaboratorOverlayPainter(
              nodes: widget.nodes,
              cursors: visible,
              viewport: widget.viewport,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}

class _CollaboratorOverlayPainter extends CustomPainter {
  final List<CanvasNode> nodes;
  final List<RemoteCursor> cursors;
  final canvas_model.Viewport viewport;

  const _CollaboratorOverlayPainter({
    required this.nodes,
    required this.cursors,
    required this.viewport,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(viewport.x, viewport.y);
    canvas.scale(viewport.zoom, viewport.zoom);
    final nodesById = {for (final node in nodes) node.id: node};
    for (final cursor in cursors) {
      final selectedIds = <String>{
        ...cursor.selectedNodeIds,
        if (cursor.selectedNodeId != null) cursor.selectedNodeId!,
      };
      if (selectedIds.isNotEmpty) {
        final selectionPaint = Paint()
          ..color = cursor.userColor.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 / viewport.zoom;
        for (final nodeId in selectedIds) {
          final node = nodesById[nodeId];
          if (node == null) continue;
          canvas.drawRRect(
            RRect.fromRectAndRadius(node.bounds, const Radius.circular(4)),
            selectionPaint,
          );
        }
      }
      CursorPainter.paint(canvas, cursor, viewport.zoom);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CollaboratorOverlayPainter oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.cursors != cursors ||
      oldDelegate.viewport != viewport;
}
