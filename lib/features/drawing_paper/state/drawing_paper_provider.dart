import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';
import 'package:varian/features/drawing_paper/domain/models/raster_edit_operation.dart';
import 'package:varian/features/drawing_paper/domain/models/ruler_guide.dart';
import 'package:varian/features/drawing_paper/domain/models/selection_mask.dart';
import 'package:varian/features/drawing_paper/domain/models/studio_item_selection.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_renderer.dart';
import 'package:varian/features/drawing_paper/domain/services/studio_item_selection_service.dart';
import 'package:varian/features/drawing_paper/domain/services/raster_canvas_engine.dart';
import 'package:varian/features/drawing_paper/domain/services/timelapse_recorder.dart';

enum StudioTool {
  brush,
  eraser,
  bucketFill,
  lassoFill,
  smudge,
  blur,
  selection,
  itemSelection,
  transform,
  shapes,
  mangaPanel,
  speechBalloon,
  text,
  eyedropper,
  ruler,
  hand,
}

enum StudioTransformMode {
  free,
  scale,
  rotate,
  flipH,
  flipV,
  perspective,
  meshWarp,
}

bool _isLayerEditable(DrawingPaperPayload payload, DrawingLayer layer) =>
    FocusStudioItemCatalog.isLayerEditable(payload, layer);

({RasterSurface surface, double scale}) _buildPreviewRaster(
  DrawingPaperPayload payload,
) => DrawingPaperRenderer.buildRasterPreview(payload, maxDimension: null);

class DrawingStudioState {
  static const Object _unset = Object();

  final DrawingPaperPayload payload;
  final RasterSurface? rasterSurface;
  final double rasterPreviewScale;
  final StudioTool activeTool;
  final StudioBrushCategory activeBrush;
  final Color primaryColor;
  final Color secondaryColor;
  final double brushSize;
  final double brushOpacity;
  final double stabilizer;
  final bool enableTaper;
  final double viewZoom;
  final double viewRotation; // radians
  final Offset viewPan;
  final int activeLayerIndex;
  final SelectionMask? selection;
  final List<FocusStudioItemReference> selectedItems;
  final List<FocusStudioClipboardItem> itemClipboard;
  final List<RulerGuide> rulers;
  final bool isRecordingTimelapse;
  final int undoCount;
  final int redoCount;
  final SelectionToolType activeSelectionTool;
  final SelectionOperation activeSelectionOp;
  final List<DrawingStroke> strokeClipboard;
  final List<VectorShapeObject> shapeClipboard;
  final List<TextObjectData> textClipboard;
  final ShapeKind activeShapeKind;
  final RulerType activeRulerType;
  final SpeechBalloonType activeBalloonType;
  final ScreenToneType activeScreenTone;
  final double screenToneFrequency;
  final double screenToneAngle;
  final StudioTransformMode transformMode;
  final Rect? transformBounds;
  final double transformRotation;
  final Color shapeFillColor;
  final Color shapeStrokeColor;
  final double shapeStrokeWidth;
  final String activeFontFamily;
  final double activeFontSize;
  final bool activeTextVertical;
  final Color activeTextOutlineColor;
  final double activeTextOutlineWidth;

  const DrawingStudioState({
    required this.payload,
    this.rasterSurface,
    this.rasterPreviewScale = 1.0,
    this.activeTool = StudioTool.brush,
    this.activeBrush = StudioBrushCategory.gPen,
    this.primaryColor = const Color(0xFF000000),
    this.secondaryColor = const Color(0xFFFFFFFF),
    this.brushSize = 6.0,
    this.brushOpacity = 1.0,
    this.stabilizer = 0.4,
    this.enableTaper = true,
    this.viewZoom = 1.0,
    this.viewRotation = 0.0,
    this.viewPan = Offset.zero,
    this.activeLayerIndex = 0,
    this.selection,
    this.selectedItems = const [],
    this.itemClipboard = const [],
    this.rulers = const [],
    this.isRecordingTimelapse = true,
    this.undoCount = 0,
    this.redoCount = 0,
    this.activeSelectionTool = SelectionToolType.lasso,
    this.activeSelectionOp = SelectionOperation.replace,
    this.strokeClipboard = const [],
    this.shapeClipboard = const [],
    this.textClipboard = const [],
    this.activeShapeKind = ShapeKind.rectangle,
    this.activeRulerType = RulerType.straight,
    this.activeBalloonType = SpeechBalloonType.speechOval,
    this.activeScreenTone = ScreenToneType.none,
    this.screenToneFrequency = 24.0,
    this.screenToneAngle = 45.0,
    this.transformMode = StudioTransformMode.free,
    this.transformBounds,
    this.transformRotation = 0.0,
    this.shapeFillColor = const Color(0x00000000),
    this.shapeStrokeColor = const Color(0xFF000000),
    this.shapeStrokeWidth = 3.0,
    this.activeFontFamily = 'Roboto',
    this.activeFontSize = 24.0,
    this.activeTextVertical = false,
    this.activeTextOutlineColor = Colors.transparent,
    this.activeTextOutlineWidth = 0.0,
  });

  DrawingLayer? get activeLayer {
    if (payload.layers.isEmpty) return null;
    final idx = activeLayerIndex.clamp(0, payload.layers.length - 1);
    return payload.layers[idx];
  }

  DrawingStudioState copyWith({
    DrawingPaperPayload? payload,
    RasterSurface? rasterSurface,
    double? rasterPreviewScale,
    StudioTool? activeTool,
    StudioBrushCategory? activeBrush,
    Color? primaryColor,
    Color? secondaryColor,
    double? brushSize,
    double? brushOpacity,
    double? stabilizer,
    bool? enableTaper,
    double? viewZoom,
    double? viewRotation,
    Offset? viewPan,
    int? activeLayerIndex,
    Object? selection = _unset,
    List<FocusStudioItemReference>? selectedItems,
    List<FocusStudioClipboardItem>? itemClipboard,
    List<RulerGuide>? rulers,
    bool? isRecordingTimelapse,
    int? undoCount,
    int? redoCount,
    SelectionToolType? activeSelectionTool,
    SelectionOperation? activeSelectionOp,
    List<DrawingStroke>? strokeClipboard,
    List<VectorShapeObject>? shapeClipboard,
    List<TextObjectData>? textClipboard,
    ShapeKind? activeShapeKind,
    RulerType? activeRulerType,
    SpeechBalloonType? activeBalloonType,
    ScreenToneType? activeScreenTone,
    double? screenToneFrequency,
    double? screenToneAngle,
    StudioTransformMode? transformMode,
    Object? transformBounds = _unset,
    double? transformRotation,
    Color? shapeFillColor,
    Color? shapeStrokeColor,
    double? shapeStrokeWidth,
    String? activeFontFamily,
    double? activeFontSize,
    bool? activeTextVertical,
    Color? activeTextOutlineColor,
    double? activeTextOutlineWidth,
  }) {
    return DrawingStudioState(
      payload: payload ?? this.payload,
      rasterSurface: rasterSurface ?? this.rasterSurface,
      rasterPreviewScale: rasterPreviewScale ?? this.rasterPreviewScale,
      activeTool: activeTool ?? this.activeTool,
      activeBrush: activeBrush ?? this.activeBrush,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      brushSize: brushSize ?? this.brushSize,
      brushOpacity: brushOpacity ?? this.brushOpacity,
      stabilizer: stabilizer ?? this.stabilizer,
      enableTaper: enableTaper ?? this.enableTaper,
      viewZoom: viewZoom ?? this.viewZoom,
      viewRotation: viewRotation ?? this.viewRotation,
      viewPan: viewPan ?? this.viewPan,
      activeLayerIndex: activeLayerIndex ?? this.activeLayerIndex,
      selection: selection == _unset
          ? this.selection
          : selection as SelectionMask?,
      selectedItems: selectedItems ?? this.selectedItems,
      itemClipboard: itemClipboard ?? this.itemClipboard,
      rulers: rulers ?? this.rulers,
      isRecordingTimelapse: isRecordingTimelapse ?? this.isRecordingTimelapse,
      undoCount: undoCount ?? this.undoCount,
      redoCount: redoCount ?? this.redoCount,
      activeSelectionTool: activeSelectionTool ?? this.activeSelectionTool,
      activeSelectionOp: activeSelectionOp ?? this.activeSelectionOp,
      strokeClipboard: strokeClipboard ?? this.strokeClipboard,
      shapeClipboard: shapeClipboard ?? this.shapeClipboard,
      textClipboard: textClipboard ?? this.textClipboard,
      activeShapeKind: activeShapeKind ?? this.activeShapeKind,
      activeRulerType: activeRulerType ?? this.activeRulerType,
      activeBalloonType: activeBalloonType ?? this.activeBalloonType,
      activeScreenTone: activeScreenTone ?? this.activeScreenTone,
      screenToneFrequency: screenToneFrequency ?? this.screenToneFrequency,
      screenToneAngle: screenToneAngle ?? this.screenToneAngle,
      transformMode: transformMode ?? this.transformMode,
      transformBounds: transformBounds == _unset
          ? this.transformBounds
          : transformBounds as Rect?,
      transformRotation: transformRotation ?? this.transformRotation,
      shapeFillColor: shapeFillColor ?? this.shapeFillColor,
      shapeStrokeColor: shapeStrokeColor ?? this.shapeStrokeColor,
      shapeStrokeWidth: shapeStrokeWidth ?? this.shapeStrokeWidth,
      activeFontFamily: activeFontFamily ?? this.activeFontFamily,
      activeFontSize: activeFontSize ?? this.activeFontSize,
      activeTextVertical: activeTextVertical ?? this.activeTextVertical,
      activeTextOutlineColor:
          activeTextOutlineColor ?? this.activeTextOutlineColor,
      activeTextOutlineWidth:
          activeTextOutlineWidth ?? this.activeTextOutlineWidth,
    );
  }
}

class DrawingStudioNotifier extends StateNotifier<DrawingStudioState> {
  final List<DrawingPaperPayload> _undoStack = [];
  final List<DrawingPaperPayload> _redoStack = [];
  final List<RasterSurface?> _undoRasterStack = [];
  final List<RasterSurface?> _redoRasterStack = [];
  final TimelapseRecorder timelapseRecorder = TimelapseRecorder();
  DrawingPaperPayload? _itemGestureInitialPayload;
  RasterSurface? _itemGestureInitialRaster;
  bool _itemGestureChanged = false;
  bool _itemGestureAffectsRaster = false;
  int _itemIdSeed = 0;

  DrawingStudioNotifier(DrawingPaperPayload initialPayload)
    : super(
        (() {
          final pagePayload = initialPayload.copyWith(studioPages: const []);
          final preview = _buildPreviewRaster(pagePayload);
          return DrawingStudioState(
            payload: pagePayload,
            rasterSurface: preview.surface,
            rasterPreviewScale: preview.scale,
            activeLayerIndex: pagePayload.activeLayerIndex,
            rulers: pagePayload.rulers,
            selection: pagePayload.activeSelection,
            selectedItems: const [],
            stabilizer: pagePayload.stabilizerStrength,
            enableTaper: pagePayload.enableTaper,
          );
        })(),
      ) {
    timelapseRecorder.start();
    timelapseRecorder.captureStep(
      action: 'Initial Open',
      layers: state.payload.layers,
    );
  }

  void replacePayload(DrawingPaperPayload nextPayload) {
    final pagePayload = nextPayload.copyWith(studioPages: const []);
    final preview = _buildPreviewRaster(pagePayload);
    _undoStack.clear();
    _redoStack.clear();
    _undoRasterStack.clear();
    _redoRasterStack.clear();
    state = state.copyWith(
      payload: pagePayload,
      rasterSurface: preview.surface,
      rasterPreviewScale: preview.scale,
      activeLayerIndex: _normalizeLayerIndex(
        pagePayload,
        pagePayload.activeLayerIndex,
      ),
      selection: pagePayload.activeSelection,
      selectedItems: const [],
      itemClipboard: const [],
      rulers: pagePayload.rulers,
      stabilizer: pagePayload.stabilizerStrength,
      enableTaper: pagePayload.enableTaper,
      undoCount: 0,
      redoCount: 0,
    );
    timelapseRecorder.captureStep(
      action: 'Switch Focus Studio Page',
      layers: state.payload.layers,
    );
  }

  void _recordHistory(String action) {
    _undoStack.add(state.payload.clone());
    _undoRasterStack.add(state.rasterSurface?.clone());
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
      _undoRasterStack.removeAt(0);
    }
    _redoStack.clear();
    _redoRasterStack.clear();

    timelapseRecorder.captureStep(action: action, layers: state.payload.layers);

    state = state.copyWith(
      undoCount: _undoStack.length,
      redoCount: _redoStack.length,
    );
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final prev = _undoStack.removeLast();
    final prevRaster = _undoRasterStack.isNotEmpty
        ? _undoRasterStack.removeLast()
        : null;
    _redoStack.add(state.payload.clone());
    _redoRasterStack.add(state.rasterSurface?.clone());
    state = state.copyWith(
      payload: prev,
      rasterSurface: prevRaster,
      activeLayerIndex: _normalizeLayerIndex(prev, prev.activeLayerIndex),
      selectedItems: _validItemSelection(prev, state.selectedItems),
      undoCount: _undoStack.length,
      redoCount: _redoStack.length,
    );
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    final nextRaster = _redoRasterStack.isNotEmpty
        ? _redoRasterStack.removeLast()
        : null;
    _undoStack.add(state.payload.clone());
    _undoRasterStack.add(state.rasterSurface?.clone());
    state = state.copyWith(
      payload: next,
      rasterSurface: nextRaster,
      activeLayerIndex: _normalizeLayerIndex(next, next.activeLayerIndex),
      selectedItems: _validItemSelection(next, state.selectedItems),
      undoCount: _undoStack.length,
      redoCount: _redoStack.length,
    );
  }

  int _normalizeLayerIndex(DrawingPaperPayload payload, int index) {
    if (payload.layers.isEmpty) return 0;
    return index.clamp(0, payload.layers.length - 1).toInt();
  }

  List<FocusStudioItemReference> _validItemSelection(
    DrawingPaperPayload payload,
    Iterable<FocusStudioItemReference> references,
  ) {
    final allowed = FocusStudioItemCatalog.editable(
      payload,
    ).map((entry) => entry.reference).toSet();
    return references.where(allowed.contains).toList();
  }

  // --- Tools & Colors ---
  void setTool(StudioTool tool) {
    state = state.copyWith(
      activeTool: tool,
      selectedItems: tool == StudioTool.itemSelection
          ? state.selectedItems
          : const [],
    );
  }

  void setPrimaryColor(Color color) {
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final history = List<String>.from(state.payload.colorHistory);
    if (!history.contains(hex)) {
      history.insert(0, hex);
      if (history.length > 16) history.removeLast();
    }
    state = state.copyWith(
      primaryColor: color,
      payload: state.payload.copyWith(colorHistory: history),
    );
  }

  void setSecondaryColor(Color color) {
    state = state.copyWith(secondaryColor: color);
  }

  void setBrush(StudioBrushCategory brush) {
    final tool = switch (brush) {
      StudioBrushCategory.bucketFill => StudioTool.bucketFill,
      StudioBrushCategory.lassoFill => StudioTool.lassoFill,
      StudioBrushCategory.smudge => StudioTool.smudge,
      StudioBrushCategory.blurTool => StudioTool.blur,
      StudioBrushCategory.eraserHard ||
      StudioBrushCategory.eraserSoft ||
      StudioBrushCategory.eraserVector => StudioTool.eraser,
      _ => StudioTool.brush,
    };
    state = state.copyWith(
      activeBrush: brush,
      activeTool: tool,
      selectedItems: const [],
    );
  }

  void swapColors() => state = state.copyWith(
    primaryColor: state.secondaryColor,
    secondaryColor: state.primaryColor,
  );

  void setShapeKind(ShapeKind kind) => state = state.copyWith(
    activeShapeKind: kind,
    activeTool: StudioTool.shapes,
  );

  void setShapeFillColor(Color color) =>
      state = state.copyWith(shapeFillColor: color);

  void setShapeStrokeColor(Color color) =>
      state = state.copyWith(shapeStrokeColor: color);

  void setShapeStrokeWidth(double width) =>
      state = state.copyWith(shapeStrokeWidth: width.clamp(0.0, 80.0));

  void setRulerType(RulerType type) => state = state.copyWith(
    activeRulerType: type,
    activeTool: StudioTool.ruler,
  );

  void setBalloonType(SpeechBalloonType type) => state = state.copyWith(
    activeBalloonType: type,
    activeTool: StudioTool.speechBalloon,
  );

  void setSelectionTool(SelectionToolType tool) =>
      state = state.copyWith(activeSelectionTool: tool);
  void setSelectionOperation(SelectionOperation op) =>
      state = state.copyWith(activeSelectionOp: op);

  void invertSelection() {
    if (state.selection == null) return;
    _recordHistory('Invert Selection');
    final inv = state.selection!.copyWith(inverted: !state.selection!.inverted);
    setSelection(inv);
  }

  void copySelection() {
    if (state.activeTool == StudioTool.itemSelection) {
      copySelectedItems();
      return;
    }
    final layer = state.activeLayer;
    if (layer == null) return;
    state = state.copyWith(
      strokeClipboard: List.of(layer.strokes),
      shapeClipboard: List.of(layer.shapes),
      textClipboard: List.of(layer.texts),
    );
  }

  void cutSelection() {
    if (state.activeTool == StudioTool.itemSelection) {
      cutSelectedItems();
      return;
    }
    copySelection();
    clearActiveLayer();
  }

  void pasteClipboard() {
    if (state.activeTool == StudioTool.itemSelection) {
      pasteSelectedItems();
      return;
    }
    if (state.strokeClipboard.isEmpty &&
        state.shapeClipboard.isEmpty &&
        state.textClipboard.isEmpty) {
      return;
    }
    _recordHistory('Paste Selection');

    final layer = state.activeLayer;
    if (layer == null) return;

    final newStrokes = List<DrawingStroke>.from(layer.strokes)
      ..addAll(
        state.strokeClipboard.map(
          (s) =>
              s.copyWith(id: 'stroke_${DateTime.now().microsecondsSinceEpoch}'),
        ),
      );
    final newShapes = List<VectorShapeObject>.from(layer.shapes)
      ..addAll(
        state.shapeClipboard.map(
          (s) =>
              s.copyWith(id: 'shape_${DateTime.now().microsecondsSinceEpoch}'),
        ),
      );
    final newTexts = List<TextObjectData>.from(layer.texts)
      ..addAll(
        state.textClipboard.map(
          (t) =>
              t.copyWith(id: 'text_${DateTime.now().microsecondsSinceEpoch}'),
        ),
      );

    updateActiveLayer(
      (l) =>
          l.copyWith(strokes: newStrokes, shapes: newShapes, texts: newTexts),
    );
  }

  void addShapeToActiveLayer(VectorShapeObject shape) {
    if (state.payload.layers.isEmpty) return;
    final idx = _normalizeLayerIndex(state.payload, state.activeLayerIndex);
    final target = state.payload.layers[idx];
    if (target.type == LayerType.folder ||
        !_isLayerEditable(state.payload, target)) {
      return;
    }
    _recordHistory('Add Vector Shape');

    final layers = List<DrawingLayer>.from(state.payload.layers);
    layers[idx] = target.copyWith(
      shapes: List<VectorShapeObject>.from(target.shapes)..add(shape),
    );
    state = state.copyWith(payload: state.payload.copyWith(layers: layers));
  }

  void addTextToActiveLayer(TextObjectData textObj) {
    if (state.payload.layers.isEmpty) return;
    final idx = _normalizeLayerIndex(state.payload, state.activeLayerIndex);
    final target = state.payload.layers[idx];
    if (target.type == LayerType.folder ||
        !_isLayerEditable(state.payload, target)) {
      return;
    }
    _recordHistory('Add Text');

    final layers = List<DrawingLayer>.from(state.payload.layers);
    layers[idx] = target.copyWith(
      texts: List<TextObjectData>.from(target.texts)..add(textObj),
    );
    state = state.copyWith(payload: state.payload.copyWith(layers: layers));
  }

  void updateTextObject(TextObjectData updated) {
    final layers = List<DrawingLayer>.from(state.payload.layers);
    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final layer = layers[layerIndex];
      final textIndex = layer.texts.indexWhere((text) => text.id == updated.id);
      if (textIndex == -1 ||
          layer.locked ||
          !layer.visible ||
          layer.type == LayerType.folder) {
        continue;
      }
      _recordHistory('Edit Text');
      final texts = List<TextObjectData>.from(layer.texts);
      texts[textIndex] = updated;
      layers[layerIndex] = layer.copyWith(texts: texts);
      state = state.copyWith(payload: state.payload.copyWith(layers: layers));
      return;
    }
  }

  void duplicateActiveLayer() => duplicateLayer(state.activeLayerIndex);

  void addFolderLayer({String? name}) {
    addLayer(name: name ?? 'Folder Group', type: LayerType.folder);
  }

  void toggleGrid() => state = state.copyWith(
    payload: state.payload.copyWith(showGrid: !state.payload.showGrid),
  );
  void togglePixelGrid() => state = state.copyWith(
    payload: state.payload.copyWith(
      showPixelGrid: !state.payload.showPixelGrid,
    ),
  );
  void toggleMangaBleed() => state = state.copyWith(
    payload: state.payload.copyWith(
      showMangaBleed: !state.payload.showMangaBleed,
    ),
  );
  void updateReferenceConfig(ReferenceImageConfig config) {
    state = state.copyWith(
      payload: state.payload.copyWith(referenceConfig: config),
    );
  }

  void setBrushSize(double size) =>
      state = state.copyWith(brushSize: size.clamp(1.0, 300.0));
  void setBrushOpacity(double opacity) =>
      state = state.copyWith(brushOpacity: opacity.clamp(0.01, 1.0));
  void setStabilizer(double val) =>
      state = state.copyWith(stabilizer: val.clamp(0.0, 1.0));
  void setEnableTaper(bool val) => state = state.copyWith(enableTaper: val);

  // --- View Manipulation ---
  void panBy(double dx, double dy, {Size? viewportSize, Size? workspaceSize}) {
    double newPanX = state.viewPan.dx + dx;
    double newPanY = state.viewPan.dy + dy;

    if (viewportSize != null && workspaceSize != null) {
      final scaledW = workspaceSize.width * state.viewZoom;
      final scaledH = workspaceSize.height * state.viewZoom;
      final maxPanX = (viewportSize.width / 2) + (scaledW / 2) - 60;
      final maxPanY = (viewportSize.height / 2) + (scaledH / 2) - 60;

      newPanX = newPanX.clamp(-maxPanX, maxPanX);
      newPanY = newPanY.clamp(-maxPanY, maxPanY);
    }

    state = state.copyWith(viewPan: Offset(newPanX, newPanY));
  }

  void zoomBy(
    double delta,
    Offset focalPoint,
    Size viewportSize,
    Size workspaceSize,
  ) {
    final oldZoom = state.viewZoom;
    final newZoom = (oldZoom * delta).clamp(0.15, 10.0);
    if (oldZoom == newZoom) return;

    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final focusFromCenter = focalPoint - center;
    final newPan =
        focusFromCenter -
        (focusFromCenter - state.viewPan) * (newZoom / oldZoom);

    final scaledW = workspaceSize.width * newZoom;
    final scaledH = workspaceSize.height * newZoom;
    final maxPanX = (viewportSize.width / 2) + (scaledW / 2) - 60;
    final maxPanY = (viewportSize.height / 2) + (scaledH / 2) - 60;

    state = state.copyWith(
      viewZoom: newZoom,
      viewPan: Offset(
        newPan.dx.clamp(-maxPanX, maxPanX),
        newPan.dy.clamp(-maxPanY, maxPanY),
      ),
    );
  }

  void setViewZoom(double zoom) =>
      state = state.copyWith(viewZoom: zoom.clamp(0.15, 10.0));
  void setViewRotation(double rot) => state = state.copyWith(viewRotation: rot);
  void setViewPan(Offset pan) => state = state.copyWith(viewPan: pan);
  void resetView({Size? viewportSize, Size? workspaceSize, Size? paperSize}) {
    final fitSize = workspaceSize ?? paperSize;
    double initialZoom = 1.0;
    if (viewportSize != null && fitSize != null) {
      final padW = viewportSize.width - 80;
      final padH = viewportSize.height - 80;
      final scaleX = padW / fitSize.width;
      final scaleY = padH / fitSize.height;
      initialZoom = (scaleX < scaleY ? scaleX : scaleY).clamp(0.15, 2.0);
    }
    state = state.copyWith(
      viewZoom: initialZoom,
      viewRotation: 0.0,
      viewPan: Offset.zero,
    );
  }

  // --- Selection & Transform Engine ---
  void applyTransformToActiveLayer({
    Offset? translation,
    double scale = 1.0,
    double rotation = 0.0,
    bool flipH = false,
    bool flipV = false,
    Offset? pivot,
  }) {
    final layer = state.activeLayer;
    if (layer == null) return;
    _recordHistory('Transform Layer');

    final bounds = _layerBounds(layer);
    if (bounds == null) return;

    final center = pivot ?? bounds.center;
    Offset local(Offset p) {
      var pt = p;
      if (translation != null) pt = pt + translation;
      // Scale relative to center
      pt = Offset(
        center.dx + (pt.dx - center.dx) * scale,
        center.dy + (pt.dy - center.dy) * scale,
      );
      // Flip
      if (flipH) pt = Offset(2 * center.dx - pt.dx, pt.dy);
      if (flipV) pt = Offset(pt.dx, 2 * center.dy - pt.dy);
      // Rotate
      if (rotation != 0.0) {
        final cosA = cos(rotation);
        final sinA = sin(rotation);
        final dx = pt.dx - center.dx;
        final dy = pt.dy - center.dy;
        pt = Offset(
          center.dx + dx * cosA - dy * sinA,
          center.dy + dx * sinA + dy * cosA,
        );
      }
      return pt;
    }

    final newStrokes = layer.strokes.map((s) {
      return s.copyWith(
        points: s.points.map((pt) {
          final np = local(pt.offset);
          return DrawingStrokePoint(
            x: np.dx,
            y: np.dy,
            pressure: pt.pressure,
            tilt: pt.tilt,
            timestamp: pt.timestamp,
          );
        }).toList(),
      );
    }).toList();

    final newShapes = layer.shapes.map((s) {
      return s.copyWith(
        points: s.points.map(local).toList(),
        rotation: s.rotation + (rotation != 0.0 ? rotation : 0.0),
      );
    }).toList();

    final newTexts = layer.texts.map((t) {
      final np = local(Offset(t.x, t.y));
      return t.copyWith(
        x: np.dx,
        y: np.dy,
        width: t.width * (flipH ? -1 : 1).abs(),
      );
    }).toList();

    final layers = List<DrawingLayer>.from(state.payload.layers);
    layers[state.activeLayerIndex] = layer.copyWith(
      strokes: newStrokes,
      shapes: newShapes,
      texts: newTexts,
    );
    state = state.copyWith(payload: state.payload.copyWith(layers: layers));
  }

  Rect? get activeLayerBounds {
    final layer = state.activeLayer;
    return layer == null ? null : _layerBounds(layer);
  }

  Rect? _layerBounds(DrawingLayer layer) {
    Rect? result;
    void expandRect(Rect? r) {
      if (r == null) return;
      if (result == null) {
        result = r;
      } else {
        result = result!.expandToInclude(r);
      }
    }

    for (final s in layer.strokes) {
      if (s.points.isEmpty) continue;
      expandRect(
        DrawingStroke.boundsOf(s.points.map((p) => p.offset).toList()),
      );
    }
    for (final s in layer.shapes) {
      expandRect(s.bounds);
    }
    for (final t in layer.texts) {
      expandRect(
        Rect.fromLTWH(t.x - 4, t.y - t.fontSize, t.width + 8, t.fontSize * 2),
      );
    }
    return result;
  }

  // --- Stroke & Layer Editing ---
  DrawingStroke _snapStrokeToRuler(DrawingStroke stroke) {
    final ruler = state.rulers.firstWhere(
      (ruler) => ruler.active && ruler.visible,
      orElse: () =>
          const RulerGuide(id: '', type: RulerType.straight, active: false),
    );
    if (!ruler.active || stroke.points.isEmpty) return stroke;

    Offset snap(Offset point) {
      switch (ruler.type) {
        case RulerType.straight:
          final vector = ruler.target - ruler.origin;
          final lengthSquared = vector.distanceSquared;
          if (lengthSquared == 0) return ruler.origin;
          final t =
              ((point - ruler.origin).dx * vector.dx +
                  (point - ruler.origin).dy * vector.dy) /
              lengthSquared;
          final clamped = t.clamp(0.0, 1.0).toDouble();
          return ruler.origin + vector * clamped;
        case RulerType.circular:
          final delta = point - ruler.origin;
          if (delta.distance == 0) {
            return ruler.origin + Offset(ruler.radius, 0);
          }
          return ruler.origin + delta / delta.distance * ruler.radius;
        case RulerType.radialFocus:
        case RulerType.symmetryMirror:
        case RulerType.perspective1Point:
        case RulerType.perspective2Point:
        case RulerType.perspective3Point:
          return point;
      }
    }

    return stroke.copyWith(
      points: stroke.points.map((point) {
        final snapped = snap(point.offset);
        return DrawingStrokePoint(
          x: snapped.dx,
          y: snapped.dy,
          pressure: point.pressure,
          tilt: point.tilt,
          timestamp: point.timestamp,
        );
      }).toList(),
    );
  }

  void addStrokeToActiveLayer(DrawingStroke stroke) {
    if (state.payload.layers.isEmpty) return;
    final idx = _normalizeLayerIndex(state.payload, state.activeLayerIndex);
    final target = state.payload.layers[idx];
    if (target.type == LayerType.folder ||
        !_isLayerEditable(state.payload, target)) {
      return;
    }
    final committedStroke = _snapStrokeToRuler(stroke);

    final raster = state.rasterSurface?.clone();
    if (raster != null) {
      RasterCanvasEngine(raster).drawStroke(
        points: committedStroke.points
            .map((point) => point.offset * state.rasterPreviewScale)
            .toList(),
        pressures: committedStroke.points
            .map((point) => point.pressure)
            .toList(),
        color: committedStroke.color,
        size: committedStroke.size * state.rasterPreviewScale,
        opacity: committedStroke.opacity * target.opacity,
        eraser: committedStroke.isEraser,
        soft:
            committedStroke.brush == StudioBrushCategory.airbrush ||
            committedStroke.brush == StudioBrushCategory.watercolor ||
            committedStroke.brush == StudioBrushCategory.eraserSoft,
        brush: committedStroke.brush,
        selection: state.selection,
      );
    }
    _recordHistory('Draw Stroke');

    final layers = List<DrawingLayer>.from(state.payload.layers);
    layers[idx] = target.copyWith(
      strokes: List<DrawingStroke>.from(target.strokes)..add(committedStroke),
    );
    state = state.copyWith(
      payload: state.payload.copyWith(
        layers: layers,
        rasterRevision: state.payload.rasterRevision + 1,
      ),
      rasterSurface: raster,
    );
  }

  int applyRasterOperation(RasterEditOperation operation) {
    if (state.payload.layers.isEmpty) return 0;
    final layer = state.activeLayer;
    if (layer == null ||
        layer.type == LayerType.folder ||
        !_isLayerEditable(state.payload, layer)) {
      return 0;
    }
    final raster = state.rasterSurface?.clone();
    if (raster == null) return 0;

    final engine = RasterCanvasEngine(raster);
    final scaledSelection = _scaleSelection(
      operation.selection,
      state.rasterPreviewScale,
    );
    final changed = switch (operation.kind) {
      RasterEditKind.bucketFill => engine.bucketFill(
        seedPoint: operation.seedPoint * state.rasterPreviewScale,
        color: operation.color,
        tolerance: operation.tolerance,
        selection: scaledSelection,
      ),
      RasterEditKind.smudge => engine.smudge(
        points: operation.points
            .map((point) => point * state.rasterPreviewScale)
            .toList(),
        radius: operation.radius * state.rasterPreviewScale,
        strength: operation.strength,
        selection: scaledSelection,
      ),
      RasterEditKind.blur => engine.blur(
        points: operation.points
            .map((point) => point * state.rasterPreviewScale)
            .toList(),
        radius: operation.radius * state.rasterPreviewScale,
        strength: operation.strength,
        selection: scaledSelection,
      ),
      RasterEditKind.transform => engine.transform(
        bounds: _scaleRect(operation.bounds!, state.rasterPreviewScale),
        translation: operation.translation * state.rasterPreviewScale,
        scale: operation.scale,
        rotation: operation.rotation,
        flipH: operation.flipH,
        flipV: operation.flipV,
        selection: scaledSelection,
      ),
    };
    if (changed == 0) return 0;

    _recordHistory('Raster ${operation.kind.name}');
    state = state.copyWith(
      payload: state.payload.copyWith(
        rasterRevision: state.payload.rasterRevision + 1,
        rasterOperations: [...state.payload.rasterOperations, operation],
      ),
      rasterSurface: raster,
    );
    return changed;
  }

  SelectionMask? _scaleSelection(SelectionMask? selection, double scale) {
    if (selection == null) return null;
    return selection.copyWith(
      outlinePoints: selection.outlinePoints
          .map((point) => point * scale)
          .toList(),
      boundingBox: selection.boundingBox == null
          ? null
          : _scaleRect(selection.boundingBox!, scale),
    );
  }

  Rect _scaleRect(Rect rect, double scale) => Rect.fromLTWH(
    rect.left * scale,
    rect.top * scale,
    rect.width * scale,
    rect.height * scale,
  );

  void _rebuildRasterPreview() {
    final preview = _buildPreviewRaster(state.payload);
    state = state.copyWith(
      rasterSurface: preview.surface,
      rasterPreviewScale: preview.scale,
    );
  }

  void addLayer({String? name, LayerType type = LayerType.raster}) {
    _recordHistory('Add Layer');
    final layers = List<DrawingLayer>.from(state.payload.layers);
    final active = state.activeLayer;
    final parentFolderId = active?.type == LayerType.folder
        ? active?.id
        : active?.parentFolderId;
    final newId = 'layer_${DateTime.now().microsecondsSinceEpoch}';
    final newLayer = DrawingLayer(
      id: newId,
      name: name ?? 'Layer ${layers.length + 1}',
      type: type,
      parentFolderId: parentFolderId,
    );
    layers.insert(0, newLayer);
    state = state.copyWith(
      payload: state.payload.copyWith(layers: layers),
      activeLayerIndex: 0,
    );
    _rebuildRasterPreview();
  }

  void removeLayer(int index) {
    if (state.payload.layers.length <= 1) return;
    _recordHistory('Delete Layer');
    final layers = List<DrawingLayer>.from(state.payload.layers)
      ..removeAt(index);
    final nextIdx = index.clamp(0, layers.length - 1);
    state = state.copyWith(
      payload: state.payload.copyWith(layers: layers),
      activeLayerIndex: nextIdx,
    );
    _rebuildRasterPreview();
  }

  void reorderLayers(int oldIndex, int newIndex) {
    _recordHistory('Reorder Layers');
    final layers = List<DrawingLayer>.from(state.payload.layers);
    final item = layers.removeAt(oldIndex);
    layers.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    state = state.copyWith(payload: state.payload.copyWith(layers: layers));
    _rebuildRasterPreview();
  }

  void setActiveLayerIndex(int index) {
    state = state.copyWith(
      activeLayerIndex: index.clamp(0, state.payload.layers.length - 1),
    );
  }

  void updateLayerAt(int index, DrawingLayer Function(DrawingLayer) updater) {
    if (index < 0 || index >= state.payload.layers.length) return;
    _recordHistory('Update Layer');
    final layers = List<DrawingLayer>.from(state.payload.layers);
    layers[index] = updater(layers[index]);
    state = state.copyWith(payload: state.payload.copyWith(layers: layers));
    _rebuildRasterPreview();
  }

  void updateActiveLayer(DrawingLayer Function(DrawingLayer) updater) {
    updateLayerAt(state.activeLayerIndex, updater);
  }

  void duplicateLayer(int index) {
    if (index < 0 || index >= state.payload.layers.length) return;
    _recordHistory('Duplicate Layer');
    final source = state.payload.layers[index].clone();
    final duplicate = source.copyWith(
      id: 'layer_${DateTime.now().microsecondsSinceEpoch}',
      name: '${source.name} Copy',
    );
    final layers = List<DrawingLayer>.from(state.payload.layers)
      ..insert(index, duplicate);
    state = state.copyWith(
      payload: state.payload.copyWith(layers: layers),
      activeLayerIndex: index,
    );
    _rebuildRasterPreview();
  }

  void clearLayerAt(int index) {
    if (index < 0 || index >= state.payload.layers.length) return;
    _recordHistory('Clear Layer');
    final layers = List<DrawingLayer>.from(state.payload.layers);
    layers[index] = layers[index].copyWith(strokes: [], shapes: [], texts: []);
    state = state.copyWith(
      payload: state.payload.copyWith(
        layers: layers,
        rasterRevision: state.payload.rasterRevision + 1,
        rasterOperations: const [],
      ),
    );
    _rebuildRasterPreview();
  }

  void mergeLayerDown(int index) {
    if (index >= state.payload.layers.length - 1) return;
    _recordHistory('Merge Layer Down');
    final layers = List<DrawingLayer>.from(state.payload.layers);
    final upper = layers[index];
    final lower = layers[index + 1];

    final mergedStrokes = List<DrawingStroke>.from(lower.strokes)
      ..addAll(upper.strokes);
    final mergedShapes = List<VectorShapeObject>.from(lower.shapes)
      ..addAll(upper.shapes);
    final mergedTexts = List<TextObjectData>.from(lower.texts)
      ..addAll(upper.texts);
    layers[index + 1] = lower.copyWith(
      strokes: mergedStrokes,
      shapes: mergedShapes,
      texts: mergedTexts,
    );
    layers.removeAt(index);

    state = state.copyWith(
      payload: state.payload.copyWith(layers: layers),
      activeLayerIndex: index.clamp(0, layers.length - 1),
    );
    _rebuildRasterPreview();
  }

  void clearActiveLayer() => clearLayerAt(state.activeLayerIndex);

  // --- Manga & Comic Panels ---
  void setMangaStructure(MangaStructure structure) {
    _recordHistory('Update Manga Layout');
    state = state.copyWith(
      payload: state.payload.copyWith(mangaStructure: structure),
    );
  }

  void addMangaPanel(MangaPanelCut panel) {
    _recordHistory('Add Manga Panel');
    final struct = state.payload.mangaStructure ?? const MangaStructure();
    final updated = struct.copyWith(panels: List.of(struct.panels)..add(panel));
    state = state.copyWith(
      payload: state.payload.copyWith(mangaStructure: updated),
    );
  }

  void addSpeechBalloon(SpeechBalloon balloon) {
    _recordHistory('Add Speech Balloon');
    final struct = state.payload.mangaStructure ?? const MangaStructure();
    final updated = struct.copyWith(
      balloons: List.of(struct.balloons)..add(balloon),
    );
    state = state.copyWith(
      payload: state.payload.copyWith(mangaStructure: updated),
    );
  }

  void updateSpeechBalloon(SpeechBalloon updatedBalloon) {
    final structure = state.payload.mangaStructure;
    if (structure == null) return;
    final index = structure.balloons.indexWhere(
      (balloon) => balloon.id == updatedBalloon.id,
    );
    if (index == -1) return;
    _recordHistory('Edit Speech Balloon');
    final balloons = List<SpeechBalloon>.from(structure.balloons);
    balloons[index] = updatedBalloon;
    state = state.copyWith(
      payload: state.payload.copyWith(
        mangaStructure: structure.copyWith(balloons: balloons),
      ),
    );
  }

  // --- Item selection ---
  List<FocusStudioItemEntry> get selectedItemEntries {
    final selected = state.selectedItems.toSet();
    return FocusStudioItemCatalog.editable(
      state.payload,
    ).where((entry) => selected.contains(entry.reference)).toList();
  }

  Rect? get selectedItemsBounds {
    Rect? bounds;
    for (final entry in selectedItemEntries) {
      final itemBounds = FocusStudioItemGeometry.boundsOf(entry.item);
      if (itemBounds == null) continue;
      bounds = bounds == null ? itemBounds : bounds.expandToInclude(itemBounds);
    }
    return bounds;
  }

  void selectItems(
    Iterable<FocusStudioItemReference> references, {
    bool additive = false,
  }) {
    final allowed = FocusStudioItemCatalog.editable(
      state.payload,
    ).map((entry) => entry.reference).toSet();
    final next = additive
        ? <FocusStudioItemReference>{...state.selectedItems}
        : <FocusStudioItemReference>{};
    for (final reference in references) {
      if (allowed.contains(reference)) next.add(reference);
    }
    state = state.copyWith(selectedItems: next.toList());
  }

  void toggleItemSelection(FocusStudioItemReference reference) {
    final selected = <FocusStudioItemReference>{...state.selectedItems};
    if (selected.contains(reference)) {
      selected.remove(reference);
    } else {
      final allowed = FocusStudioItemCatalog.editable(
        state.payload,
      ).any((entry) => entry.reference == reference);
      if (!allowed) return;
      selected.add(reference);
    }
    state = state.copyWith(selectedItems: selected.toList());
  }

  void clearItemSelection() => state = state.copyWith(selectedItems: const []);

  void selectAllItems() {
    state = state.copyWith(
      activeTool: StudioTool.itemSelection,
      selectedItems: FocusStudioItemCatalog.editable(
        state.payload,
      ).map((entry) => entry.reference).toList(),
    );
  }

  void moveSelectedItems(Offset delta) {
    if (delta == Offset.zero) return;
    final updates = <FocusStudioItemReference, Object>{};
    for (final entry in selectedItemEntries) {
      updates[entry.reference] = FocusStudioItemCatalog.translate(
        entry.item,
        delta,
      );
    }
    _applyItemUpdates(updates, action: 'Move Items');
  }

  void resizeSelectedItems(Rect targetBounds) {
    final sourceBounds = selectedItemsBounds;
    if (sourceBounds == null || sourceBounds == targetBounds) return;
    _resizeItemsFrom(
      sourceBounds: sourceBounds,
      targetBounds: targetBounds,
      entries: selectedItemEntries,
    );
  }

  void resizeSelectedItemsFromGesture(Rect targetBounds) {
    final initialPayload = _itemGestureInitialPayload;
    if (initialPayload == null) {
      resizeSelectedItems(targetBounds);
      return;
    }
    final selected = state.selectedItems.toSet();
    final entries = FocusStudioItemCatalog.editable(
      initialPayload,
    ).where((entry) => selected.contains(entry.reference)).toList();
    Rect? sourceBounds;
    for (final entry in entries) {
      final itemBounds = FocusStudioItemGeometry.boundsOf(entry.item);
      if (itemBounds == null) continue;
      sourceBounds = sourceBounds == null
          ? itemBounds
          : sourceBounds.expandToInclude(itemBounds);
    }
    if (sourceBounds == null || sourceBounds == targetBounds) return;
    _resizeItemsFrom(
      sourceBounds: sourceBounds,
      targetBounds: targetBounds,
      entries: entries,
    );
  }

  void _resizeItemsFrom({
    required Rect sourceBounds,
    required Rect targetBounds,
    required List<FocusStudioItemEntry> entries,
  }) {
    final updates = <FocusStudioItemReference, Object>{};
    for (final entry in entries) {
      updates[entry.reference] = FocusStudioItemCatalog.scale(
        entry.item,
        sourceBounds,
        targetBounds,
      );
    }
    _applyItemUpdates(updates, action: 'Resize Items');
  }

  void rotateSelectedItems(double angle, {Offset? pivot}) {
    if (angle == 0.0) return;
    final actualPivot = pivot ?? selectedItemsBounds?.center;
    if (actualPivot == null) return;
    final updates = <FocusStudioItemReference, Object>{};
    for (final entry in selectedItemEntries) {
      updates[entry.reference] = FocusStudioItemCatalog.rotate(
        entry.item,
        angle,
        actualPivot,
      );
    }
    _applyItemUpdates(updates, action: 'Rotate Items');
  }

  void deleteSelectedItems() {
    final entries = selectedItemEntries;
    final references = entries.map((entry) => entry.reference).toSet();
    if (references.isEmpty) return;
    final affectsRaster = _containsRasterItems(
      entries.map((entry) => entry.item),
    );
    final rebuildRaster = affectsRaster;
    _recordHistory('Delete Items');
    final nextPayload = FocusStudioItemCatalog.remove(state.payload, references)
        .copyWith(
          rasterRevision: rebuildRaster
              ? state.payload.rasterRevision + 1
              : state.payload.rasterRevision,
        );
    state = state.copyWith(payload: nextPayload, selectedItems: const []);
    if (rebuildRaster) _rebuildRasterPreview();
  }

  void copySelectedItems() {
    final clipboard = selectedItemEntries
        .map(
          (entry) => FocusStudioClipboardItem(
            reference: entry.reference,
            item: FocusStudioItemCatalog.clone(entry.item),
          ),
        )
        .toList();
    if (clipboard.isEmpty) return;
    state = state.copyWith(itemClipboard: clipboard);
  }

  void cutSelectedItems() {
    copySelectedItems();
    deleteSelectedItems();
  }

  void duplicateSelectedItems() {
    final entries = selectedItemEntries;
    if (entries.isEmpty) return;
    const offset = Offset(24, 24);
    final duplicated = <FocusStudioClipboardItem>[];
    final newReferences = <FocusStudioItemReference>[];
    for (final entry in entries) {
      final id = _nextItemId(entry.reference.kind);
      final item = FocusStudioItemCatalog.translate(
        FocusStudioItemCatalog.withId(
          FocusStudioItemCatalog.clone(entry.item),
          id,
        ),
        offset,
      );
      final reference = _referenceFor(
        entry.reference.kind,
        id,
        entry.reference.layerId,
      );
      duplicated.add(
        FocusStudioClipboardItem(reference: reference, item: item),
      );
      newReferences.add(reference);
    }
    final affectsRaster = _containsRasterItems(
      duplicated.map((entry) => entry.item),
    );
    final rebuildRaster = affectsRaster;
    _recordHistory('Duplicate Items');
    final nextPayload =
        FocusStudioItemCatalog.addClipboardItems(
          state.payload,
          duplicated,
        ).copyWith(
          rasterRevision: rebuildRaster
              ? state.payload.rasterRevision + 1
              : state.payload.rasterRevision,
        );
    state = state.copyWith(payload: nextPayload, selectedItems: newReferences);
    if (rebuildRaster) _rebuildRasterPreview();
  }

  void pasteSelectedItems() {
    if (state.itemClipboard.isEmpty) return;
    final activeLayer = state.activeLayer;
    final activeLayerId =
        activeLayer != null && _isLayerEditable(state.payload, activeLayer)
        ? activeLayer.id
        : null;
    const offset = Offset(24, 24);
    final pasted = <FocusStudioClipboardItem>[];
    final references = <FocusStudioItemReference>[];
    for (final entry in state.itemClipboard) {
      final sourceLayerId = entry.reference.layerId;
      final layerId = sourceLayerId == null ? null : activeLayerId;
      if (sourceLayerId != null && layerId == null) continue;
      final id = _nextItemId(entry.reference.kind);
      final item = FocusStudioItemCatalog.translate(
        FocusStudioItemCatalog.withId(
          FocusStudioItemCatalog.clone(entry.item),
          id,
        ),
        offset,
      );
      final reference = _referenceFor(entry.reference.kind, id, layerId);
      pasted.add(FocusStudioClipboardItem(reference: reference, item: item));
      references.add(reference);
    }
    if (pasted.isEmpty) return;
    final affectsRaster = _containsRasterItems(
      pasted.map((entry) => entry.item),
    );
    final rebuildRaster = affectsRaster;
    _recordHistory('Paste Items');
    final nextPayload =
        FocusStudioItemCatalog.addClipboardItems(
          state.payload,
          pasted,
        ).copyWith(
          rasterRevision: rebuildRaster
              ? state.payload.rasterRevision + 1
              : state.payload.rasterRevision,
        );
    state = state.copyWith(payload: nextPayload, selectedItems: references);
    if (rebuildRaster) _rebuildRasterPreview();
  }

  void beginItemTransform() {
    if (_itemGestureInitialPayload != null || state.selectedItems.isEmpty) {
      return;
    }
    _itemGestureInitialPayload = state.payload.clone();
    _itemGestureInitialRaster = state.rasterSurface?.clone();
    _itemGestureChanged = false;
  }

  void endItemTransform() {
    if (_itemGestureChanged &&
        _itemGestureAffectsRaster &&
        state.payload.rasterOperations.isEmpty) {
      state = state.copyWith(
        payload: state.payload.copyWith(
          rasterRevision: state.payload.rasterRevision + 1,
        ),
      );
      _rebuildRasterPreview();
    }
    _itemGestureInitialPayload = null;
    _itemGestureInitialRaster = null;
    _itemGestureChanged = false;
    _itemGestureAffectsRaster = false;
  }

  void _applyItemUpdates(
    Map<FocusStudioItemReference, Object> updates, {
    required String action,
  }) {
    if (updates.isEmpty) return;
    final affectsRaster = _containsRasterItems(updates.values);
    final rebuildRaster =
        affectsRaster &&
        (state.payload.rasterOperations.isNotEmpty ||
            _itemGestureInitialPayload == null);
    _recordItemHistory(action);
    final nextPayload =
        FocusStudioItemCatalog.applyUpdates(state.payload, updates).copyWith(
          rasterRevision: rebuildRaster
              ? state.payload.rasterRevision + 1
              : state.payload.rasterRevision,
        );
    state = state.copyWith(payload: nextPayload);
    if (rebuildRaster) _rebuildRasterPreview();
    _itemGestureAffectsRaster =
        _itemGestureAffectsRaster ||
        (affectsRaster && _itemGestureInitialPayload != null);
  }

  bool _containsRasterItems(Iterable<Object> items) =>
      items.any((item) => item is DrawingStroke);

  void _recordItemHistory(String action) {
    final initialPayload = _itemGestureInitialPayload;
    if (initialPayload == null) {
      _recordHistory(action);
      return;
    }
    if (_itemGestureChanged) return;
    _undoStack.add(initialPayload);
    _undoRasterStack.add(_itemGestureInitialRaster?.clone());
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
      _undoRasterStack.removeAt(0);
    }
    _redoStack.clear();
    _redoRasterStack.clear();
    timelapseRecorder.captureStep(action: action, layers: state.payload.layers);
    _itemGestureChanged = true;
    state = state.copyWith(
      undoCount: _undoStack.length,
      redoCount: _redoStack.length,
    );
  }

  FocusStudioItemReference _referenceFor(
    FocusStudioItemKind kind,
    String objectId,
    String? layerId,
  ) {
    return switch (kind) {
      FocusStudioItemKind.drawingStroke =>
        FocusStudioItemReference.drawingStroke(
          layerId: layerId!,
          objectId: objectId,
        ),
      FocusStudioItemKind.vectorShapeObject =>
        FocusStudioItemReference.vectorShapeObject(
          layerId: layerId!,
          objectId: objectId,
        ),
      FocusStudioItemKind.textObject => FocusStudioItemReference.textObject(
        layerId: layerId!,
        objectId: objectId,
      ),
      FocusStudioItemKind.mangaPanelCut =>
        FocusStudioItemReference.mangaPanelCut(objectId: objectId),
      FocusStudioItemKind.speechBalloon =>
        FocusStudioItemReference.speechBalloon(objectId: objectId),
    };
  }

  String _nextItemId(FocusStudioItemKind kind) {
    final prefix = switch (kind) {
      FocusStudioItemKind.drawingStroke => 'stroke',
      FocusStudioItemKind.vectorShapeObject => 'shape',
      FocusStudioItemKind.textObject => 'text',
      FocusStudioItemKind.mangaPanelCut => 'panel',
      FocusStudioItemKind.speechBalloon => 'balloon',
    };
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_itemIdSeed++}';
  }

  // --- Rulers & Guides ---
  void addRuler(RulerGuide ruler) {
    _recordHistory('Add Ruler');
    final list = List<RulerGuide>.from(state.rulers)..add(ruler);
    state = state.copyWith(
      rulers: list,
      payload: state.payload.copyWith(rulers: list),
    );
  }

  void toggleRuler(String id) {
    final list = state.rulers
        .map((r) => r.id == id ? r.copyWith(active: !r.active) : r)
        .toList();
    state = state.copyWith(
      rulers: list,
      payload: state.payload.copyWith(rulers: list),
    );
  }

  void clearRulers() {
    state = state.copyWith(
      rulers: [],
      payload: state.payload.copyWith(rulers: []),
    );
  }

  // --- Selection ---
  void setSelection(SelectionMask? mask) {
    state = state.copyWith(
      selection: mask,
      payload: state.payload.copyWith(activeSelection: mask),
    );
  }

  void clearSelection() => setSelection(null);
}

final drawingStudioProviderFamily = StateNotifierProvider.autoDispose
    .family<DrawingStudioNotifier, DrawingStudioState, DrawingPaperPayload>((
      ref,
      payload,
    ) {
      return DrawingStudioNotifier(payload);
    });
