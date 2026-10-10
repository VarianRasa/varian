import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/viewport.dart' as canvas_model;
import 'package:varian/features/ai/data/image_artifact_store.dart';
import 'package:varian/features/canvas/presentation/painters/grid_painter.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';
import 'package:varian/features/export/presentation/canvas_export_surface.dart';

void main() {
  testWidgets('renders the configured local capture boundary', (tester) async {
    const captureSize = Size(64, 48);
    final boundaryKey = GlobalKey();
    final imageCache = CanvasImageCache.scoped(
      imageArtifactStore: MemoryImageArtifactStore(),
    );
    addTearDown(imageCache.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: CanvasExportSurface(
            boundaryKey: boundaryKey,
            nodes: [
              CanvasNode(
                id: 'local-shape',
                type: NodeType.rectangle,
                x: 8,
                y: 8,
                width: 24,
                height: 16,
                payload: ShapePayload(
                  fill: const Color(0xFF2563EB),
                  stroke: const Color(0xFF60A5FA),
                  label: 'Local fixture',
                ),
              ),
            ],
            edges: const <CanvasEdge>[],
            viewport: const canvas_model.Viewport(),
            size: captureSize,
            renderTokens: CanvasRenderTokens.light,
            imageCache: imageCache,
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    expect(boundary.size, captureSize);
    expect(find.byType(CustomPaint), findsNWidgets(2));
    final background = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(CanvasExportSurface),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(background.color, CanvasRenderTokens.light.canvas);
  });
}
