import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';
import 'package:varian/features/drawing_paper/domain/models/raster_edit_operation.dart';
import 'package:varian/features/drawing_paper/domain/models/ruler_guide.dart';
import 'package:varian/features/drawing_paper/domain/models/selection_mask.dart';
import 'package:varian/features/drawing_paper/domain/models/studio_item_selection.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_renderer.dart';
import 'package:varian/features/drawing_paper/domain/services/studio_item_selection_service.dart';
import '../../domain/services/stroke_stabilizer.dart';
import '../../state/drawing_paper_provider.dart';
import 'painters/studio_brush_cursor_painter.dart';
import 'painters/studio_workspace_painter.dart';
import 'widgets/reference_window.dart';
import 'widgets/studio_brush_settings_bar.dart';
import 'widgets/studio_color_panel.dart';
import 'widgets/studio_layer_panel.dart';
import 'widgets/studio_left_toolbar.dart';
import 'widgets/studio_top_bar.dart';

enum _ItemTransformHandle {
  topLeft,
  top,
  topRight,
  left,
  right,
  bottomLeft,
  bottom,
  bottomRight,
  rotation,
}

class DrawingStudioScreen extends ConsumerStatefulWidget {
  final DrawingPaperPayload initialPayload;
  final Function(DrawingPaperPayload updatedPayload) onSaveAndExit;

  const DrawingStudioScreen({
    super.key,
    required this.initialPayload,
    required this.onSaveAndExit,
  });

  @override
  ConsumerState<DrawingStudioScreen> createState() =>
      _DrawingStudioScreenState();
}

class _DrawingStudioScreenState extends ConsumerState<DrawingStudioScreen> {
  final List<DrawingStrokePoint> _activePoints = [];
  final StrokeStabilizer _stabilizer = StrokeStabilizer();
  bool _isDrawing = false;
  bool _isPanning = false;
  bool _isSelecting = false;
  bool _spacePressed = false;
  List<Offset> _selectionPoints = [];
  late final List<DrawingPaperPage> _pages;
  late String _activePageId;
  final Map<String, ui.Image> _rasterImages = {};
  final Map<String, double> _rasterImageScales = {};
  final Map<String, int> _decodedRasterRevisions = {};
  final Set<String> _rasterDecodePending = {};
  String? _gesturePageId;
  Offset? _shapeStartPos;
  bool _isTransforming = false;
  Offset? _transformStartPos;
  Offset? _transformCurrentPos;
  Rect? _transformBounds;
  bool _isItemMarquee = false;
  bool _isItemMoving = false;
  bool _isItemResizing = false;
  bool _isItemRotating = false;
  Offset? _itemMarqueeStart;
  Offset? _itemMarqueeCurrent;
  Offset? _itemDragStart;
  Offset _itemDragDelta = Offset.zero;
  Rect? _itemInitialBounds;
  _ItemTransformHandle? _itemTransformHandle;
  double? _itemLastRotationAngle;
  bool _shiftPressed = false;
  bool _itemGestureAdditive = false;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  TextObjectData? _editingTextObject;
  SpeechBalloon? _editingBalloon;
  bool _editingNewText = false;
  double _pointerPressure = 1.0;
  double _pointerTilt = 0.0;
  Offset? _lastPointerPosition;
  Offset? _brushCursorPosition;
  Offset? _pointerDownScreenPosition;

  bool _initializedFit = false;

  @override
  void initState() {
    super.initState();
    _pages = DrawingPaperRenderer.workspacePages(widget.initialPayload);
    _activePageId = _pages.first.id;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    for (final image in _rasterImages.values) {
      image.dispose();
    }
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  void _syncRasterImages(DrawingStudioState state) {
    for (final page in _pages) {
      final revision = page.id == _activePageId
          ? state.payload.rasterRevision
          : page.payload.rasterRevision;
      if (_rasterDecodePending.contains(page.id) ||
          _decodedRasterRevisions[page.id] == revision) {
        continue;
      }

      final preview = page.id == _activePageId
          ? (surface: state.rasterSurface, scale: state.rasterPreviewScale)
          : DrawingPaperRenderer.buildRasterPreview(page.payload);
      final surface = preview.surface;
      if (surface == null) continue;

      _rasterImageScales[page.id] = preview.scale;
      _rasterDecodePending.add(page.id);
      final pixels = Uint8List.fromList(surface.pixels);
      ui.decodeImageFromPixels(
        pixels,
        surface.width,
        surface.height,
        ui.PixelFormat.rgba8888,
        (image) {
          _rasterDecodePending.remove(page.id);
          if (!mounted) {
            image.dispose();
            return;
          }
          final oldImage = _rasterImages[page.id];
          _rasterImages[page.id] = image;
          _decodedRasterRevisions[page.id] = revision;
          oldImage?.dispose();
          setState(() {});
        },
      );
    }
  }

  void _capturePointer(PointerEvent event) {
    final pressure = event.pressure;
    _pointerPressure = pressure.isFinite && pressure > 0
        ? pressure.clamp(0.0, 1.0).toDouble()
        : 1.0;
    _pointerTilt = event.tilt.isFinite ? event.tilt : 0.0;
  }

  bool _usesCustomBrushCursor(StudioTool tool) => switch (tool) {
    StudioTool.brush ||
    StudioTool.eraser ||
    StudioTool.bucketFill ||
    StudioTool.lassoFill ||
    StudioTool.smudge ||
    StudioTool.blur => true,
    _ => false,
  };

  void _updateBrushCursor(Offset position, DrawingStudioState state) {
    _lastPointerPosition = position;
    if (!_usesCustomBrushCursor(state.activeTool)) {
      if (_brushCursorPosition != null) {
        setState(() => _brushCursorPosition = null);
      }
      return;
    }
    if (_brushCursorPosition == position) return;
    setState(() => _brushCursorPosition = position);
  }

  void _clearBrushCursor() {
    _lastPointerPosition = null;
    if (_brushCursorPosition == null) return;
    setState(() => _brushCursorPosition = null);
  }

  bool _handleKeyEvent(KeyEvent event) {
    final isDown = event is KeyDownEvent;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (_spacePressed != isDown) {
        setState(() => _spacePressed = isDown);
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight) {
      _shiftPressed = isDown;
    }

    if (!isDown) return false;
    final provider = drawingStudioProviderFamily(widget.initialPayload);
    final currentState = ref.read(provider);
    final notifier = ref.read(provider.notifier);

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final wasEditing = _editingTextObject != null || _editingBalloon != null;
      if (_editingTextObject != null) {
        _finishInlineTextEdit(notifier, cancel: true);
      } else if (_editingBalloon != null) {
        _finishInlineBalloonEdit(notifier, cancel: true);
      }
      if (wasEditing) return true;
      if (currentState.activeTool == StudioTool.itemSelection) {
        notifier.clearItemSelection();
        return true;
      }
      return false;
    }

    if (_editingTextObject != null || _editingBalloon != null) return false;

    final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
    final hasCommandModifier =
        pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
        pressedKeys.contains(LogicalKeyboardKey.controlRight) ||
        pressedKeys.contains(LogicalKeyboardKey.metaLeft) ||
        pressedKeys.contains(LogicalKeyboardKey.metaRight);
    final hasShiftModifier =
        _shiftPressed ||
        pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
        pressedKeys.contains(LogicalKeyboardKey.shiftRight);

    if (hasCommandModifier && event.logicalKey == LogicalKeyboardKey.keyA) {
      notifier.selectAllItems();
      return true;
    }
    if (hasCommandModifier && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (currentState.activeTool == StudioTool.itemSelection) {
        notifier.copySelectedItems();
      } else {
        notifier.copySelection();
      }
      return true;
    }
    if (hasCommandModifier && event.logicalKey == LogicalKeyboardKey.keyX) {
      if (currentState.activeTool == StudioTool.itemSelection) {
        notifier.cutSelectedItems();
      } else {
        notifier.cutSelection();
      }
      return true;
    }
    if (hasCommandModifier && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (currentState.activeTool == StudioTool.itemSelection) {
        notifier.pasteSelectedItems();
      } else {
        notifier.pasteClipboard();
      }
      return true;
    }
    if (hasCommandModifier && event.logicalKey == LogicalKeyboardKey.keyD) {
      if (currentState.activeTool == StudioTool.itemSelection) {
        notifier.duplicateSelectedItems();
        return true;
      }
    }
    if (hasCommandModifier && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (hasShiftModifier) {
        notifier.redo();
      } else {
        notifier.undo();
      }
      return true;
    }
    if (hasCommandModifier && event.logicalKey == LogicalKeyboardKey.keyY) {
      notifier.redo();
      return true;
    }
    if (currentState.activeTool == StudioTool.itemSelection &&
        (event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace)) {
      notifier.deleteSelectedItems();
      return true;
    }
    if (currentState.activeTool == StudioTool.itemSelection &&
        currentState.selectedItems.isNotEmpty) {
      final step = hasShiftModifier ? 10.0 : 1.0;
      final delta = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
        LogicalKeyboardKey.arrowRight => Offset(step, 0),
        LogicalKeyboardKey.arrowUp => Offset(0, -step),
        LogicalKeyboardKey.arrowDown => Offset(0, step),
        _ => null,
      };
      if (delta != null) {
        notifier.moveSelectedItems(delta);
        return true;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.keyV) {
      notifier.setTool(StudioTool.itemSelection);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyH) {
      notifier.setTool(StudioTool.hand);
      return true;
    } else if (event.logicalKey == LogicalKeyboardKey.keyB) {
      notifier.setTool(StudioTool.brush);
      return true;
    } else if (event.logicalKey == LogicalKeyboardKey.keyE) {
      notifier.setTool(StudioTool.eraser);
      return true;
    }

    return false;
  }

  Rect _workspaceBounds() =>
      DrawingPaperRenderer.workspaceBoundsForPages(_pages);

  Offset _screenToWorkspaceCoord(
    Offset screenPos,
    Size viewportSize,
    DrawingStudioState state,
  ) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final relative = screenPos - center - state.viewPan;
    final unrotated = Offset(
      relative.dx * cos(state.viewRotation) +
          relative.dy * sin(state.viewRotation),
      -relative.dx * sin(state.viewRotation) +
          relative.dy * cos(state.viewRotation),
    );
    return unrotated / state.viewZoom + _workspaceBounds().center;
  }

  Offset _screenDeltaToPaperDelta(
    Offset screenDelta,
    DrawingStudioState state,
  ) {
    final unrotated = Offset(
      screenDelta.dx * cos(state.viewRotation) +
          screenDelta.dy * sin(state.viewRotation),
      -screenDelta.dx * sin(state.viewRotation) +
          screenDelta.dy * cos(state.viewRotation),
    );
    return unrotated / state.viewZoom;
  }

  Offset _workspaceToScreenCoord(
    Offset workspacePos,
    Size viewportSize,
    DrawingStudioState state,
  ) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final local = (workspacePos - _workspaceBounds().center) * state.viewZoom;
    final rotated = Offset(
      local.dx * cos(state.viewRotation) - local.dy * sin(state.viewRotation),
      local.dx * sin(state.viewRotation) + local.dy * cos(state.viewRotation),
    );
    return center + state.viewPan + rotated;
  }

  DrawingPaperPage? _pageAt(Offset workspacePos) {
    for (final page in _pages.reversed) {
      final rect = Rect.fromLTWH(
        page.position.dx,
        page.position.dy,
        page.payload.pixelWidth,
        page.payload.pixelHeight,
      );
      if (rect.contains(workspacePos)) return page;
    }
    return null;
  }

  DrawingPaperPage get _activePage =>
      _pages.firstWhere((page) => page.id == _activePageId);

  DrawingPaperPage? _pageById(String? pageId) {
    if (pageId == null) return null;
    for (final page in _pages) {
      if (page.id == pageId) return page;
    }
    return null;
  }

  void _commitActivePage(DrawingStudioState state) {
    final index = _pages.indexWhere((page) => page.id == _activePageId);
    if (index == -1) return;
    _pages[index] = _pages[index].copyWith(
      payload: state.payload.copyWith(studioPages: const []),
    );
  }

  void _focusPage(
    DrawingPaperPage page,
    DrawingStudioState state,
    DrawingStudioNotifier notifier,
  ) {
    if (page.id == _activePageId) return;
    if (_editingTextObject != null) {
      _finishInlineTextEdit(notifier, cancel: true);
    }
    if (_editingBalloon != null) {
      _finishInlineBalloonEdit(notifier, cancel: true);
    }
    _commitActivePage(state);
    setState(() {
      _activePageId = page.id;
      _activePoints.clear();
      _selectionPoints.clear();
      _shapeStartPos = null;
      _isDrawing = false;
      _isSelecting = false;
      _isTransforming = false;
      _gesturePageId = page.id;
    });
    notifier.replacePayload(page.payload);
  }

  Rect _pageRect(DrawingPaperPage page) => Rect.fromLTWH(
    page.position.dx,
    page.position.dy,
    page.payload.pixelWidth,
    page.payload.pixelHeight,
  );

  DrawingPaperPage _pageForWorkspaceSide(Offset direction, Rect bounds) {
    final edgePages = _pages.where((page) {
      final rect = _pageRect(page);
      return direction.dx > 0
          ? (rect.right - bounds.right).abs() <= 0.5
          : direction.dx < 0
          ? (rect.left - bounds.left).abs() <= 0.5
          : direction.dy > 0
          ? (rect.bottom - bounds.bottom).abs() <= 0.5
          : (rect.top - bounds.top).abs() <= 0.5;
    }).toList();
    if (edgePages.isEmpty) return _pages.first;

    edgePages.sort((a, b) {
      final aCenter = _pageRect(a).center;
      final bCenter = _pageRect(b).center;
      final aDistance = direction.dx != 0
          ? (aCenter.dy - bounds.center.dy).abs()
          : (aCenter.dx - bounds.center.dx).abs();
      final bDistance = direction.dx != 0
          ? (bCenter.dy - bounds.center.dy).abs()
          : (bCenter.dx - bounds.center.dx).abs();
      return aDistance.compareTo(bDistance);
    });
    return edgePages.first;
  }

  Offset _workspaceSideAnchor(Rect bounds, Offset direction) => Offset(
    direction.dx > 0
        ? bounds.right + 16
        : direction.dx < 0
        ? bounds.left - 16
        : bounds.center.dx,
    direction.dy > 0
        ? bounds.bottom + 16
        : direction.dy < 0
        ? bounds.top - 16
        : bounds.center.dy,
  );

  DrawingPaperPayload _newStudioPagePayload(DrawingPaperPayload source) {
    return source.copyWith(
      rasterDocumentId: const Uuid().v4(),
      rasterRevision: 0,
      compositePreviewRef: null,
      rasterOperations: const [],
      layers: const [DrawingLayer(id: 'layer_1', name: 'Background Layer')],
      activeLayerIndex: 0,
      activeSelection: null,
      rulers: const [],
      mangaStructure: null,
      studioPages: const [],
    );
  }

  void _addAdjacentPage(
    DrawingPaperPage source,
    Offset direction,
    DrawingStudioState state,
    DrawingStudioNotifier notifier,
  ) {
    _commitActivePage(state);
    final oldWorkspaceBounds = _workspaceBounds();
    final sourcePage = _pageById(source.id) ?? source;
    final size = sourcePage.payload.pixelSize;
    final position = Offset(
      sourcePage.position.dx +
          (direction.dx > 0
              ? size.width
              : direction.dx < 0
              ? -size.width
              : 0),
      sourcePage.position.dy +
          (direction.dy > 0
              ? size.height
              : direction.dy < 0
              ? -size.height
              : 0),
    );
    final page = DrawingPaperPage(
      id: const Uuid().v4(),
      position: position,
      payload: _newStudioPagePayload(sourcePage.payload),
    );
    _pages.add(page);
    final newWorkspaceBounds = _workspaceBounds();
    final panAdjustment =
        (newWorkspaceBounds.center - oldWorkspaceBounds.center) *
        state.viewZoom;
    setState(() {
      _activePageId = page.id;
      _activePoints.clear();
      _gesturePageId = page.id;
    });
    notifier.replacePayload(page.payload);
    notifier.setViewPan(state.viewPan + panAdjustment);
  }

  void _saveWorkspace(DrawingStudioState state) {
    _commitActivePage(state);
    final pages = _pages
        .skip(1)
        .map(
          (page) => page.copyWith(
            payload: page.payload.copyWith(studioPages: const []),
          ),
        )
        .toList();
    final rootPayload = _pages.first.payload.copyWith(studioPages: pages);
    widget.onSaveAndExit(rootPayload);
  }

  List<Widget> _buildPageControls(
    Size viewportSize,
    DrawingStudioState state,
    DrawingStudioNotifier notifier,
  ) {
    const directions = <Offset>[
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, -1),
      Offset(0, 1),
    ];
    final workspaceBounds = _workspaceBounds();
    return [
      for (final direction in directions)
        _buildPageControl(
          _pageForWorkspaceSide(direction, workspaceBounds),
          direction,
          _workspaceSideAnchor(workspaceBounds, direction),
          viewportSize,
          state,
          notifier,
        ),
    ];
  }

  Widget _buildPageControl(
    DrawingPaperPage page,
    Offset direction,
    Offset anchor,
    Size viewportSize,
    DrawingStudioState state,
    DrawingStudioNotifier notifier,
  ) {
    final screenAnchor = _workspaceToScreenCoord(anchor, viewportSize, state);
    return Positioned(
      left: screenAnchor.dx - AppControlSize.minimumHitTarget / 2,
      top: screenAnchor.dy - AppControlSize.minimumHitTarget / 2,
      child: UiIconButton(
        icon: Icons.add,
        tooltip: 'Add same-size paper',
        size: UiButtonSize.sm,
        onPressed: () => _addAdjacentPage(page, direction, state, notifier),
      ),
    );
  }

  TextObjectData? _textAt(DrawingStudioState state, Offset paperPos) {
    for (final entry in FocusStudioItemCatalog.all(state.payload)) {
      final item = entry.item;
      if (item is TextObjectData &&
          FocusStudioItemGeometry.hitTest(item, paperPos, tolerance: 4.0)) {
        return item;
      }
    }
    return null;
  }

  SpeechBalloon? _balloonAt(DrawingStudioState state, Offset paperPos) {
    for (final entry in FocusStudioItemCatalog.all(state.payload)) {
      final item = entry.item;
      if (item is SpeechBalloon &&
          FocusStudioItemGeometry.hitTest(item, paperPos, tolerance: 4.0)) {
        return item;
      }
    }
    return null;
  }

  void _beginInlineBalloonEdit(SpeechBalloon balloon) {
    _textController.value = TextEditingValue(
      text: balloon.text,
      selection: TextSelection.collapsed(offset: balloon.text.length),
    );
    setState(() => _editingBalloon = balloon);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingBalloon?.id == balloon.id) {
        _textFocusNode.requestFocus();
      }
    });
  }

  void _finishInlineBalloonEdit(
    DrawingStudioNotifier notifier, {
    bool cancel = false,
  }) {
    final balloon = _editingBalloon;
    if (balloon == null) return;
    if (!cancel && _textController.text.trim().isNotEmpty) {
      notifier.updateSpeechBalloon(
        balloon.copyWith(text: _textController.text),
      );
    }
    setState(() => _editingBalloon = null);
    _textFocusNode.unfocus();
  }

  void _beginInlineTextEdit(Offset paperPos, DrawingStudioState state) {
    final existing = _textAt(state, paperPos);
    final object =
        existing ??
        TextObjectData(
          id: 'text_${DateTime.now().microsecondsSinceEpoch}',
          x: paperPos.dx,
          y: paperPos.dy,
          color: state.primaryColor,
          fontFamily: state.activeFontFamily,
          fontSize: state.activeFontSize,
          isVertical: state.activeTextVertical,
          outlineColor: state.activeTextOutlineColor,
          outlineWidth: state.activeTextOutlineWidth,
        );
    _textController.value = TextEditingValue(
      text: object.text,
      selection: TextSelection.collapsed(offset: object.text.length),
    );
    setState(() {
      _editingTextObject = object;
      _editingNewText = existing == null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingTextObject?.id == object.id) {
        _textFocusNode.requestFocus();
      }
    });
  }

  void _finishInlineTextEdit(
    DrawingStudioNotifier notifier, {
    bool cancel = false,
  }) {
    final object = _editingTextObject;
    if (object == null) return;
    final text = _textController.text;
    if (!cancel && text.trim().isNotEmpty) {
      final updated = object.copyWith(text: text);
      if (_editingNewText) {
        notifier.addTextToActiveLayer(updated);
      } else {
        notifier.updateTextObject(updated);
      }
    }
    setState(() {
      _editingTextObject = null;
      _editingNewText = false;
    });
    _textFocusNode.unfocus();
  }

  Widget _buildInlineTextEditor(
    TextObjectData object,
    Size viewportSize,
    DrawingStudioState state,
    DrawingStudioNotifier notifier,
  ) {
    final position = _workspaceToScreenCoord(
      _activePage.position + Offset(object.x, object.y),
      viewportSize,
      state,
    );
    final width = max(120.0, object.width * state.viewZoom);
    final height = max(48.0, object.bounds.height * state.viewZoom + 16.0);

    return Positioned(
      left: position.dx,
      top: position.dy,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: state.viewRotation,
        alignment: Alignment.topLeft,
        child: TapRegion(
          onTapOutside: (_) => _finishInlineTextEdit(notifier),
          child: Material(
            color: Colors.transparent,
            child: TextField(
              key: const ValueKey('drawing-studio-inline-text-editor'),
              controller: _textController,
              focusNode: _textFocusNode,
              autofocus: true,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              maxLines: null,
              expands: true,
              style: TextStyle(
                color: object.color,
                fontFamily: object.fontFamily,
                fontSize: object.fontSize * state.viewZoom,
                fontWeight: object.fontWeight,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: context.appTokens.panel,
                hintText: 'Type text',
                contentPadding: const EdgeInsets.all(AppSpacing.md),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: object.color),
                ),
              ),
              onSubmitted: (_) => _finishInlineTextEdit(notifier),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineBalloonEditor(
    SpeechBalloon balloon,
    Size viewportSize,
    DrawingStudioState state,
    DrawingStudioNotifier notifier,
  ) {
    final position = _workspaceToScreenCoord(
      _activePage.position + balloon.position,
      viewportSize,
      state,
    );
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: max(64.0, balloon.size.width * state.viewZoom),
      height: max(48.0, balloon.size.height * state.viewZoom),
      child: Transform.rotate(
        angle: state.viewRotation,
        alignment: Alignment.topLeft,
        child: TapRegion(
          onTapOutside: (_) => _finishInlineBalloonEdit(notifier),
          child: Material(
            color: Colors.transparent,
            child: TextField(
              key: const ValueKey('drawing-studio-inline-balloon-editor'),
              controller: _textController,
              focusNode: _textFocusNode,
              autofocus: true,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              maxLines: null,
              expands: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: balloon.textColor,
                fontSize: balloon.fontSize * state.viewZoom,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: balloon.balloonColor.withValues(alpha: 0.94),
                hintText: 'Balloon text',
                contentPadding: const EdgeInsets.all(AppSpacing.sm),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: balloon.borderColor),
                ),
              ),
              onSubmitted: (_) => _finishInlineBalloonEdit(notifier),
            ),
          ),
        ),
      ),
    );
  }

  FocusStudioItemReference? _itemAt(DrawingStudioState state, Offset paperPos) {
    const hitTolerance = 6.0;
    for (final entry in FocusStudioItemCatalog.editable(state.payload)) {
      if (FocusStudioItemGeometry.hitTest(
        entry.item,
        paperPos,
        tolerance: hitTolerance / state.viewZoom,
      )) {
        return entry.reference;
      }
    }
    return null;
  }

  _ItemTransformHandle? _itemHandleAt(
    Rect bounds,
    Offset paperPos,
    double zoom,
  ) {
    final tolerance = 10.0 / zoom;
    final points = <_ItemTransformHandle, Offset>{
      _ItemTransformHandle.topLeft: bounds.topLeft,
      _ItemTransformHandle.top: Offset(bounds.center.dx, bounds.top),
      _ItemTransformHandle.topRight: bounds.topRight,
      _ItemTransformHandle.left: Offset(bounds.left, bounds.center.dy),
      _ItemTransformHandle.right: Offset(bounds.right, bounds.center.dy),
      _ItemTransformHandle.bottomLeft: bounds.bottomLeft,
      _ItemTransformHandle.bottom: Offset(bounds.center.dx, bounds.bottom),
      _ItemTransformHandle.bottomRight: bounds.bottomRight,
      _ItemTransformHandle.rotation: Offset(
        bounds.center.dx,
        bounds.top - 28.0 / zoom,
      ),
    };
    for (final entry in points.entries) {
      if ((entry.value - paperPos).distance <= tolerance) return entry.key;
    }
    return null;
  }

  Rect _resizeItemBounds(
    Rect initial,
    _ItemTransformHandle handle,
    Offset delta,
  ) {
    var left = initial.left;
    var top = initial.top;
    var right = initial.right;
    var bottom = initial.bottom;
    switch (handle) {
      case _ItemTransformHandle.topLeft:
        left += delta.dx;
        top += delta.dy;
        break;
      case _ItemTransformHandle.top:
        top += delta.dy;
        break;
      case _ItemTransformHandle.topRight:
        right += delta.dx;
        top += delta.dy;
        break;
      case _ItemTransformHandle.left:
        left += delta.dx;
        break;
      case _ItemTransformHandle.right:
        right += delta.dx;
        break;
      case _ItemTransformHandle.bottomLeft:
        left += delta.dx;
        bottom += delta.dy;
        break;
      case _ItemTransformHandle.bottom:
        bottom += delta.dy;
        break;
      case _ItemTransformHandle.bottomRight:
        right += delta.dx;
        bottom += delta.dy;
        break;
      case _ItemTransformHandle.rotation:
        return initial;
    }
    const minimumSize = 2.0;
    if (right - left < minimumSize) {
      if (handle == _ItemTransformHandle.left ||
          handle == _ItemTransformHandle.topLeft ||
          handle == _ItemTransformHandle.bottomLeft) {
        left = right - minimumSize;
      } else {
        right = left + minimumSize;
      }
    }
    if (bottom - top < minimumSize) {
      if (handle == _ItemTransformHandle.top ||
          handle == _ItemTransformHandle.topLeft ||
          handle == _ItemTransformHandle.topRight) {
        top = bottom - minimumSize;
      } else {
        bottom = top + minimumSize;
      }
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  double _angleFromCenter(Offset point, Offset center) =>
      atan2(point.dy - center.dy, point.dx - center.dx);

  double _normalizedAngleDelta(double angle) {
    var value = angle;
    while (value > pi) {
      value -= 2 * pi;
    }
    while (value < -pi) {
      value += 2 * pi;
    }
    return value;
  }

  void _beginItemGesture(
    Offset paperPos,
    DrawingStudioState state,
    DrawingStudioNotifier notifier,
  ) {
    _itemMarqueeStart = null;
    _itemMarqueeCurrent = null;
    _itemDragStart = paperPos;
    _itemDragDelta = Offset.zero;
    _itemInitialBounds = notifier.selectedItemsBounds;
    _itemTransformHandle = _itemInitialBounds == null
        ? null
        : _itemHandleAt(_itemInitialBounds!, paperPos, state.viewZoom);
    _itemLastRotationAngle = null;
    _isItemMarquee = false;
    _isItemMoving = false;
    _isItemResizing = false;
    _isItemRotating = false;
    _shiftPressed =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );
    _itemGestureAdditive = _shiftPressed;

    if (_itemTransformHandle == _ItemTransformHandle.rotation &&
        _itemInitialBounds != null) {
      _isItemRotating = true;
      _itemLastRotationAngle = _angleFromCenter(
        paperPos,
        _itemInitialBounds!.center,
      );
      notifier.beginItemTransform();
      return;
    }
    if (_itemTransformHandle != null &&
        _itemTransformHandle != _ItemTransformHandle.rotation) {
      _isItemResizing = true;
      notifier.beginItemTransform();
      return;
    }
    final reference = _itemAt(state, paperPos);
    if (reference != null) {
      final alreadySelected = state.selectedItems.contains(reference);
      if (_shiftPressed) {
        notifier.toggleItemSelection(reference);
        return;
      }
      if (!alreadySelected) {
        notifier.selectItems([reference]);
      }
      _isItemMoving = true;
      _itemInitialBounds = notifier.selectedItemsBounds;
      notifier.beginItemTransform();
      return;
    }

    if (!_shiftPressed) notifier.clearItemSelection();
    _isItemMarquee = true;
    _itemMarqueeStart = paperPos;
    _itemMarqueeCurrent = paperPos;
  }

  void _finishItemGesture(DrawingStudioNotifier notifier) {
    notifier.endItemTransform();
    _isItemMarquee = false;
    _isItemMoving = false;
    _isItemResizing = false;
    _isItemRotating = false;
    _itemMarqueeStart = null;
    _itemMarqueeCurrent = null;
    _itemDragStart = null;
    _itemInitialBounds = null;
    _itemTransformHandle = null;
    _itemLastRotationAngle = null;
    _itemGestureAdditive = false;
  }

  void _handleTapUp(
    TapUpDetails details,
    Size viewportSize,
    DrawingStudioState state,
    DrawingStudioNotifier notifier,
  ) {
    final workspacePos = _screenToWorkspaceCoord(
      details.localPosition,
      viewportSize,
      state,
    );
    final page = _pageAt(workspacePos);
    if (page == null) return;
    if (page.id != _activePageId) {
      _focusPage(page, state, notifier);
    }
    final effectiveState = ref.read(
      drawingStudioProviderFamily(widget.initialPayload),
    );

    final paperPos = workspacePos - page.position;

    switch (effectiveState.activeTool) {
      case StudioTool.itemSelection:
        final reference = _itemAt(effectiveState, paperPos);
        if (reference == null) {
          if (!_shiftPressed) notifier.clearItemSelection();
        } else if (_shiftPressed) {
          notifier.toggleItemSelection(reference);
        } else if (!effectiveState.selectedItems.contains(reference)) {
          notifier.selectItems([reference]);
        }
        break;
      case StudioTool.text:
        _beginInlineTextEdit(paperPos, effectiveState);
        break;
      case StudioTool.bucketFill:
        notifier.applyRasterOperation(
          RasterEditOperation.bucketFill(
            seedPoint: paperPos,
            color: effectiveState.primaryColor,
            selection: effectiveState.selection,
          ),
        );
        break;
      case StudioTool.speechBalloon:
        final balloon = _balloonAt(effectiveState, paperPos);
        if (balloon != null) {
          _beginInlineBalloonEdit(balloon);
        }
        break;
      case StudioTool.eyedropper:
        final surface = effectiveState.rasterSurface;
        if (surface != null) {
          notifier.setPrimaryColor(
            surface.sample(paperPos * effectiveState.rasterPreviewScale),
          );
          notifier.setTool(StudioTool.brush);
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = drawingStudioProviderFamily(widget.initialPayload);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    _syncRasterImages(state);

    return UiPageScaffold(
      title: const SizedBox.shrink(),
      showHeader: false,
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Top Bar
                StudioTopBar(
                  initialPayload: widget.initialPayload,
                  onExit: () {
                    _saveWorkspace(state);
                    Navigator.of(context).pop();
                  },
                ),

                // Brush Settings Sub-bar
                StudioBrushSettingsBar(initialPayload: widget.initialPayload),

                // Center Workspace with Left Toolbar & Right Panels
                Expanded(
                  child: Row(
                    children: [
                      // Left Tools
                      StudioLeftToolbar(initialPayload: widget.initialPayload),

                      // Interactive Drawing Canvas Area
                      Expanded(
                        child: LayoutBuilder(
                          builder: (ctx, constraints) {
                            final viewportSize = Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );

                            if (!_initializedFit &&
                                viewportSize.width > 0 &&
                                viewportSize.height > 0) {
                              _initializedFit = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                notifier.resetView(
                                  viewportSize: viewportSize,
                                  workspaceSize: _workspaceBounds().size,
                                );
                              });
                            }

                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Listener(
                                  onPointerDown: (event) {
                                    _pointerDownScreenPosition =
                                        event.localPosition;
                                    _capturePointer(event);
                                    _updateBrushCursor(
                                      event.localPosition,
                                      state,
                                    );
                                  },
                                  onPointerMove: (event) {
                                    _capturePointer(event);
                                    _updateBrushCursor(
                                      event.localPosition,
                                      state,
                                    );
                                  },
                                  onPointerSignal: (pointerSignal) {
                                    if (pointerSignal is PointerScrollEvent) {
                                      final zoomDelta =
                                          pointerSignal.scrollDelta.dy < 0
                                          ? 1.1
                                          : 0.9;
                                      notifier.zoomBy(
                                        zoomDelta,
                                        pointerSignal.localPosition,
                                        viewportSize,
                                        _workspaceBounds().size,
                                      );
                                    }
                                  },
                                  child: GestureDetector(
                                    key: const ValueKey(
                                      'drawing-studio-canvas',
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    onPanStart: (details) {
                                      if (_spacePressed ||
                                          state.activeTool == StudioTool.hand) {
                                        _isPanning = true;
                                        return;
                                      }

                                      final workspacePos =
                                          _screenToWorkspaceCoord(
                                            _pointerDownScreenPosition ??
                                                details.localPosition,
                                            viewportSize,
                                            state,
                                          );
                                      final page = _pageAt(workspacePos);
                                      if (page == null) return;
                                      var gestureState = ref.read(provider);
                                      if (page.id != _activePageId) {
                                        _focusPage(page, state, notifier);
                                        gestureState = ref.read(provider);
                                      }
                                      _gesturePageId = page.id;
                                      final paperPos =
                                          workspacePos - page.position;

                                      if (gestureState.activeTool ==
                                          StudioTool.itemSelection) {
                                        _beginItemGesture(
                                          paperPos,
                                          gestureState,
                                          notifier,
                                        );
                                        return;
                                      }

                                      if (gestureState.activeTool ==
                                          StudioTool.selection) {
                                        _isSelecting = true;
                                        _selectionPoints = [paperPos];
                                        return;
                                      }

                                      if (gestureState.activeTool ==
                                          StudioTool.transform) {
                                        final bounds =
                                            gestureState
                                                .selection
                                                ?.boundingBox ??
                                            notifier.activeLayerBounds;
                                        if (bounds != null &&
                                            bounds.contains(paperPos)) {
                                          _isTransforming = true;
                                          _transformStartPos = paperPos;
                                          _transformCurrentPos = paperPos;
                                          _transformBounds = bounds;
                                        }
                                        return;
                                      }

                                      if (gestureState.activeTool ==
                                              StudioTool.ruler ||
                                          gestureState.activeTool ==
                                              StudioTool.mangaPanel ||
                                          gestureState.activeTool ==
                                              StudioTool.speechBalloon ||
                                          gestureState.activeTool ==
                                              StudioTool.shapes) {
                                        _shapeStartPos = paperPos;
                                        return;
                                      }

                                      if (gestureState.activeTool ==
                                              StudioTool.text ||
                                          gestureState.activeTool ==
                                              StudioTool.bucketFill ||
                                          gestureState.activeTool ==
                                              StudioTool.eyedropper) {
                                        return;
                                      }

                                      _isDrawing = true;
                                      _stabilizer.reset();
                                      _activePoints.clear();

                                      final rawPt = DrawingStrokePoint(
                                        x: paperPos.dx,
                                        y: paperPos.dy,
                                        pressure: _pointerPressure,
                                        tilt: _pointerTilt,
                                        timestamp: DateTime.now()
                                            .millisecondsSinceEpoch,
                                      );
                                      final stabilized = _stabilizer.addPoint(
                                        rawPt,
                                      );
                                      setState(
                                        () => _activePoints.add(stabilized),
                                      );
                                    },
                                    onPanUpdate: (details) {
                                      if (_spacePressed ||
                                          state.activeTool == StudioTool.hand ||
                                          _isPanning) {
                                        notifier.panBy(
                                          details.delta.dx,
                                          details.delta.dy,
                                          viewportSize: viewportSize,
                                          workspaceSize:
                                              _workspaceBounds().size,
                                        );
                                        return;
                                      }

                                      final workspacePos =
                                          _screenToWorkspaceCoord(
                                            details.localPosition,
                                            viewportSize,
                                            state,
                                          );
                                      final gesturePage =
                                          _pageById(_gesturePageId) ??
                                          _activePage;
                                      final paperPos =
                                          workspacePos - gesturePage.position;
                                      final paperDelta =
                                          _screenDeltaToPaperDelta(
                                            details.delta,
                                            state,
                                          );
                                      _itemDragDelta += paperDelta;

                                      if (_isItemMarquee) {
                                        setState(
                                          () => _itemMarqueeCurrent = paperPos,
                                        );
                                        return;
                                      }
                                      if (_isItemMoving) {
                                        notifier.moveSelectedItems(paperDelta);
                                        return;
                                      }
                                      if (_isItemResizing) {
                                        final bounds = _itemInitialBounds;
                                        final handle = _itemTransformHandle;
                                        if (bounds != null && handle != null) {
                                          notifier
                                              .resizeSelectedItemsFromGesture(
                                                _resizeItemBounds(
                                                  bounds,
                                                  handle,
                                                  _itemDragDelta,
                                                ),
                                              );
                                        }
                                        return;
                                      }
                                      if (_isItemRotating) {
                                        final bounds = _itemInitialBounds;
                                        final previous = _itemLastRotationAngle;
                                        if (bounds != null &&
                                            previous != null &&
                                            _itemDragStart != null) {
                                          final current = _angleFromCenter(
                                            _itemDragStart! + _itemDragDelta,
                                            bounds.center,
                                          );
                                          notifier.rotateSelectedItems(
                                            _normalizedAngleDelta(
                                              current - previous,
                                            ),
                                            pivot: bounds.center,
                                          );
                                          _itemLastRotationAngle = current;
                                        }
                                        return;
                                      }

                                      if (_isTransforming) {
                                        setState(
                                          () => _transformCurrentPos = paperPos,
                                        );
                                        return;
                                      }

                                      if (_isSelecting) {
                                        setState(() {
                                          _selectionPoints.add(paperPos);
                                        });
                                        return;
                                      }

                                      if (!_isDrawing) return;

                                      final rawPt = DrawingStrokePoint(
                                        x: paperPos.dx,
                                        y: paperPos.dy,
                                        pressure: _pointerPressure,
                                        tilt: _pointerTilt,
                                        timestamp: DateTime.now()
                                            .millisecondsSinceEpoch,
                                      );
                                      final stabilized = _stabilizer.addPoint(
                                        rawPt,
                                      );
                                      setState(
                                        () => _activePoints.add(stabilized),
                                      );
                                    },
                                    onPanEnd: (details) {
                                      _isPanning = false;
                                      final currentState = ref.read(provider);

                                      if (currentState.activeTool ==
                                          StudioTool.itemSelection) {
                                        if (_isItemMarquee &&
                                            _itemMarqueeStart != null &&
                                            _itemMarqueeCurrent != null) {
                                          final marquee = Rect.fromPoints(
                                            _itemMarqueeStart!,
                                            _itemMarqueeCurrent!,
                                          );
                                          if (marquee.width > 2 &&
                                              marquee.height > 2) {
                                            final references =
                                                FocusStudioItemCatalog.editable(
                                                      currentState.payload,
                                                    )
                                                    .where(
                                                      (entry) =>
                                                          FocusStudioItemGeometry.intersectsMarquee(
                                                            entry.item,
                                                            marquee,
                                                          ),
                                                    )
                                                    .map(
                                                      (entry) =>
                                                          entry.reference,
                                                    );
                                            notifier.selectItems(
                                              references,
                                              additive: _itemGestureAdditive,
                                            );
                                          }
                                        }
                                        _finishItemGesture(notifier);
                                        setState(() {});
                                        return;
                                      }

                                      if (_isTransforming) {
                                        final bounds = _transformBounds;
                                        final start = _transformStartPos;
                                        final end = _transformCurrentPos;
                                        if (bounds != null &&
                                            start != null &&
                                            end != null) {
                                          final translation = end - start;
                                          final current =
                                              currentState.selection ??
                                              SelectionMask(
                                                toolType:
                                                    SelectionToolType.rectangle,
                                                boundingBox: bounds,
                                              );
                                          final changed = notifier
                                              .applyRasterOperation(
                                                RasterEditOperation.transform(
                                                  bounds: bounds,
                                                  translation: translation,
                                                  selection: current,
                                                ),
                                              );
                                          if (changed > 0) {
                                            notifier.setSelection(
                                              current.copyWith(
                                                outlinePoints: current
                                                    .outlinePoints
                                                    .map(
                                                      (point) =>
                                                          point + translation,
                                                    )
                                                    .toList(),
                                                boundingBox: current.boundingBox
                                                    ?.shift(translation),
                                              ),
                                            );
                                          }
                                        }
                                        _isTransforming = false;
                                        _transformStartPos = null;
                                        _transformCurrentPos = null;
                                        _transformBounds = null;
                                        setState(() {});
                                        return;
                                      }

                                      if (_isSelecting &&
                                          _selectionPoints.length >= 2) {
                                        _isSelecting = false;
                                        final selectionTool =
                                            currentState.activeSelectionTool;
                                        final selectionPoints =
                                            selectionTool ==
                                                    SelectionToolType
                                                        .rectangle ||
                                                selectionTool ==
                                                    SelectionToolType.ellipse
                                            ? const <Offset>[]
                                            : List.of(_selectionPoints);
                                        notifier.setSelection(
                                          SelectionMask(
                                            toolType: selectionTool,
                                            outlinePoints: selectionPoints,
                                            boundingBox: SelectionMask.boundsOf(
                                              _selectionPoints,
                                            ),
                                          ),
                                        );
                                        setState(
                                          () => _selectionPoints.clear(),
                                        );
                                        return;
                                      }

                                      if (_shapeStartPos != null) {
                                        final rawWorkspacePos =
                                            _screenToWorkspaceCoord(
                                              details.localPosition,
                                              viewportSize,
                                              currentState,
                                            );
                                        final gesturePage =
                                            _pageById(_gesturePageId) ??
                                            _activePage;
                                        final rawPaperPos =
                                            rawWorkspacePos -
                                            gesturePage.position;
                                        final paperPos = Offset(
                                          rawPaperPos.dx
                                              .clamp(
                                                0.0,
                                                currentState.payload.pixelWidth,
                                              )
                                              .toDouble(),
                                          rawPaperPos.dy
                                              .clamp(
                                                0.0,
                                                currentState
                                                    .payload
                                                    .pixelHeight,
                                              )
                                              .toDouble(),
                                        );
                                        final start = _shapeStartPos!;
                                        final bounds = Rect.fromPoints(
                                          start,
                                          paperPos,
                                        );
                                        switch (currentState.activeTool) {
                                          case StudioTool.shapes:
                                            notifier.addShapeToActiveLayer(
                                              VectorShapeObject(
                                                id: 'shape_${DateTime.now().microsecondsSinceEpoch}',
                                                kind: currentState
                                                    .activeShapeKind,
                                                points: [start, paperPos],
                                                fill:
                                                    currentState.shapeFillColor,
                                                stroke: currentState
                                                    .shapeStrokeColor,
                                                strokeWidth: currentState
                                                    .shapeStrokeWidth,
                                                toneType: currentState
                                                    .activeScreenTone,
                                                toneFrequency: currentState
                                                    .screenToneFrequency,
                                                toneAngle: currentState
                                                    .screenToneAngle,
                                              ),
                                            );
                                            break;
                                          case StudioTool.ruler:
                                            final ruler = switch (currentState
                                                .activeRulerType) {
                                              RulerType.straight => RulerGuide(
                                                id: 'ruler_${DateTime.now().microsecondsSinceEpoch}',
                                                type: RulerType.straight,
                                                origin: start,
                                                target: paperPos,
                                              ),
                                              RulerType.circular => RulerGuide(
                                                id: 'ruler_${DateTime.now().microsecondsSinceEpoch}',
                                                type: RulerType.circular,
                                                origin: start,
                                                radius:
                                                    (paperPos - start).distance,
                                              ),
                                              RulerType.radialFocus => RulerGuide(
                                                id: 'ruler_${DateTime.now().microsecondsSinceEpoch}',
                                                type: RulerType.radialFocus,
                                                origin: start,
                                                target: paperPos,
                                              ),
                                              RulerType.symmetryMirror =>
                                                RulerGuide(
                                                  id: 'ruler_${DateTime.now().microsecondsSinceEpoch}',
                                                  type:
                                                      RulerType.symmetryMirror,
                                                  origin: start,
                                                  target: paperPos,
                                                ),
                                              RulerType.perspective1Point =>
                                                RulerGuide(
                                                  id: 'ruler_${DateTime.now().microsecondsSinceEpoch}',
                                                  type: RulerType
                                                      .perspective1Point,
                                                  origin: start,
                                                  target: paperPos,
                                                  vanishingPoints: [start],
                                                ),
                                              RulerType.perspective2Point =>
                                                RulerGuide(
                                                  id: 'ruler_${DateTime.now().microsecondsSinceEpoch}',
                                                  type: RulerType
                                                      .perspective2Point,
                                                  origin: start,
                                                  target: paperPos,
                                                  vanishingPoints: [
                                                    start,
                                                    paperPos,
                                                  ],
                                                ),
                                              RulerType.perspective3Point =>
                                                RulerGuide(
                                                  id: 'ruler_${DateTime.now().microsecondsSinceEpoch}',
                                                  type: RulerType
                                                      .perspective3Point,
                                                  origin: start,
                                                  target: paperPos,
                                                  vanishingPoints: [
                                                    start,
                                                    paperPos,
                                                    bounds.center,
                                                  ],
                                                ),
                                            };
                                            notifier.addRuler(ruler);
                                            break;
                                          case StudioTool.mangaPanel:
                                            if (bounds.width >= 8 &&
                                                bounds.height >= 8) {
                                              notifier.addMangaPanel(
                                                MangaPanelCut(
                                                  id: 'panel_${DateTime.now().microsecondsSinceEpoch}',
                                                  rect: bounds,
                                                  borderWidth: currentState
                                                      .shapeStrokeWidth,
                                                  borderColor: currentState
                                                      .shapeStrokeColor,
                                                ),
                                              );
                                            }
                                            break;
                                          case StudioTool.speechBalloon:
                                            if (bounds.width >= 8 &&
                                                bounds.height >= 8) {
                                              notifier.addSpeechBalloon(
                                                SpeechBalloon(
                                                  id: 'balloon_${DateTime.now().microsecondsSinceEpoch}',
                                                  position: bounds.topLeft,
                                                  size: bounds.size,
                                                  tailTarget: Offset(
                                                    bounds.center.dx,
                                                    min(
                                                      currentState
                                                          .payload
                                                          .pixelHeight,
                                                      bounds.bottom + 32,
                                                    ),
                                                  ),
                                                  type: currentState
                                                      .activeBalloonType,
                                                  fontSize: currentState
                                                      .activeFontSize,
                                                  textColor:
                                                      currentState.primaryColor,
                                                  borderColor: currentState
                                                      .shapeStrokeColor,
                                                ),
                                              );
                                            }
                                            break;
                                          default:
                                            break;
                                        }
                                        _shapeStartPos = null;
                                        return;
                                      }

                                      if (!_isDrawing) return;
                                      _isDrawing = false;

                                      if (currentState.activeTool ==
                                              StudioTool.smudge ||
                                          currentState.activeTool ==
                                              StudioTool.blur) {
                                        if (_activePoints.isNotEmpty) {
                                          final effectPoints = _activePoints
                                              .map((point) => point.offset)
                                              .toList();
                                          final operation =
                                              currentState.activeTool ==
                                                  StudioTool.smudge
                                              ? RasterEditOperation.smudge(
                                                  points: effectPoints,
                                                  radius:
                                                      currentState.brushSize,
                                                  strength:
                                                      currentState.brushOpacity,
                                                  selection:
                                                      currentState.selection,
                                                )
                                              : RasterEditOperation.blur(
                                                  points: effectPoints,
                                                  radius:
                                                      currentState.brushSize,
                                                  strength:
                                                      currentState.brushOpacity,
                                                  selection:
                                                      currentState.selection,
                                                );
                                          notifier.applyRasterOperation(
                                            operation,
                                          );
                                        }
                                        setState(() => _activePoints.clear());
                                        return;
                                      }

                                      if (_activePoints.length >= 2) {
                                        final finalPoints =
                                            currentState.enableTaper
                                            ? StrokeStabilizer.applyTaper(
                                                _activePoints,
                                              )
                                            : List<DrawingStrokePoint>.from(
                                                _activePoints,
                                              );

                                        final newStroke = DrawingStroke(
                                          id: 'stroke_${DateTime.now().microsecondsSinceEpoch}',
                                          brush: currentState.activeBrush,
                                          color: currentState.primaryColor,
                                          size: currentState.brushSize,
                                          opacity: currentState.brushOpacity,
                                          points: finalPoints,
                                          isEraser:
                                              currentState.activeTool ==
                                                  StudioTool.eraser ||
                                              currentState.activeBrush.name
                                                  .contains('eraser'),
                                          toneType:
                                              currentState.activeScreenTone,
                                          toneFrequency:
                                              currentState.screenToneFrequency,
                                          toneAngle:
                                              currentState.screenToneAngle,
                                        );
                                        notifier.addStrokeToActiveLayer(
                                          newStroke,
                                        );
                                      }
                                      setState(() => _activePoints.clear());
                                    },
                                    onTapUp: (details) => _handleTapUp(
                                      details,
                                      viewportSize,
                                      state,
                                      notifier,
                                    ),
                                    child: MouseRegion(
                                      key: const ValueKey(
                                        'drawing-studio-pointer-surface',
                                      ),
                                      cursor:
                                          _usesCustomBrushCursor(
                                            state.activeTool,
                                          )
                                          ? SystemMouseCursors.none
                                          : MouseCursor.defer,
                                      onHover: (event) => _updateBrushCursor(
                                        event.localPosition,
                                        state,
                                      ),
                                      onExit: (_) => _clearBrushCursor(),
                                      child: ClipRect(
                                        child: CustomPaint(
                                          size: Size.infinite,
                                          painter: StudioWorkspacePainter(
                                            pages: _pages
                                                .map(
                                                  (
                                                    page,
                                                  ) => StudioPageRenderData(
                                                    page:
                                                        page.id == _activePageId
                                                        ? page.copyWith(
                                                            payload:
                                                                state.payload,
                                                          )
                                                        : page,
                                                    rasterImage:
                                                        _rasterImages[page.id],
                                                    rasterImageScale:
                                                        _rasterImageScales[page
                                                            .id] ??
                                                        1.0,
                                                  ),
                                                )
                                                .toList(),
                                            activePageId: _activePageId,
                                            workspaceCenter:
                                                _workspaceBounds().center,
                                            activePoints: _activePoints,
                                            activeBrush: state.activeBrush,
                                            activeColor: state.primaryColor,
                                            activeSize: state.brushSize,
                                            activeOpacity: state.brushOpacity,
                                            isEraser:
                                                state.activeTool ==
                                                StudioTool.eraser,
                                            selection: state.selection,
                                            selectedItems:
                                                notifier.selectedItemEntries,
                                            itemMarquee:
                                                _itemMarqueeStart != null &&
                                                    _itemMarqueeCurrent != null
                                                ? Rect.fromPoints(
                                                    _itemMarqueeStart!,
                                                    _itemMarqueeCurrent!,
                                                  )
                                                : null,
                                            rulers: state.rulers,
                                            zoom: state.viewZoom,
                                            rotation: state.viewRotation,
                                            pan: state.viewPan,
                                            activeLayerIndex:
                                                state.activeLayerIndex,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                IgnorePointer(
                                  child: CustomPaint(
                                    size: Size.infinite,
                                    painter: StudioBrushCursorPainter(
                                      position:
                                          _usesCustomBrushCursor(
                                            state.activeTool,
                                          )
                                          ? (_brushCursorPosition ??
                                                _lastPointerPosition)
                                          : null,
                                      brush: state.activeBrush,
                                      tool: state.activeTool,
                                      color: state.primaryColor,
                                      brushSize: state.brushSize,
                                      zoom: state.viewZoom,
                                    ),
                                  ),
                                ),
                                ..._buildPageControls(
                                  viewportSize,
                                  state,
                                  notifier,
                                ),
                                if (_editingTextObject != null)
                                  _buildInlineTextEditor(
                                    _editingTextObject!,
                                    viewportSize,
                                    state,
                                    notifier,
                                  ),
                                if (_editingBalloon != null)
                                  _buildInlineBalloonEditor(
                                    _editingBalloon!,
                                    viewportSize,
                                    state,
                                    notifier,
                                  ),
                              ],
                            );
                          },
                        ),
                      ),

                      // Right Panel: Color Studio + Layers
                      if (MediaQuery.sizeOf(context).width >=
                          AppBreakpoints.medium) ...[
                        StudioColorPanel(initialPayload: widget.initialPayload),
                        StudioLayerPanel(initialPayload: widget.initialPayload),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // Reference PiP floating overlay on top of the canvas
            ReferenceWindowView(initialPayload: widget.initialPayload),
          ],
        ),
      ),
    );
  }
}
