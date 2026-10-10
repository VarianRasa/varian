import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/domain/models/drawing_payload.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/diagrams/domain/diagram_shape_catalog.dart';
import '../domain/command_palette.dart';

enum CanvasTool {
  select,
  hand,
  text,
  stickyNote,
  rectangle,
  ellipse,
  line,
  arrow,
  image,
  frame,
  diamond,
  cylinder,
  parallelogram,
  connector,
  brush,
  pen,
  component,
  comment,
  fileCard,
  model3d,
  linkCard,
  videoCard,
  audioCard,
  mapCard,
  colorSwatch,
  sketchCard,
  columnContainer,
  nestedBoard,
  tableGrid,
  todoList,
  annotate,
  drawingPaper,
  document,
  embed,
  mermaid,
  chart,
  diagramShape,
}

const double minBrushWidth = 1.0;
const double maxBrushWidth = 100.0;

class BrushConfig {
  final BrushType brushType;
  final EraserMode eraserMode;
  final Color color;
  final double strokeWidth;
  final double opacity;
  final bool smoothCurves;

  const BrushConfig({
    this.brushType = BrushType.ink,
    this.eraserMode = EraserMode.stroke,
    this.color = const Color(0xFFF97316),
    this.strokeWidth = 3.0,
    this.opacity = 1.0,
    this.smoothCurves = true,
  });

  BrushConfig copyWith({
    BrushType? brushType,
    EraserMode? eraserMode,
    Color? color,
    double? strokeWidth,
    double? opacity,
    bool? smoothCurves,
  }) {
    return BrushConfig(
      brushType: brushType ?? this.brushType,
      eraserMode: eraserMode ?? this.eraserMode,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      opacity: opacity ?? this.opacity,
      smoothCurves: smoothCurves ?? this.smoothCurves,
    );
  }
}

const _brushColorKey = 'canvas_brush_color';

final activeBrushConfigProvider =
    StateNotifierProvider<ActiveBrushConfigNotifier, BrushConfig>((ref) {
      return ActiveBrushConfigNotifier();
    });

class ActiveBrushConfigNotifier extends StateNotifier<BrushConfig> {
  late final Future<void> ready;
  Future<void> _colorWriteQueue = Future<void>.value();
  bool _colorWasSet = false;

  ActiveBrushConfigNotifier() : super(const BrushConfig()) {
    ready = _loadColor();
  }

  void setBrushType(BrushType type) => state = state.copyWith(brushType: type);
  void setEraserMode(EraserMode mode) =>
      state = state.copyWith(eraserMode: mode);
  Future<void> setColor(Color color) {
    _colorWasSet = true;
    state = state.copyWith(color: color);
    final nextWrite = _colorWriteQueue.then((_) => _persistColor(color));
    _colorWriteQueue = nextWrite.catchError((_) {});
    return nextWrite;
  }

  void setStrokeWidth(double width) {
    final nextWidth = width.isFinite
        ? width.clamp(minBrushWidth, maxBrushWidth).toDouble()
        : state.strokeWidth;
    state = state.copyWith(strokeWidth: nextWidth);
  }

  void setOpacity(double opacity) => state = state.copyWith(opacity: opacity);
  void setSmoothCurves(bool smooth) =>
      state = state.copyWith(smoothCurves: smooth);

  Future<void> _loadColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_colorWasSet) return;
      final storedColor = prefs.getInt(_brushColorKey);
      if (storedColor != null) {
        state = state.copyWith(color: Color(storedColor));
      }
    } catch (error) {
      debugPrint('[BrushConfig] Could not load brush color: $error');
    }
  }

  Future<void> _persistColor(Color color) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_brushColorKey, color.toARGB32());
    } catch (error) {
      debugPrint('[BrushConfig] Could not save brush color: $error');
    }
  }
}

final activeToolProvider =
    StateNotifierProvider<ActiveToolNotifier, CanvasTool>((ref) {
      return ActiveToolNotifier(ref);
    });

class ActiveToolNotifier extends StateNotifier<CanvasTool> {
  final Ref? _ref;

  ActiveToolNotifier([this._ref]) : super(CanvasTool.select);

  void setTool(CanvasTool tool) {
    state = tool;
    _ref?.read(canvasToolHistoryProvider.notifier).record(tool.name);
  }
}

const _canvasToolHistoryKey = 'canvas_tool_history_v1';

final canvasToolHistoryProvider =
    StateNotifierProvider<
      CanvasToolHistoryNotifier,
      List<CanvasToolHistoryEntry>
    >((ref) => CanvasToolHistoryNotifier());

class CanvasToolHistoryNotifier
    extends StateNotifier<List<CanvasToolHistoryEntry>> {
  late final Future<void> ready;
  bool _hasLocalChange = false;

  CanvasToolHistoryNotifier() : super(const []) {
    ready = _load();
  }

  void record(String toolId) {
    _hasLocalChange = true;
    final history = CanvasToolHistory(entries: state).record(toolId);
    state = history.entries;
    unawaited(_persist(history));
  }

  void clear() {
    _hasLocalChange = true;
    state = const [];
    unawaited(_persist(const CanvasToolHistory()));
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_hasLocalChange) return;
      final raw = prefs.getString(_canvasToolHistoryKey);
      if (raw == null) return;
      state = CanvasToolHistory.fromJson(raw).entries;
    } catch (_) {
      state = const [];
    }
  }

  Future<void> _persist(CanvasToolHistory history) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_canvasToolHistoryKey, history.encode());
    } catch (_) {
      return;
    }
  }
}

final activeDiagramShapeProvider = StateProvider<DiagramShapeDefinition>(
  (ref) => DiagramShapeCatalog.resolve('rectangle'),
);

final activeChartTypeProvider = StateProvider<ChartType>(
  (ref) => ChartType.line,
);
