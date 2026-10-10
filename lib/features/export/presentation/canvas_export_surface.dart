import 'package:flutter/material.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/viewport.dart' as canvas_model;
import 'package:varian/features/canvas/presentation/painters/canvas_painter.dart';
import 'package:varian/features/canvas/presentation/painters/grid_painter.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';

/// A clean, editor-free canvas surface used for PNG export captures.
class CanvasExportSurface extends StatelessWidget {
  final GlobalKey boundaryKey;
  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;
  final canvas_model.Viewport viewport;
  final Size size;
  final CanvasRenderTokens renderTokens;
  final CanvasImageCache? imageCache;

  const CanvasExportSurface({
    required this.boundaryKey,
    required this.nodes,
    required this.edges,
    required this.viewport,
    required this.size,
    required this.renderTokens,
    this.imageCache,
    super.key,
  });

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: boundaryKey,
    child: SizedBox(
      width: size.width,
      height: size.height,
      child: ColoredBox(
        color: renderTokens.canvas,
        child: CustomPaint(
          painter: CanvasPainter(
            nodes: nodes,
            edges: edges,
            viewport: viewport,
            selectedNodeIds: const {},
            renderTokens: renderTokens,
            imageCache: imageCache,
          ),
        ),
      ),
    ),
  );
}
