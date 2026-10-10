import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/models/node.dart';

enum CanvasGridPreset { none, dots, lines, majorMinor, isometric }

enum CanvasSnapMode { off, grid, guides, objects, all }

enum CanvasGuideAxis { horizontal, vertical }

enum CanvasLayoutPreset { freeform, horizontal, vertical, grid }

enum CanvasSpacingPreset { none, tight, compact, regular, relaxed }

extension CanvasSpacingPresetValues on CanvasSpacingPreset {
  double get value => switch (this) {
    CanvasSpacingPreset.none => 0.0,
    CanvasSpacingPreset.tight => 8.0,
    CanvasSpacingPreset.compact => 12.0,
    CanvasSpacingPreset.regular => 16.0,
    CanvasSpacingPreset.relaxed => 24.0,
  };

  String get label => switch (this) {
    CanvasSpacingPreset.none => 'None',
    CanvasSpacingPreset.tight => 'Tight',
    CanvasSpacingPreset.compact => 'Compact',
    CanvasSpacingPreset.regular => 'Regular',
    CanvasSpacingPreset.relaxed => 'Relaxed',
  };
}

enum CanvasHorizontalConstraint { left, center, right, leftRight, scale }

enum CanvasVerticalConstraint { top, center, bottom, topBottom, scale }

class CanvasNodeConstraints {
  final CanvasHorizontalConstraint horizontal;
  final CanvasVerticalConstraint vertical;

  const CanvasNodeConstraints({
    this.horizontal = CanvasHorizontalConstraint.left,
    this.vertical = CanvasVerticalConstraint.top,
  });

  CanvasNodeConstraints copyWith({
    CanvasHorizontalConstraint? horizontal,
    CanvasVerticalConstraint? vertical,
  }) {
    return CanvasNodeConstraints(
      horizontal: horizontal ?? this.horizontal,
      vertical: vertical ?? this.vertical,
    );
  }

  Map<String, dynamic> toJson() => {
    'horizontal': horizontal.name,
    'vertical': vertical.name,
  };

  factory CanvasNodeConstraints.fromJson(Object? raw) {
    if (raw is! Map) return const CanvasNodeConstraints();
    final horizontal = CanvasHorizontalConstraint.values.firstWhere(
      (value) => value.name == raw['horizontal']?.toString(),
      orElse: () => CanvasHorizontalConstraint.left,
    );
    final vertical = CanvasVerticalConstraint.values.firstWhere(
      (value) => value.name == raw['vertical']?.toString(),
      orElse: () => CanvasVerticalConstraint.top,
    );
    return CanvasNodeConstraints(horizontal: horizontal, vertical: vertical);
  }
}

class CanvasConstraintEngine {
  const CanvasConstraintEngine._();

  static CanvasNode resolve(
    CanvasNode node, {
    required Rect oldParent,
    required Rect newParent,
  }) {
    if (!_validRect(oldParent) || !_validRect(newParent)) return node;

    final oldWidth = oldParent.width;
    final oldHeight = oldParent.height;
    final newWidth = newParent.width;
    final newHeight = newParent.height;
    var nextX = node.x;
    var nextY = node.y;
    var nextWidth = node.width;
    var nextHeight = node.height;
    final constraints = node.constraints;

    if (constraints == null) return node;

    switch (constraints.horizontal) {
      case CanvasHorizontalConstraint.left:
        nextX = newParent.left + (node.bounds.left - oldParent.left);
        break;
      case CanvasHorizontalConstraint.center:
        nextX =
            newParent.center.dx +
            (node.bounds.center.dx - oldParent.center.dx) -
            node.width / 2;
        break;
      case CanvasHorizontalConstraint.right:
        nextX =
            newParent.right -
            (oldParent.right - node.bounds.right) -
            node.width;
        break;
      case CanvasHorizontalConstraint.leftRight:
        final leftMargin = node.bounds.left - oldParent.left;
        final rightMargin = oldParent.right - node.bounds.right;
        nextX = newParent.left + leftMargin;
        nextWidth = math.max(0, newWidth - leftMargin - rightMargin);
        break;
      case CanvasHorizontalConstraint.scale:
        final ratio = newWidth / oldWidth;
        nextX = newParent.left + (node.bounds.left - oldParent.left) * ratio;
        nextWidth = node.width * ratio;
        break;
    }

    switch (constraints.vertical) {
      case CanvasVerticalConstraint.top:
        nextY = newParent.top + (node.bounds.top - oldParent.top);
        break;
      case CanvasVerticalConstraint.center:
        nextY =
            newParent.center.dy +
            (node.bounds.center.dy - oldParent.center.dy) -
            node.height / 2;
        break;
      case CanvasVerticalConstraint.bottom:
        nextY =
            newParent.bottom -
            (oldParent.bottom - node.bounds.bottom) -
            node.height;
        break;
      case CanvasVerticalConstraint.topBottom:
        final topMargin = node.bounds.top - oldParent.top;
        final bottomMargin = oldParent.bottom - node.bounds.bottom;
        nextY = newParent.top + topMargin;
        nextHeight = math.max(0, newHeight - topMargin - bottomMargin);
        break;
      case CanvasVerticalConstraint.scale:
        final ratio = newHeight / oldHeight;
        nextY = newParent.top + (node.bounds.top - oldParent.top) * ratio;
        nextHeight = node.height * ratio;
        break;
    }

    return node.copyWith(
      x: nextX,
      y: nextY,
      width: nextWidth,
      height: nextHeight,
    );
  }

  static bool _validRect(Rect rect) =>
      rect.left.isFinite &&
      rect.top.isFinite &&
      rect.width.isFinite &&
      rect.height.isFinite &&
      rect.width > 0 &&
      rect.height > 0;
}

class CanvasGuide {
  final String id;
  final CanvasGuideAxis axis;
  final double position;
  final String? label;
  final bool locked;

  const CanvasGuide({
    required this.id,
    required this.axis,
    required this.position,
    this.label,
    this.locked = false,
  });

  CanvasGuide copyWith({
    String? id,
    CanvasGuideAxis? axis,
    double? position,
    Object? label = _sentinel,
    bool? locked,
  }) {
    return CanvasGuide(
      id: id ?? this.id,
      axis: axis ?? this.axis,
      position: position ?? this.position,
      label: label == _sentinel ? this.label : label as String?,
      locked: locked ?? this.locked,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'axis': axis.name,
    'position': position,
    'label': label,
    'locked': locked,
  };

  factory CanvasGuide.fromJson(Map<String, dynamic> json) {
    final axisName = json['axis']?.toString();
    final axis = CanvasGuideAxis.values.firstWhere(
      (value) => value.name == axisName,
      orElse: () => CanvasGuideAxis.vertical,
    );
    return CanvasGuide(
      id: json['id']?.toString() ?? '',
      axis: axis,
      position: (json['position'] as num?)?.toDouble() ?? 0,
      label: json['label']?.toString(),
      locked: json['locked'] as bool? ?? false,
    );
  }

  static const Object _sentinel = Object();
}

class CanvasPrecisionState {
  static const int schemaVersion = 1;

  final bool gridVisible;
  final bool rulersVisible;
  final bool guidesVisible;
  final bool smartGuidesEnabled;
  final bool measurementsVisible;
  final CanvasGridPreset gridPreset;
  final double gridSpacing;
  final int gridSubdivisions;
  final CanvasSnapMode snapMode;
  final CanvasLayoutPreset layoutPreset;
  final List<CanvasGuide> guides;

  const CanvasPrecisionState({
    this.gridVisible = true,
    this.rulersVisible = false,
    this.guidesVisible = true,
    this.smartGuidesEnabled = true,
    this.measurementsVisible = true,
    this.gridPreset = CanvasGridPreset.dots,
    this.gridSpacing = 28,
    this.gridSubdivisions = 4,
    this.snapMode = CanvasSnapMode.all,
    this.layoutPreset = CanvasLayoutPreset.freeform,
    this.guides = const [],
  });

  CanvasPrecisionState copyWith({
    bool? gridVisible,
    bool? rulersVisible,
    bool? guidesVisible,
    bool? smartGuidesEnabled,
    bool? measurementsVisible,
    CanvasGridPreset? gridPreset,
    double? gridSpacing,
    int? gridSubdivisions,
    CanvasSnapMode? snapMode,
    CanvasLayoutPreset? layoutPreset,
    List<CanvasGuide>? guides,
  }) {
    return CanvasPrecisionState(
      gridVisible: gridVisible ?? this.gridVisible,
      rulersVisible: rulersVisible ?? this.rulersVisible,
      guidesVisible: guidesVisible ?? this.guidesVisible,
      smartGuidesEnabled: smartGuidesEnabled ?? this.smartGuidesEnabled,
      measurementsVisible: measurementsVisible ?? this.measurementsVisible,
      gridPreset: gridPreset ?? this.gridPreset,
      gridSpacing: gridSpacing ?? this.gridSpacing,
      gridSubdivisions: gridSubdivisions ?? this.gridSubdivisions,
      snapMode: snapMode ?? this.snapMode,
      layoutPreset: layoutPreset ?? this.layoutPreset,
      guides: guides ?? this.guides,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'gridVisible': gridVisible,
    'rulersVisible': rulersVisible,
    'guidesVisible': guidesVisible,
    'smartGuidesEnabled': smartGuidesEnabled,
    'measurementsVisible': measurementsVisible,
    'gridPreset': gridPreset.name,
    'gridSpacing': gridSpacing,
    'gridSubdivisions': gridSubdivisions,
    'snapMode': snapMode.name,
    'layoutPreset': layoutPreset.name,
    'guides': guides.map((guide) => guide.toJson()).toList(),
  };

  factory CanvasPrecisionState.fromJson(Object? raw) {
    if (raw is! Map) return const CanvasPrecisionState();
    final sourceVersion = (raw['schemaVersion'] as num?)?.toInt() ?? 0;
    if (sourceVersion > schemaVersion) {
      throw FormatException(
        'Canvas precision schema $sourceVersion is newer than supported schema $schemaVersion.',
      );
    }
    final gridPreset = CanvasGridPreset.values.firstWhere(
      (value) => value.name == raw['gridPreset']?.toString(),
      orElse: () => CanvasGridPreset.dots,
    );
    final snapMode = CanvasSnapMode.values.firstWhere(
      (value) => value.name == raw['snapMode']?.toString(),
      orElse: () => CanvasSnapMode.all,
    );
    final layoutPreset = CanvasLayoutPreset.values.firstWhere(
      (value) => value.name == raw['layoutPreset']?.toString(),
      orElse: () => CanvasLayoutPreset.freeform,
    );
    final seen = <String>{};
    final guides = <CanvasGuide>[];
    if (raw['guides'] is List) {
      for (final item in (raw['guides'] as List).whereType<Map>()) {
        final guide = CanvasGuide.fromJson(Map<String, dynamic>.from(item));
        if (guide.id.isEmpty || !seen.add(guide.id)) continue;
        guides.add(guide);
      }
    }
    return CanvasPrecisionState(
      gridVisible: raw['gridVisible'] as bool? ?? true,
      rulersVisible: raw['rulersVisible'] as bool? ?? false,
      guidesVisible: raw['guidesVisible'] as bool? ?? true,
      smartGuidesEnabled: raw['smartGuidesEnabled'] as bool? ?? true,
      measurementsVisible: raw['measurementsVisible'] as bool? ?? true,
      gridPreset: gridPreset,
      gridSpacing: CanvasPrecisionMath.clampGridSpacing(
        (raw['gridSpacing'] as num?)?.toDouble() ?? 28,
      ),
      gridSubdivisions: ((raw['gridSubdivisions'] as num?)?.toInt() ?? 4).clamp(
        1,
        16,
      ),
      snapMode: snapMode,
      layoutPreset: layoutPreset,
      guides: List.unmodifiable(guides),
    );
  }
}

class RulerTick {
  final double worldPosition;
  final bool major;
  final String label;

  const RulerTick({
    required this.worldPosition,
    required this.major,
    required this.label,
  });
}

class CanvasPrecisionMath {
  const CanvasPrecisionMath._();

  static double clampGridSpacing(double value) {
    if (!value.isFinite) return 28;
    return value.clamp(4, 512).toDouble();
  }

  static double effectiveGridSpacing(
    CanvasGridPreset preset,
    double customSpacing,
  ) {
    final spacing = clampGridSpacing(customSpacing);
    return switch (preset) {
      CanvasGridPreset.none => spacing,
      CanvasGridPreset.dots => spacing,
      CanvasGridPreset.lines => spacing,
      CanvasGridPreset.majorMinor => spacing,
      CanvasGridPreset.isometric => spacing,
    };
  }

  static Offset snapPointToGrid(
    Offset point, {
    required CanvasPrecisionState state,
  }) {
    if (state.snapMode != CanvasSnapMode.grid &&
        state.snapMode != CanvasSnapMode.all) {
      return point;
    }
    final spacing = effectiveGridSpacing(state.gridPreset, state.gridSpacing);
    if (state.gridPreset == CanvasGridPreset.none || spacing <= 0) return point;
    return Offset(
      (point.dx / spacing).round() * spacing,
      (point.dy / spacing).round() * spacing,
    );
  }

  static Offset snapPointToGuides(
    Offset point, {
    required CanvasPrecisionState state,
    double threshold = 5,
  }) {
    if (state.snapMode != CanvasSnapMode.guides &&
        state.snapMode != CanvasSnapMode.all) {
      return point;
    }
    var x = point.dx;
    var y = point.dy;
    for (final guide in state.guides) {
      if ((guide.axis == CanvasGuideAxis.vertical) &&
          (guide.position - point.dx).abs() <= threshold) {
        x = guide.position;
      }
      if ((guide.axis == CanvasGuideAxis.horizontal) &&
          (guide.position - point.dy).abs() <= threshold) {
        y = guide.position;
      }
    }
    return Offset(x, y);
  }

  static Offset snapPoint(
    Offset point, {
    required CanvasPrecisionState state,
    double guideThreshold = 5,
  }) {
    final gridSnapped = snapPointToGrid(point, state: state);
    return snapPointToGuides(
      gridSnapped,
      state: state,
      threshold: guideThreshold,
    );
  }

  static List<RulerTick> rulerTicks({
    required double start,
    required double end,
    required double zoom,
    double targetPixels = 90,
  }) {
    if (!start.isFinite || !end.isFinite || !zoom.isFinite || zoom <= 0) {
      return const [];
    }
    final worldStep = targetPixels / zoom;
    final magnitude = worldStep <= 0 ? 1 : worldStep;
    final power = math.log(magnitude) / math.ln10;
    final base = math.pow(10, power.floor()).toDouble();
    final fraction = magnitude / base;
    final niceFraction = fraction <= 1
        ? 1
        : fraction <= 2
        ? 2
        : fraction <= 5
        ? 5
        : 10;
    final step = math.max(1e-9, niceFraction * base).toDouble();
    final first = ((start / step).floor() * step).toDouble();
    final result = <RulerTick>[];
    for (var position = first; position <= end; position += step) {
      final major = (position / step).round() % 5 == 0;
      result.add(
        RulerTick(
          worldPosition: position.toDouble(),
          major: major,
          label: position.roundToDouble() == position
              ? position.toInt().toString()
              : position.toStringAsFixed(1),
        ),
      );
      if (result.length > 1000) break;
    }
    return result;
  }
}
