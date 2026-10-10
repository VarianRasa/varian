import 'dart:ui';

import '../../../domain/models/vector_path_payload.dart';
import '../../../domain/models/node_payload.dart';

enum VectorBooleanOperation { union, intersect, difference, xor }

class VectorPathSplitResult {
  final VectorPathPayload first;
  final VectorPathPayload second;

  const VectorPathSplitResult({required this.first, required this.second});
}

class VectorPathEditing {
  const VectorPathEditing._();

  static VectorPathPayload updateAnchor(
    VectorPathPayload payload, {
    int subpathIndex = 0,
    required int pointIndex,
    Offset? point,
    Offset? handleIn,
    Offset? handleOut,
    PointType? type,
    double? cornerRadius,
  }) {
    final contours = _mutableContours(payload);
    final closed = _mutableClosed(payload, contours.length);
    _checkSubpath(contours, subpathIndex);
    final contour = contours[subpathIndex];
    if (pointIndex < 0 || pointIndex >= contour.length) {
      throw RangeError.index(pointIndex, contour, 'pointIndex');
    }
    final current = contour[pointIndex];
    var next = current.copyWith(
      point: point,
      handleIn: handleIn,
      handleOut: handleOut,
      type: type,
      cornerRadius: cornerRadius,
    );
    if (type == PointType.corner) {
      next = next.copyWith(handleIn: Offset.zero, handleOut: Offset.zero);
    } else if (type == PointType.mirrored) {
      final out = next.handleOut;
      final length = out.distance;
      if (length > 0 && next.handleIn.distance > 0) {
        final direction = -out / length;
        next = next.copyWith(handleIn: direction * next.handleIn.distance);
      }
    }
    contour[pointIndex] = next;
    return _withContours(payload, contours, closed);
  }

  static VectorPathPayload moveHandle(
    VectorPathPayload payload, {
    int subpathIndex = 0,
    required int pointIndex,
    required Offset handle,
    required bool incoming,
    bool preserveSymmetry = false,
  }) {
    final contours = _mutableContours(payload);
    final closed = _mutableClosed(payload, contours.length);
    _checkSubpath(contours, subpathIndex);
    final contour = contours[subpathIndex];
    if (pointIndex < 0 || pointIndex >= contour.length) {
      throw RangeError.index(pointIndex, contour, 'pointIndex');
    }
    final current = contour[pointIndex];
    var next = incoming
        ? current.copyWith(handleIn: handle)
        : current.copyWith(handleOut: handle);
    if (preserveSymmetry || current.type == PointType.mirrored) {
      final distance = handle.distance;
      if (distance > 0) {
        final direction = -handle / distance;
        final opposite =
            direction *
            (incoming ? current.handleOut.distance : current.handleIn.distance);
        next = incoming
            ? next.copyWith(handleOut: opposite)
            : next.copyWith(handleIn: opposite);
      }
    }
    contour[pointIndex] = next;
    return _withContours(payload, contours, closed);
  }

  static VectorPathPayload toggleSubpathClosed(
    VectorPathPayload payload, {
    int subpathIndex = 0,
    bool? closed,
  }) {
    final contours = _mutableContours(payload);
    final nextClosed = _mutableClosed(payload, contours.length);
    _checkSubpath(contours, subpathIndex);
    nextClosed[subpathIndex] = closed ?? !nextClosed[subpathIndex];
    return _withContours(payload, contours, nextClosed);
  }

  static VectorPathPayload reverseSubpath(
    VectorPathPayload payload, {
    int subpathIndex = 0,
  }) {
    final contours = _mutableContours(payload);
    final closed = _mutableClosed(payload, contours.length);
    _checkSubpath(contours, subpathIndex);
    contours[subpathIndex] = contours[subpathIndex].reversed
        .map(
          (point) => point.copyWith(
            handleIn: point.handleOut,
            handleOut: point.handleIn,
          ),
        )
        .toList(growable: false);
    return _withContours(payload, contours, closed);
  }

  static VectorPathPayload setAppearance(
    VectorPathPayload payload, {
    Color? fill,
    Color? stroke,
    double? strokeWidth,
    VectorStrokeCap? strokeCap,
    VectorStrokeJoin? strokeJoin,
    List<double>? dashPattern,
    double? dashOffset,
    bool? isGradientFill,
    FillType? gradientType,
    Color? gradientEndColor,
    Object? maskNodeId = _sentinel,
    VectorMaskMode? maskMode,
    List<VectorEffect>? effects,
  }) => payload.copyWith(
    fill: fill,
    stroke: stroke,
    strokeWidth: strokeWidth,
    strokeCap: strokeCap,
    strokeJoin: strokeJoin,
    dashPattern: dashPattern,
    dashOffset: dashOffset,
    isGradientFill: isGradientFill,
    gradientType: gradientType,
    gradientEndColor: gradientEndColor,
    maskNodeId: maskNodeId,
    maskMode: maskMode,
    effects: effects,
  );

  static const Object _sentinel = Object();

  static VectorPathPayload insertAnchor(
    VectorPathPayload payload, {
    int subpathIndex = 0,
    required int segmentIndex,
    double t = 0.5,
  }) {
    final contours = _mutableContours(payload);
    final closed = _mutableClosed(payload, contours.length);
    _checkSubpath(contours, subpathIndex);
    final contour = contours[subpathIndex];
    if (contour.length < 2) {
      throw ArgumentError('A path needs at least two anchors.');
    }
    final isWrapSegment =
        closed[subpathIndex] && segmentIndex == contour.length - 1;
    if (segmentIndex < 0 ||
        segmentIndex >= contour.length - (isWrapSegment ? 0 : 1)) {
      throw RangeError.index(segmentIndex, contour, 'segmentIndex');
    }

    final nextIndex = isWrapSegment ? 0 : segmentIndex + 1;
    final from = contour[segmentIndex];
    final to = contour[nextIndex];
    final split = _splitCubic(from, to, t.clamp(0.0, 1.0).toDouble());
    contour[segmentIndex] = from.copyWith(handleOut: split.leftHandleOut);
    contour[nextIndex] = to.copyWith(handleIn: split.rightHandleIn);
    final inserted = BezierPoint(
      point: split.point,
      handleIn: split.handleIn,
      handleOut: split.handleOut,
      type: from.type == PointType.corner && to.type == PointType.corner
          ? PointType.corner
          : PointType.disconnected,
    );
    if (isWrapSegment) {
      contour.add(inserted);
    } else {
      contour.insert(nextIndex, inserted);
    }
    return _withContours(payload, contours, closed);
  }

  static VectorPathPayload removeAnchor(
    VectorPathPayload payload, {
    int subpathIndex = 0,
    required int pointIndex,
  }) {
    final contours = _mutableContours(payload);
    final closed = _mutableClosed(payload, contours.length);
    _checkSubpath(contours, subpathIndex);
    final contour = contours[subpathIndex];
    final minimum = closed[subpathIndex] ? 3 : 2;
    if (contour.length <= minimum) {
      throw StateError('Cannot remove an anchor from the minimum path.');
    }
    if (pointIndex < 0 || pointIndex >= contour.length) {
      throw RangeError.index(pointIndex, contour, 'pointIndex');
    }
    contour.removeAt(pointIndex);
    return _withContours(payload, contours, closed);
  }

  static VectorPathSplitResult splitSubpath(
    VectorPathPayload payload, {
    int subpathIndex = 0,
    required int pointIndex,
  }) {
    final contours = _mutableContours(payload);
    _checkSubpath(contours, subpathIndex);
    final contour = contours[subpathIndex];
    if (pointIndex <= 0 || pointIndex >= contour.length - 1) {
      throw RangeError('pointIndex must split an interior anchor.');
    }
    final firstPoints = contour.sublist(0, pointIndex + 1);
    final secondPoints = contour.sublist(pointIndex);
    final firstContours = [...contours]..[subpathIndex] = firstPoints;
    final secondContours = [...contours]..[subpathIndex] = secondPoints;
    final closed = List<bool>.filled(contours.length, false);
    return VectorPathSplitResult(
      first: _withContours(payload, firstContours, closed),
      second: _withContours(payload, secondContours, closed),
    );
  }

  static VectorPathPayload joinSubpaths(
    VectorPathPayload payload, {
    required int firstSubpathIndex,
    required int secondSubpathIndex,
    bool closeResult = false,
  }) {
    final contours = _mutableContours(payload);
    final closed = _mutableClosed(payload, contours.length);
    _checkSubpath(contours, firstSubpathIndex);
    _checkSubpath(contours, secondSubpathIndex);
    if (firstSubpathIndex == secondSubpathIndex) {
      throw ArgumentError('Joining requires two different subpaths.');
    }
    final first = contours[firstSubpathIndex];
    final second = contours[secondSubpathIndex];
    final merged = <BezierPoint>[...first];
    if (merged.isNotEmpty &&
        second.isNotEmpty &&
        merged.last.point == second.first.point) {
      merged.addAll(second.skip(1));
    } else {
      merged.addAll(second);
    }
    final keepIndex = firstSubpathIndex < secondSubpathIndex
        ? firstSubpathIndex
        : secondSubpathIndex;
    final removeIndex = firstSubpathIndex < secondSubpathIndex
        ? secondSubpathIndex
        : firstSubpathIndex;
    contours[keepIndex] = merged;
    contours.removeAt(removeIndex);
    closed.removeAt(removeIndex);
    closed[keepIndex] = closeResult;
    return _withContours(payload, contours, closed);
  }

  static VectorPathPayload booleanCombine(
    VectorPathPayload first,
    VectorPathPayload second,
    VectorBooleanOperation operation, {
    double sampleSpacing = 8.0,
  }) {
    final path = Path.combine(
      _pathOperation(operation),
      first.toPath(closeOpenSubpaths: true),
      second.toPath(closeOpenSubpaths: true),
    );
    final contours = _samplePath(path, sampleSpacing: sampleSpacing);
    if (contours.isEmpty) {
      return first.copyWith(
        points: const [],
        isClosed: true,
        subpaths: const [],
        subpathClosed: const [],
      );
    }
    return first.copyWith(
      points: contours.first,
      isClosed: true,
      subpaths: contours,
      subpathClosed: List<bool>.filled(contours.length, true),
    );
  }

  static VectorPathPayload translate(VectorPathPayload payload, Offset offset) {
    final contours = payload.allSubpaths
        .map(
          (contour) => contour
              .map((point) => point.copyWith(point: point.point + offset))
              .toList(growable: false),
        )
        .toList(growable: false);
    return _withContours(
      payload,
      contours,
      _mutableClosed(payload, contours.length),
    );
  }

  static List<List<BezierPoint>> _mutableContours(VectorPathPayload payload) =>
      payload.allSubpaths
          .map((contour) => List<BezierPoint>.of(contour))
          .toList();

  static List<bool> _mutableClosed(VectorPathPayload payload, int count) {
    final source = payload.allSubpathClosed;
    return List<bool>.generate(
      count,
      (index) => index < source.length ? source[index] : payload.isClosed,
    );
  }

  static void _checkSubpath(List<List<BezierPoint>> contours, int index) {
    if (index < 0 || index >= contours.length) {
      throw RangeError.index(index, contours, 'subpathIndex');
    }
  }

  static VectorPathPayload _withContours(
    VectorPathPayload source,
    List<List<BezierPoint>> contours,
    List<bool> closed,
  ) {
    final simple = source.subpaths.isEmpty && contours.length == 1;
    return source.copyWith(
      points: contours.expand((contour) => contour).toList(growable: false),
      isClosed: closed.isNotEmpty && closed.first,
      subpaths: simple ? const [] : contours,
      subpathClosed: simple ? const [] : closed,
    );
  }

  static _CubicSplit _splitCubic(BezierPoint from, BezierPoint to, double t) {
    Offset lerp(Offset a, Offset b) => a + (b - a) * t;
    final p0 = from.point;
    final p1 = from.point + from.handleOut;
    final p2 = to.point + to.handleIn;
    final p3 = to.point;
    final q0 = lerp(p0, p1);
    final q1 = lerp(p1, p2);
    final q2 = lerp(p2, p3);
    final r0 = lerp(q0, q1);
    final r1 = lerp(q1, q2);
    final point = lerp(r0, r1);
    return _CubicSplit(
      point: point,
      leftHandleOut: q0 - p0,
      handleIn: r0 - point,
      handleOut: r1 - point,
      rightHandleIn: q2 - p3,
    );
  }

  static PathOperation _pathOperation(VectorBooleanOperation operation) {
    return switch (operation) {
      VectorBooleanOperation.union => PathOperation.union,
      VectorBooleanOperation.intersect => PathOperation.intersect,
      VectorBooleanOperation.difference => PathOperation.difference,
      VectorBooleanOperation.xor => PathOperation.xor,
    };
  }

  static List<List<BezierPoint>> _samplePath(
    Path path, {
    required double sampleSpacing,
  }) {
    final spacing = sampleSpacing.isFinite && sampleSpacing > 0
        ? sampleSpacing.clamp(0.5, 100.0).toDouble()
        : 8.0;
    final result = <List<BezierPoint>>[];
    var totalPoints = 0;
    for (final metric in path.computeMetrics(forceClosed: true)) {
      if (metric.length <= 0) continue;
      final count = (metric.length / spacing).ceil().clamp(3, 512);
      final points = <BezierPoint>[];
      for (var index = 0; index < count; index++) {
        final tangent = metric.getTangentForOffset(
          metric.length * index / count,
        );
        if (tangent == null) continue;
        points.add(
          BezierPoint(point: tangent.position, type: PointType.corner),
        );
      }
      if (points.length >= 3) {
        result.add(points);
        totalPoints += points.length;
        if (totalPoints >= 4096) break;
      }
    }
    return result;
  }
}

class _CubicSplit {
  final Offset point;
  final Offset leftHandleOut;
  final Offset handleIn;
  final Offset handleOut;
  final Offset rightHandleIn;

  const _CubicSplit({
    required this.point,
    required this.leftHandleOut,
    required this.handleIn,
    required this.handleOut,
    required this.rightHandleIn,
  });
}
