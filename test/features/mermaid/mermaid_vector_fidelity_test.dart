import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/vector_path_payload.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';
import 'package:varian/features/mermaid/domain/mermaid_svg_native_converter.dart';

const _red = Color(0xFFFF0000);
const _outer = [
  BezierPoint(point: Offset(10, 10)),
  BezierPoint(point: Offset(90, 10)),
  BezierPoint(point: Offset(90, 90)),
  BezierPoint(point: Offset(10, 90)),
];
const _inner = [
  BezierPoint(
    point: Offset(30, 30),
    handleIn: Offset(0, 8),
    handleOut: Offset(8, 0),
    type: PointType.disconnected,
  ),
  BezierPoint(point: Offset(70, 30)),
  BezierPoint(point: Offset(70, 70)),
  BezierPoint(point: Offset(30, 70)),
];

VectorPathPayload _compoundPayload() => VectorPathPayload(
  points: List.of(_outer),
  subpaths: [List.of(_outer), List.of(_inner)],
  subpathClosed: [true, false],
  fillRule: VectorFillRule.evenOdd,
  fill: _red,
  stroke: Colors.transparent,
  strokeWidth: 0,
);

void _expectCompoundGeometry(VectorPathPayload payload) {
  expect(payload.points, isNotEmpty);
  expect(
    payload.allSubpaths
        .map((path) => path.map((point) => point.point).toList())
        .toList(),
    [
      [
        const Offset(10, 10),
        const Offset(90, 10),
        const Offset(90, 90),
        const Offset(10, 90),
      ],
      [
        const Offset(30, 30),
        const Offset(70, 30),
        const Offset(70, 70),
        const Offset(30, 70),
      ],
    ],
  );
  expect(payload.isClosed, isTrue);
  expect(payload.allSubpathClosed, [true, false]);
  expect(payload.fillRule, VectorFillRule.evenOdd);
  final curvedAnchor = payload.allSubpaths[1].first;
  expect(curvedAnchor.handleIn, const Offset(0, 8));
  expect(curvedAnchor.handleOut, const Offset(8, 0));
  expect(curvedAnchor.type, PointType.disconnected);
}

CanvasNode _sourceNode() => CanvasNode(
  id: 'mermaid-source',
  type: NodeType.mermaid,
  x: 0,
  y: 0,
  width: 100,
  height: 100,
  payload: MermaidPayload(source: 'flowchart TD\n  A[Canonical source]'),
);

String _svg(String content) =>
    '<svg xmlns="http://www.w3.org/2000/svg" '
    'width="100" height="100" viewBox="0 0 100 100">$content</svg>';

CanvasNode _convertPath(
  String data, {
  String attributes = 'fill="#ff0000" stroke="none"',
}) {
  final result = MermaidSvgNativeConverter.convert(
    _sourceNode(),
    _svg('<path d="$data" $attributes />'),
  );
  expect(result.isSuccess, isTrue, reason: result.diagnostic?.message);
  expect(result.renderedSvg, isNotNull);
  expect(result.edges, isEmpty);
  expect(result.nodes, hasLength(1));
  expect(result.nodes.single.type, NodeType.vectorPath);
  expect(result.nodes.single.mermaidSourceId, 'mermaid-source');
  return result.nodes.single;
}

CanvasNode _vectorNode(VectorPathPayload payload) => CanvasNode(
  id: 'vector',
  type: NodeType.vectorPath,
  x: 0,
  y: 0,
  width: 100,
  height: 100,
  payload: payload,
);

Future<ByteData> _paint(CanvasNode node) async {
  final recorder = ui.PictureRecorder();
  NodePainter.paint(Canvas(recorder), node);
  final picture = recorder.endRecording();
  addTearDown(picture.dispose);
  final image = await picture.toImage(100, 100);
  addTearDown(image.dispose);
  return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
}

Color _pixel(ByteData data, int x, int y) {
  final offset = (y * 100 + x) * 4;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

void main() {
  test(
    'compound path JSON roundtrip preserves contours, closure and handles',
    () {
      final json =
          jsonDecode(jsonEncode(_compoundPayload().toJson()))
              as Map<String, dynamic>;
      expect(json['subpaths'], hasLength(2));
      expect(json['subpathClosed'], [true, false]);
      expect(json['fillRule'], 'evenOdd');
      final restored = VectorPathPayload.fromJson(json);
      _expectCompoundGeometry(restored);
      expect(restored.fill, _red);
    },
  );

  test(
    'compound path clone preserves geometry without sharing mutable lists',
    () {
      final original = _compoundPayload();
      final clone = original.clone();
      _expectCompoundGeometry(clone);
      expect(identical(clone.points, original.points), isFalse);
      expect(identical(clone.subpaths, original.subpaths), isFalse);
      expect(identical(clone.subpaths[0], original.subpaths[0]), isFalse);
      expect(identical(clone.subpaths[1], original.subpaths[1]), isFalse);
      expect(identical(clone.subpathClosed, original.subpathClosed), isFalse);
      _expectCompoundGeometry(original);
    },
  );

  test('compound path copyWith preserves geometry during a style edit', () {
    final original = _compoundPayload();
    final copy = original.copyWith(fill: Colors.blue, strokeWidth: 3);
    _expectCompoundGeometry(copy);
    expect(copy.fill, Colors.blue);
    expect(copy.strokeWidth, 3);
    expect(original.fill, _red);
    expect(original.strokeWidth, 0);

    final changed = copy.copyWith(
      subpaths: [List.of(_inner)],
      subpathClosed: [false],
      fillRule: VectorFillRule.nonZero,
    );
    expect(changed.allSubpaths, hasLength(1));
    expect(changed.allSubpaths.single.first.point, const Offset(30, 30));
    expect(changed.allSubpathClosed, [false]);
    expect(changed.fillRule, VectorFillRule.nonZero);
  });

  for (final rule in VectorFillRule.values) {
    test(
      'NodePainter applies ${rule.name} to same-winding nested contours',
      () async {
        final bytes = await _paint(
          _vectorNode(
            _compoundPayload().copyWith(
              subpathClosed: [true, true],
              fillRule: rule,
            ),
          ),
        );
        expect(
          _pixel(bytes, 20, 50),
          _red,
          reason: 'The outer ring is filled.',
        );
        expect(_pixel(bytes, 5, 50), Colors.transparent);
        expect(
          _pixel(bytes, 50, 50),
          rule == VectorFillRule.evenOdd ? Colors.transparent : _red,
          reason:
              'Only evenodd creates a hole for contours with the same winding.',
        );
      },
    );
  }

  test(
    'SVG evenodd fill survives conversion and paints a transparent hole',
    () async {
      final node = _convertPath(
        'M10 10 H90 V90 H10 Z M30 30 H70 V70 H30 Z',
        attributes: 'fill="#ff0000" stroke="none" fill-rule="evenodd"',
      );
      final payload = node.payload as VectorPathPayload;
      expect(payload.fillRule, VectorFillRule.evenOdd);
      expect(payload.allSubpaths, hasLength(2));
      expect(payload.allSubpathClosed, [true, true]);
      final bytes = await _paint(node);
      expect(_pixel(bytes, 20, 50), _red);
      expect(_pixel(bytes, 50, 50), Colors.transparent);
    },
  );

  test('multiple SVG M/Z contours never acquire a connecting stroke', () async {
    final node = _convertPath(
      'M10 20 H30 V40 H10 Z m60 0 h20 v20 h-20 z',
      attributes: 'fill="none" stroke="#000000" stroke-width="4"',
    );
    final payload = node.payload as VectorPathPayload;
    expect(payload.allSubpaths.map((path) => path.length), [4, 4]);
    expect(payload.allSubpathClosed, [true, true]);
    expect(
      payload.allSubpaths.map((path) => node.bounds.topLeft + path.first.point),
      [const Offset(10, 20), const Offset(70, 20)],
    );
    final bytes = await _paint(node);
    expect(_pixel(bytes, 10, 30), Colors.black);
    expect(_pixel(bytes, 70, 30), Colors.black);
    expect(
      _pixel(bytes, 40, 30),
      Colors.transparent,
      reason: 'Flattening the anchors joins the two independent rectangles.',
    );
    expect(_pixel(bytes, 50, 20), Colors.transparent);
  });

  test('SVG close commands do not close a subsequent open contour', () async {
    final node = _convertPath(
      'M10 10 H30 V30 H10 Z M60 10 H90 V40',
      attributes: 'fill="none" stroke="#000000" stroke-width="4"',
    );
    final payload = node.payload as VectorPathPayload;
    expect(payload.allSubpathClosed, [true, false]);
    final bytes = await _paint(node);
    expect(_pixel(bytes, 10, 20), Colors.black);
    expect(_pixel(bytes, 90, 25), Colors.black);
    expect(
      _pixel(bytes, 75, 25),
      Colors.transparent,
      reason: 'The open contour must not gain a diagonal closing stroke.',
    );
  });

  test(
    'NodePainter closes a two-anchor loop using both cubic handles',
    () async {
      final bytes = await _paint(
        _vectorNode(
          VectorPathPayload(
            points: const [
              BezierPoint(
                point: Offset(20, 50),
                handleIn: Offset(0, 40),
                handleOut: Offset(0, -40),
              ),
              BezierPoint(
                point: Offset(80, 50),
                handleIn: Offset(0, -40),
                handleOut: Offset(0, 40),
              ),
            ],
            isClosed: true,
            fill: _red,
            stroke: Colors.black,
            strokeWidth: 4,
          ),
        ),
      );
      expect(_pixel(bytes, 50, 20), Colors.black);
      expect(
        _pixel(bytes, 50, 79),
        Colors.black,
        reason:
            'The last outgoing and first incoming handles form the return arc.',
      );
      expect(_pixel(bytes, 50, 50), _red);
      expect(_pixel(bytes, 50, 5), Colors.transparent);
    },
  );

  test(
    'closed SVG with two cubic anchors retains its fill and closing stroke',
    () async {
      final node = _convertPath(
        'M20 50 C20 10 80 10 80 50 Z',
        attributes: 'fill="#ff0000" stroke="#000000" stroke-width="4"',
      );
      final payload = node.payload as VectorPathPayload;
      expect(payload.allSubpaths.single, hasLength(2));
      expect(payload.allSubpathClosed, [true]);
      final bytes = await _paint(node);
      expect(_pixel(bytes, 50, 35), _red);
      expect(_pixel(bytes, 50, 50), Colors.black);
      expect(_pixel(bytes, 50, 65), Colors.transparent);
    },
  );

  test(
    'open SVG paths are implicitly closed for fill but not for stroke',
    () async {
      final node = _convertPath(
        'M20 20 L80 20 L80 80',
        attributes: 'fill="#ff0000" stroke="#000000" stroke-width="4"',
      );
      final payload = node.payload as VectorPathPayload;
      expect(payload.allSubpathClosed, [false]);
      expect(payload.fill, _red);
      final bytes = await _paint(node);
      expect(
        _pixel(bytes, 65, 35),
        _red,
        reason: 'SVG fills open subpaths without requiring a Z command.',
      );
      expect(
        _pixel(bytes, 50, 49),
        _red,
        reason: 'Implicit fill closure must not add a black diagonal stroke.',
      );
      expect(_pixel(bytes, 50, 20), Colors.black);
      expect(_pixel(bytes, 35, 65), Colors.transparent);
    },
  );

  test(
    'SVG arcs remain editable curves with tangent handles, not polygons',
    () async {
      final node = _convertPath(
        'M80 50 A30 30 0 0 1 50 80',
        attributes: 'fill="none" stroke="#000000" stroke-width="4"',
      );
      final payload = node.payload as VectorPathPayload;
      final anchors = payload.allSubpaths.single;
      expect(payload.allSubpathClosed, [false]);
      final start = node.bounds.topLeft + anchors.first.point;
      final end = node.bounds.topLeft + anchors.last.point;
      expect(start.dx, closeTo(80, 0.001));
      expect(start.dy, closeTo(50, 0.001));
      expect(end.dx, closeTo(50, 0.001));
      expect(end.dy, closeTo(80, 0.001));
      expect(anchors.first.handleOut.dx, closeTo(0, 0.001));
      expect(
        anchors.first.handleOut.dy,
        greaterThan(0),
        reason: 'A quarter-circle starts with a vertical tangent, not a chord.',
      );
      expect(anchors.last.handleIn.dx, greaterThan(0));
      expect(anchors.last.handleIn.dy, closeTo(0, 0.001));
      final bytes = await _paint(node);
      expect(_pixel(bytes, 71, 71), Colors.black);
      expect(_pixel(bytes, 65, 65), Colors.transparent);
    },
  );

  const invalidPaths = {
    'unrecognized punctuation': 'M10 10 L90 10 @ L90 90 Z',
    'unsupported command': 'M10 10 L90 10 X90 90 Z',
    'incomplete coordinate pair': 'M10 10 L90 10 L90 Z',
    'numbers after close': 'M10 10 L90 10 L90 90 Z 50 50',
    'missing initial moveto': 'L10 10 L90 90',
    'nonfinite endpoint': 'M10 10 L1e309 90 Z',
    'nonfinite cubic control': 'M10 10 C20 20 1e309 30 90 90 Z',
    'NaN endpoint': 'M10 10 LNaN 90 Z',
    'Infinity endpoint': 'M10 10 LInfinity 90 Z',
    'invalid arc flag': 'M10 50 A40 40 0 2 0 90 50',
  };
  for (final invalid in invalidPaths.entries) {
    test('invalid SVG path rejects ${invalid.key} atomically', () {
      final source = _sourceNode();
      final before = jsonEncode(source.toJson());
      final result = MermaidSvgNativeConverter.convert(
        source,
        _svg('''
<rect id="a" x="10" y="10" width="20" height="20" />
<rect id="b" x="70" y="10" width="20" height="20" />
<path data-source-id="a" data-target-id="b" d="M30 20 L70 20" stroke="#000000" fill="none" />
<path d="${invalid.value}" fill="#ff0000" />
'''),
      );
      expect(result.isSuccess, isFalse, reason: invalid.value);
      expect(result.diagnostic, isNotNull);
      expect(
        result.nodes,
        isEmpty,
        reason: 'Do not retain earlier valid shapes.',
      );
      expect(
        result.edges,
        isEmpty,
        reason: 'Do not retain earlier valid connectors.',
      );
      expect(result.renderedSvg, isNull);
      expect(
        jsonEncode(source.toJson()),
        before,
        reason: 'The editable canonical Mermaid source must remain unchanged.',
      );
    });
  }
}
