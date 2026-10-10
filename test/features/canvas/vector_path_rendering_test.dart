import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/vector_path_payload.dart';
import 'package:varian/domain/models/viewport.dart' as model;
import 'package:varian/features/canvas/presentation/painters/canvas_painter.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';

CanvasNode _rectangleNode(
  String id, {
  Color fill = Colors.white,
  double x = 0,
  double y = 0,
  double width = 100,
  double height = 100,
  double rotation = 0,
  String? maskNodeId,
  VectorMaskMode maskMode = VectorMaskMode.alpha,
  List<VectorEffect> effects = const [],
  bool visible = true,
  int zIndex = 0,
}) {
  return CanvasNode(
    id: id,
    type: NodeType.vectorPath,
    x: x,
    y: y,
    width: width,
    height: height,
    rotation: rotation,
    visible: visible,
    zIndex: zIndex,
    payload: VectorPathPayload(
      points: [
        const BezierPoint(point: Offset.zero, type: PointType.corner),
        BezierPoint(point: Offset(width, 0), type: PointType.corner),
        BezierPoint(point: Offset(width, height), type: PointType.corner),
        BezierPoint(point: Offset(0, height), type: PointType.corner),
      ],
      fill: fill,
      strokeWidth: 0,
      maskNodeId: maskNodeId,
      maskMode: maskMode,
      effects: effects,
    ),
  );
}

Future<ui.Image> _renderNode(
  CanvasNode node, {
  Size size = const Size(100, 100),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  NodePainter.paint(canvas, node);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  picture.dispose();
  return image;
}

Future<ui.Image> _renderCanvas(List<CanvasNode> nodes) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  CanvasPainter(
    nodes: nodes,
    viewport: const model.Viewport(),
    selectedNodeIds: const {},
    renderEdges: false,
    renderForeground: false,
  ).paint(canvas, const Size(100, 100));
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  picture.dispose();
  return image;
}

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('Unable to read rendered pixel.');
  final offset = (y * image.width + x) * 4;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

void main() {
  test('inner shadow is confined to the path edge', () async {
    final image = await _renderNode(
      _rectangleNode(
        'shadow',
        effects: const [
          VectorEffect(
            type: VectorEffectType.innerShadow,
            color: Colors.black,
            offset: Offset(10, 0),
          ),
        ],
      ),
    );

    final edge = await _pixel(image, 4, 50);
    final center = await _pixel(image, 50, 50);
    expect(center.r, greaterThan(edge.r));
    image.dispose();
  });

  test('rotated frame clipping follows the frame transform', () async {
    final frame = CanvasNode(
      id: 'rotated-frame',
      type: NodeType.frame,
      x: 10,
      y: 30,
      width: 80,
      height: 40,
      rotation: 0.7853981633974483,
      zIndex: 0,
      payload: FramePayload(
        background: const Color(0xFF111827),
        borderColor: const Color(0xFF111827),
        clipContent: true,
      ),
    );
    final child = CanvasNode(
      id: 'rotated-frame-child',
      type: NodeType.rectangle,
      x: 65,
      y: 65,
      width: 20,
      height: 15,
      zIndex: 1,
      parentId: frame.id,
      payload: ShapePayload(
        fill: Colors.red,
        stroke: Colors.red,
        strokeWidth: 0,
        cornerRadius: 0,
      ),
    );

    final image = await _renderCanvas([frame, child]);
    final insideRotatedFrame = await _pixel(image, 72, 72);
    expect(insideRotatedFrame.r, closeTo(Colors.red.r, 0.05));
    image.dispose();
  });

  test('vector luminance and inverted luminance masks resolve alpha', () async {
    final source = _rectangleNode('source', fill: Colors.red, zIndex: 1);
    final blackMask = _rectangleNode(
      'mask',
      fill: Colors.black,
      width: 50,
      height: 100,
      visible: false,
      zIndex: -1,
    );

    final luminanceImage = await _renderCanvas([
      source.copyWith(
        payload: (source.payload as VectorPathPayload).copyWith(
          maskNodeId: blackMask.id,
          maskMode: VectorMaskMode.luminance,
        ),
      ),
      blackMask,
    ]);
    final invertedImage = await _renderCanvas([
      source.copyWith(
        payload: (source.payload as VectorPathPayload).copyWith(
          maskNodeId: blackMask.id,
          maskMode: VectorMaskMode.invertedLuminance,
        ),
      ),
      blackMask,
    ]);

    final luminancePixel = await _pixel(luminanceImage, 20, 50);
    final invertedPixel = await _pixel(invertedImage, 20, 50);
    expect(luminancePixel.a, lessThan(0.04));
    expect(invertedPixel.a, greaterThan(0.94));
    luminanceImage.dispose();
    invertedImage.dispose();
  });

  test('vector mask follows the mask node rotation', () async {
    final source = _rectangleNode('source', fill: Colors.red, zIndex: 1);
    final rotatedMask = _rectangleNode(
      'rotated-mask',
      x: 10,
      y: 40,
      width: 80,
      height: 20,
      rotation: 1.5707963267948966,
      fill: Colors.white,
      visible: false,
      zIndex: -1,
    );
    final maskedSource = source.copyWith(
      payload: (source.payload as VectorPathPayload).copyWith(
        maskNodeId: rotatedMask.id,
      ),
    );

    final image = await _renderCanvas([maskedSource, rotatedMask]);
    final rotatedInside = await _pixel(image, 40, 20);
    final rotatedOutside = await _pixel(image, 10, 20);
    expect(rotatedInside.a, greaterThan(0.94));
    expect(rotatedOutside.a, lessThan(0.04));
    image.dispose();
  });
}
