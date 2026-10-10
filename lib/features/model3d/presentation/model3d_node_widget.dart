import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:three_js/three_js.dart' as three;

import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../../domain/models/durable_asset_reference.dart';
import '../../../domain/models/model3d_payload.dart';
import '../../../domain/models/model3d_studio.dart';
import '../data/model3d_artifact_store.dart';
import '../data/model3d_glb_compatibility.dart';
import '../data/model3d_renderer_capability.dart';
import '../data/model3d_texture_upload.dart';
import 'model3d_control_button.dart';
import 'model3d_preview.dart';
import 'model3d_rendering.dart';
import '../../export/export_service.dart';

@visibleForTesting
bool model3DViewerNeedsRestart({
  required bool sourceChanged,
  required bool retryChanged,
  required bool sizeChanged,
}) => sourceChanged || retryChanged || sizeChanged;

@visibleForTesting
bool model3DViewerShouldStartTicker({
  required bool enabled,
  required bool isActive,
}) => enabled && !isActive;

@visibleForTesting
int model3DViewerClearColor(Color color) => color.toARGB32() & 0x00FFFFFF;

@visibleForTesting
three.Settings model3DViewerSettings({
  required int clearColor,
  required double clearAlpha,
  bool animate = true,
}) => three.Settings(
  // Alpha is enabled from the first frame. Changing only clearAlpha later
  // keeps the ANGLE/D3D11 surface stable during selection changes.
  alpha: true,
  clearColor: clearColor,
  clearAlpha: clearAlpha,
  premultipliedAlpha: false,
  // Keep the ANGLE D3D surface producer so the renderer and Flutter share the
  // same surface without cross-context FBO attachments.
  useSurfaceProducer: true,
  // Keep the ANGLE surface configuration stable while selection toggles only
  // interaction and animation state.
  antialias: true,
  enableShadowMap: false,
  animate: animate,
  screenResolution: null,
  toneMapping: three.ACESFilmicToneMapping,
  toneMappingExposure: 1.1,
);

@visibleForTesting
List<three.Object3D> model3DStudioLights([
  Model3DLightingPreset preset = Model3DLightingPreset.studio,
]) {
  final profile = switch (preset) {
    Model3DLightingPreset.studio => (0xFFF4E6, 2.6, 1.4, 1.2, 1.8),
    Model3DLightingPreset.neutral => (0xFFFFFF, 1.8, 1.2, 0.9, 1.0),
    Model3DLightingPreset.dramatic => (0xFFFFD1, 3.0, 0.55, 0.65, 2.5),
    Model3DLightingPreset.flat => (0xFFFFFF, 0.8, 0.8, 0.8, 0.4),
  };
  final keyLight = three.DirectionalLight(profile.$1, profile.$2)
    ..position.setValues(4, 6, 5);
  final fillLight = three.DirectionalLight(0xD9ECFF, profile.$3)
    ..position.setValues(-4, 2, 4);
  final frontLight = three.DirectionalLight(0xFFFFFF, profile.$4)
    ..position.setValues(0, 1, 6);
  final rimLight = three.DirectionalLight(0xFFFFFF, profile.$5)
    ..position.setValues(-3, 4, -4);

  return [
    three.HemisphereLight(0xF8FAFC, 0x1E293B, 1.1),
    three.AmbientLight(0xFFFFFF, 0.55),
    keyLight,
    fillLight,
    frontLight,
    rimLight,
  ];
}

class Model3DNodeWidget extends StatefulWidget {
  final Model3DPayload payload;
  final bool readOnly;
  final bool canMove;
  final bool selected;
  final bool interactive;
  final double width;
  final double height;
  final Color canvasColor;
  final Color panelColor;
  final Color borderColor;
  final Color textColor;
  final Color mutedColor;
  final int resetCommand;
  final int retryCommand;
  final ValueChanged<Offset>? onDragDelta;
  final VoidCallback? onSelect;
  final ValueChanged<Offset>? onSecondaryTap;
  final ValueChanged<bool>? onAutoRotateChanged;
  final ValueChanged<Model3DCameraBookmark>? onCameraBookmarkCaptured;
  final Future<void> Function(Uint8List bytes, int width, int height)?
  onSnapshotCaptured;
  @visibleForTesting
  final bool? nativeRendererAvailableOverride;
  final Model3DArtifactStore? artifactStore;

  const Model3DNodeWidget({
    required this.payload,
    required this.readOnly,
    required this.canMove,
    required this.selected,
    this.interactive = true,
    required this.width,
    required this.height,
    required this.canvasColor,
    required this.panelColor,
    required this.borderColor,
    required this.textColor,
    required this.mutedColor,
    this.resetCommand = 0,
    this.retryCommand = 0,
    this.onDragDelta,
    this.onSelect,
    this.onSecondaryTap,
    this.onAutoRotateChanged,
    this.onCameraBookmarkCaptured,
    this.onSnapshotCaptured,
    this.nativeRendererAvailableOverride,
    this.artifactStore,
    super.key,
  });

  @override
  State<Model3DNodeWidget> createState() => _Model3DNodeWidgetState();
}

class _Model3DNodeWidgetState extends State<Model3DNodeWidget> {
  three.ThreeJS? _viewer;
  three.GLTFLoader? _loader;
  three.Object3D? _model;
  three.OrbitControls? _controls;
  three.AnimationMixer? _mixer;
  final Map<three.ThreeJS, Model3DArtifact> _hydratedArtifacts = {};
  late final Model3DArtifactStore _artifactStore;
  Timer? _restartTimer;
  Timer? _rendererStartupTimer;
  Timer? _annotationRefreshTimer;
  final GlobalKey _snapshotBoundaryKey = GlobalKey();
  String? _error;
  late bool _autoRotate;
  bool _isReady = false;
  bool _disposed = false;
  bool _restartQueued = false;
  bool _hardwareKeyHandlerRegistered = false;
  final Set<int> _shiftPanPointers = {};
  final Model3DScenePresentation _presentation = Model3DScenePresentation();
  final Model3DTextureUploadRepair _textureUploadRepair =
      Model3DTextureUploadRepair();

  bool get _viewerInteractionEnabled =>
      widget.interactive &&
      widget.payload.viewportMode != Model3DViewportMode.twoD;

  bool _isShiftPressed() =>
      HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.shiftLeft,
      ) ||
      HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.shiftRight,
      );

  void _setLeftMouseAction(int action) {
    _controls?.mouseButtons['left'] = action;
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.shiftLeft &&
        event.logicalKey != LogicalKeyboardKey.shiftRight) {
      return false;
    }
    if (event is KeyUpEvent) {
      scheduleMicrotask(() {
        if (!_disposed && mounted && !_isShiftPressed()) {
          _setLeftMouseAction(three.Mouse.rotate);
        }
      });
    } else {
      _setLeftMouseAction(three.Mouse.pan);
    }
    return false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    widget.onSelect?.call();
    final controls = _controls;
    if (controls == null ||
        event.kind != PointerDeviceKind.mouse ||
        (event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }
    if (_isShiftPressed()) {
      _shiftPanPointers.add(event.pointer);
      controls.mouseButtons['left'] = three.Mouse.pan;
    } else if (_shiftPanPointers.isEmpty) {
      // Recover from a browser that did not deliver the Shift key-up event.
      controls.mouseButtons['left'] = three.Mouse.rotate;
    }
  }

  void _handlePointerUp(PointerEvent event) {
    if (!_shiftPanPointers.remove(event.pointer) ||
        _shiftPanPointers.isNotEmpty ||
        _isShiftPressed()) {
      return;
    }
    _setLeftMouseAction(three.Mouse.rotate);
  }

  void _setHardwareKeyHandling(bool enabled) {
    if (enabled && !_hardwareKeyHandlerRegistered) {
      HardwareKeyboard.instance.addHandler(_handleHardwareKey);
      _hardwareKeyHandlerRegistered = true;
    } else if (!enabled && _hardwareKeyHandlerRegistered) {
      HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
      _hardwareKeyHandlerRegistered = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _artifactStore = widget.artifactStore ?? createModel3DArtifactStore();
    _autoRotate = widget.payload.autoRotate;
    _setHardwareKeyHandling(_viewerInteractionEnabled);
    _initializeViewer();
  }

  void _queueViewerRestart() {
    if (_disposed || _restartQueued) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 300), () {
      _restartTimer = null;
      if (_disposed || _restartQueued || !mounted) return;
      _restartQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restartQueued = false;
        if (_disposed || !mounted) return;
        _restartViewer();
      });
    });
  }

  @override
  void didUpdateWidget(covariant Model3DNodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPayload = oldWidget.payload;
    final payload = widget.payload;
    final sourceChanged =
        oldPayload.storagePath != payload.storagePath ||
        oldPayload.modelPath != payload.modelPath ||
        oldPayload.modelUrl != payload.modelUrl ||
        oldPayload.artifactReference != payload.artifactReference;
    final sizeChanged =
        oldWidget.width != widget.width || oldWidget.height != widget.height;
    final autoRotateChanged = oldPayload.autoRotate != payload.autoRotate;
    final interactionChanged =
        oldWidget.interactive != widget.interactive ||
        oldPayload.viewportMode != payload.viewportMode;
    final presentationChanged =
        oldPayload.renderMode != payload.renderMode ||
        oldPayload.materialChannel != payload.materialChannel ||
        oldPayload.geometryMode != payload.geometryMode ||
        oldPayload.inspectorSelection != payload.inspectorSelection ||
        oldPayload.wireframeColor != payload.wireframeColor ||
        oldPayload.doubleSided != payload.doubleSided ||
        oldPayload.uvChecker != payload.uvChecker;
    final transparentChanged =
        oldPayload.transparentBackground != payload.transparentBackground;
    final canvasColorChanged = oldWidget.canvasColor != widget.canvasColor;
    if (autoRotateChanged) {
      _autoRotate = payload.autoRotate;
    }
    if (interactionChanged) {
      final enabled = _viewerInteractionEnabled;
      _setHardwareKeyHandling(enabled);
      _controls?.enabled = enabled;
      _controls?.autoRotate = enabled && _autoRotate;
      final ticker = _viewer?.ticker;
      if (ticker != null &&
          model3DViewerShouldStartTicker(
            enabled: enabled,
            isActive: ticker.isActive,
          )) {
        ticker.start();
      } else if (!enabled && ticker?.isActive == true) {
        ticker!.stop();
      }
    } else if (autoRotateChanged) {
      _controls?.autoRotate = _viewerInteractionEnabled && _autoRotate;
    }
    final needsRestart = model3DViewerNeedsRestart(
      sourceChanged: sourceChanged,
      retryChanged: oldWidget.retryCommand != widget.retryCommand,
      sizeChanged: sizeChanged,
    );
    if (needsRestart) {
      _queueViewerRestart();
      return;
    }
    if (oldWidget.resetCommand != widget.resetCommand) {
      _resetView();
    }
    if (needsRestart) return;
    if (_model != null && (presentationChanged || canvasColorChanged)) {
      _presentation.apply(
        _model!,
        payload,
        canvasColor: model3DViewerClearColor(widget.canvasColor),
        angleSafe: _textureUploadRepair.isSupported,
      );
      _textureUploadRepair.attach(_model!);
      if (mounted) setState(() {});
    }
    if (transparentChanged || canvasColorChanged) {
      _updateClearState();
    }
    if (presentationChanged || transparentChanged || canvasColorChanged) {
      unawaited(_renderViewer());
    }
  }

  Future<void> _renderViewer() async {
    final viewer = _viewer;
    if (viewer == null || _disposed || !mounted || viewer.renderer == null) {
      return;
    }
    try {
      await viewer.render();
    } catch (error) {
      if (!_disposed) {
        debugPrint('[Model3DNodeWidget] Render update failed: $error');
      }
    }
  }

  void _updateClearState() {
    final viewer = _viewer;
    if (viewer == null) return;
    final clearColor = model3DViewerClearColor(widget.canvasColor);
    final alpha = widget.payload.transparentBackground ? 0.0 : 1.0;
    viewer.settings
      ..clearColor = clearColor
      ..clearAlpha = alpha;
    viewer.renderer?.setClearColor(three.Color.fromHex32(clearColor), alpha);
  }

  void _initializeViewer() {
    if (!widget.payload.hasSource) {
      final sourceError = widget.payload.sourceError?.trim();
      _error = sourceError?.isNotEmpty == true
          ? sourceError
          : 'GLB artifact is unavailable.';
      return;
    }
    if (widget.payload.hasStorageOnlySource) {
      _error =
          'This GLB is stored in private project storage and needs materialization before preview. Retry when the project storage is available.';
      return;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      _error = 'Interactive 3D preview is unavailable on this Linux renderer.';
      return;
    }

    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final nativeRendererAvailable =
        widget.nativeRendererAvailableOverride ??
        nativeModel3DRendererAvailable();
    final rendererFallback = model3DRendererFallbackMessage(
      isAndroid: isAndroid,
      nativeRendererAvailable: nativeRendererAvailable,
    );
    if (shouldSkipModel3DRenderer(
      isAndroid: isAndroid,
      nativeRendererAvailable: nativeRendererAvailable,
    )) {
      _error = rendererFallback;
      return;
    }

    try {
      late final three.ThreeJS viewer;
      viewer = three.ThreeJS(
        size: Size(math.max(1, widget.width), math.max(1, widget.height)),
        settings: model3DViewerSettings(
          clearColor: model3DViewerClearColor(widget.canvasColor),
          clearAlpha: widget.payload.transparentBackground ? 0.0 : 1.0,
          animate: _viewerInteractionEnabled,
        ),
        onSetupComplete: () => _onSetupComplete(viewer),
        setup: () => _setupViewer(viewer),
      );
      _viewer = viewer;
      _armRendererStartupTimeout(viewer);
    } catch (error) {
      _setError(_friendlyError(error));
    }
  }

  void _armRendererStartupTimeout(three.ThreeJS viewer) {
    _rendererStartupTimer?.cancel();
    _rendererStartupTimer = Timer(const Duration(seconds: 3), () {
      _rendererStartupTimer = null;
      if (_disposed ||
          !mounted ||
          _viewer != viewer ||
          _isReady ||
          _error != null) {
        return;
      }
      _disposeViewer();
      _setError(
        'Interactive 3D preview could not start. The project library remains usable. Retry preview.',
      );
    });
  }

  Future<void> _setupViewer(three.ThreeJS viewer) async {
    if (_disposed || _viewer != viewer) return;

    final loader = three.GLTFLoader(flipY: true);
    _loader = loader;
    try {
      viewer.camera = three.PerspectiveCamera(
        42,
        math.max(0.01, widget.width) / math.max(0.01, widget.height),
        0.01,
        1000,
      );
      viewer.scene = three.Scene();

      for (final light in model3DStudioLights(widget.payload.lightingPreset)) {
        viewer.scene.add(light);
      }

      final data = await _loadModel(loader, viewer);
      if (_disposed || _viewer != viewer || !mounted) {
        _releaseHydratedArtifactFor(viewer);
        loader.dispose();
        return;
      }
      if (data == null) {
        throw StateError('The GLB model could not be loaded.');
      }
      _model = data.scene;
      _normalizeModel(_model!);
      viewer.scene.add(_model!);
      _presentation.apply(
        _model!,
        widget.payload,
        canvasColor: model3DViewerClearColor(widget.canvasColor),
        angleSafe: _textureUploadRepair.isSupported,
      );
      // ANGLE's Windows typed-data texture dispatch drops CPU uploads. Keep
      // this repair at the texture boundary so the normal renderer remains
      // unchanged on platforms with working typed-data bindings.
      _textureUploadRepair.attach(_model!);

      viewer.camera.position.setValues(0, 0.35, 3.2);
      viewer.camera.lookAt(three.Vector3(0, 0, 0));
      final controls = three.OrbitControls(viewer.camera, viewer.globalKey)
        ..enabled = _viewerInteractionEnabled
        ..enableDamping = true
        ..dampingFactor = 0.08
        ..enablePan = true
        ..panSpeed = 0.9
        ..keyPanSpeed = 12.0
        ..minDistance = 0.6
        ..maxDistance = 20
        ..autoRotate = _viewerInteractionEnabled && _autoRotate
        ..autoRotateSpeed = 1.4;
      _controls = controls;
      final bookmark = widget.payload.cameraBookmarks
          .where((item) => item.id == widget.payload.activeCameraBookmarkId)
          .firstOrNull;
      if (bookmark != null) {
        viewer.camera.position.setValues(
          bookmark.positionX,
          bookmark.positionY,
          bookmark.positionZ,
        );
        viewer.camera.lookAt(
          three.Vector3(bookmark.targetX, bookmark.targetY, bookmark.targetZ),
        );
        controls.update();
      }
      if (_isShiftPressed()) {
        controls.mouseButtons['left'] = three.Mouse.pan;
      }

      final animations = data.animations ?? const [];
      if (animations.isNotEmpty) {
        final mixer = three.AnimationMixer(_model!);
        for (final animation in animations) {
          final action = mixer.clipAction(animation as three.AnimationClip);
          action?.play();
        }
        _mixer = mixer;
      }

      viewer.addAnimationEvent((dt) {
        if (_disposed || _viewer != viewer) return;
        _controls?.update();
        _mixer?.update(dt);
        _scheduleAnnotationRefresh();
      });
      if (!_viewerInteractionEnabled) {
        await viewer.render();
      }
    } catch (error) {
      if (_disposed || _viewer != viewer || !mounted) {
        _releaseHydratedArtifactFor(viewer);
        loader.dispose();
        return;
      }
      _setError(_friendlyError(error));
      loader.dispose();
      _loader = null;
    }
  }

  Future<three.GLTFData?> _loadNormalizedArtifact(
    three.GLTFLoader loader,
    Model3DArtifact artifact,
  ) async {
    final bytes = artifact.bytes ?? await _artifactStore.read(artifact);
    if (bytes == null || bytes.isEmpty) return null;
    return loader.fromBytes(normalizeModel3DGlbForThreeJs(bytes));
  }

  Future<three.GLTFData?> _loadModel(
    three.GLTFLoader loader,
    three.ThreeJS viewer,
  ) async {
    final reference = validModel3DArtifactReference(
      widget.payload.artifactReference,
    );
    if (reference == null) return null;

    final artifact = await _artifactStore.hydrate(
      reference,
      fileName: widget.payload.fileName,
    );
    if (artifact == null) return null;
    _hydratedArtifacts[viewer] = artifact;
    final data = await _loadNormalizedArtifact(loader, artifact);
    if (data != null) return data;
    _releaseHydratedArtifactFor(viewer);
    return null;
  }

  void _normalizeModel(three.Object3D model) {
    final bounds = three.BoundingBox()..setFromObject(model, true);
    if (bounds.isEmpty() ||
        !bounds.min.x.isFinite ||
        !bounds.max.x.isFinite ||
        !bounds.min.y.isFinite ||
        !bounds.max.y.isFinite ||
        !bounds.min.z.isFinite ||
        !bounds.max.z.isFinite) {
      model.position.setValues(0, 0, 0);
      model.scale.setValues(1, 1, 1);
      return;
    }

    final center = bounds.getCenter(three.Vector3());
    final extent = math.max(
      0.001,
      math.max(
        bounds.max.x - bounds.min.x,
        math.max(bounds.max.y - bounds.min.y, bounds.max.z - bounds.min.z),
      ),
    );
    final scale = 2.2 / extent;
    // Apply the scale before translating so the final world-space center stays
    // at the origin for models whose source coordinates are far from zero.
    model.scale.setValues(scale, scale, scale);
    model.position.setValues(
      -center.x * scale,
      -center.y * scale,
      -center.z * scale,
    );
    model.updateMatrixWorld(true);
  }

  void _onSetupComplete(three.ThreeJS viewer) {
    if (_disposed || _viewer != viewer || !mounted) return;
    _rendererStartupTimer?.cancel();
    _rendererStartupTimer = null;
    _updateClearState();
    if (!_viewerInteractionEnabled) _viewer?.ticker?.stop();
    setState(() => _isReady = true);
  }

  void _setError(String message) {
    if (_disposed) return;
    _rendererStartupTimer?.cancel();
    _rendererStartupTimer = null;
    _error = message;
    if (mounted) setState(() {});
  }

  String _friendlyError(Object error) {
    final value = error.toString().replaceFirst('Exception: ', '').trim();
    if (value.isEmpty) return 'Interactive 3D preview is unavailable.';
    return value.length > 180 ? '${value.substring(0, 177)}…' : value;
  }

  void _releaseHydratedArtifactFor(three.ThreeJS viewer) {
    final artifact = _hydratedArtifacts.remove(viewer);
    if (artifact != null) {
      unawaited(_artifactStore.dispose(artifact));
    }
  }

  void _releaseHydratedArtifacts() {
    for (final viewer in _hydratedArtifacts.keys.toList()) {
      _releaseHydratedArtifactFor(viewer);
    }
  }

  void _disposeThreeViewer(three.ThreeJS viewer) {
    try {
      viewer.dispose();
    } catch (error) {
      debugPrint('[Model3DNodeWidget] Viewer disposal failed: $error');
    }
  }

  void _restartViewer() {
    _disposeViewer();
    _disposed = false;
    _error = null;
    _isReady = false;
    _initializeViewer();
    if (mounted) setState(() {});
  }

  void _retry() => _queueViewerRestart();

  void _resetView() {
    _controls?.reset();
  }

  void _updateControls(void Function(three.OrbitControls) action) {
    final controls = _controls;
    if (controls == null) return;
    action(controls);
    controls.update();
  }

  void _zoomIn() =>
      _updateControls((controls) => controls.dollyIn(controls.getZoomScale));

  void _zoomOut() =>
      _updateControls((controls) => controls.dollyOut(controls.getZoomScale));

  void _panLeft() =>
      _updateControls((controls) => controls.pan(-controls.keyPanSpeed, 0));

  void _panRight() =>
      _updateControls((controls) => controls.pan(controls.keyPanSpeed, 0));

  void _panUp() =>
      _updateControls((controls) => controls.pan(0, -controls.keyPanSpeed));

  void _panDown() =>
      _updateControls((controls) => controls.pan(0, controls.keyPanSpeed));

  void _rotateLeft() =>
      _updateControls((controls) => controls.rotateLeft(math.pi / 18));

  void _rotateRight() =>
      _updateControls((controls) => controls.rotateLeft(-math.pi / 18));

  void _rotateUp() =>
      _updateControls((controls) => controls.rotateUp(-math.pi / 18));

  void _rotateDown() =>
      _updateControls((controls) => controls.rotateUp(math.pi / 18));

  void _toggleAutoRotate() {
    final next = !_autoRotate;
    _controls?.autoRotate = next;
    _controls?.update();
    if (mounted) setState(() => _autoRotate = next);
    widget.onAutoRotateChanged?.call(next);
  }

  void _captureCameraBookmark() {
    final camera = _viewer?.camera;
    if (camera == null) return;
    final target = _controls?.target ?? three.Vector3();
    widget.onCameraBookmarkCaptured?.call(
      Model3DCameraBookmark(
        id: 'camera-${DateTime.now().microsecondsSinceEpoch}',
        label: 'Captured camera',
        positionX: camera.position.x,
        positionY: camera.position.y,
        positionZ: camera.position.z,
        targetX: target.x,
        targetY: target.y,
        targetZ: target.z,
      ),
    );
  }

  Future<void> _captureSnapshot() async {
    final callback = widget.onSnapshotCaptured;
    if (callback == null) return;
    final renderObject = _snapshotBoundaryKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return;
    final bytes = await ExportService.capturePng(renderObject);
    if (bytes == null || bytes.isEmpty || !mounted) return;
    await callback(
      bytes,
      renderObject.size.width.round().clamp(1, 16_384),
      renderObject.size.height.round().clamp(1, 16_384),
    );
  }

  void _scheduleAnnotationRefresh() {
    if (_annotationRefreshTimer != null || !mounted) return;
    _annotationRefreshTimer = Timer(const Duration(milliseconds: 32), () {
      _annotationRefreshTimer = null;
      if (mounted) setState(() {});
    });
  }

  List<Widget> _buildAnnotationOverlays() {
    final viewer = _viewer;
    if (viewer == null || widget.payload.annotations.isEmpty) return const [];
    final camera = viewer.camera;
    final overlays = <Widget>[];
    for (final annotation in widget.payload.annotations) {
      if (!annotation.visible) continue;
      final projected = three.Vector3(
        annotation.x,
        annotation.y,
        annotation.z,
      ).project(camera);
      if (!projected.x.isFinite ||
          !projected.y.isFinite ||
          !projected.z.isFinite ||
          projected.z < -1 ||
          projected.z > 1) {
        continue;
      }
      final left = ((projected.x + 1) / 2) * widget.width;
      final top = ((1 - projected.y) / 2) * widget.height;
      if (!left.isFinite || !top.isFinite) continue;
      overlays.add(
        Positioned(
          left: left.clamp(0, math.max(0, widget.width - 12)),
          top: top.clamp(0, math.max(0, widget.height - 12)),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(annotation.colorArgb).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: widget.panelColor),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                child: Text(
                  annotation.text.isEmpty ? annotation.label : annotation.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.textColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return overlays;
  }

  Widget _buildControlDock() {
    final tokens = context.appTokens;
    Widget row(List<Widget> children) => Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      children: children,
    );

    return Positioned(
      top: AppSpacing.xl + AppSpacing.sm + AppSpacing.xxs,
      right: AppSpacing.xs + AppSpacing.xxs,
      bottom: AppSpacing.xs + AppSpacing.xxs,
      left: AppSpacing.xs + AppSpacing.xxs,
      child: Align(
        alignment: Alignment.topRight,
        child: SingleChildScrollView(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.panelColor.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(tokens.controlRadius),
              border: Border.all(
                color: widget.borderColor.withValues(alpha: 0.55),
              ),
              boxShadow: [
                BoxShadow(
                  color: tokens.raisedShadow,
                  offset: const Offset(
                    AppElevation.controlOffset,
                    AppElevation.controlOffset,
                  ),
                  blurRadius: AppElevation.controlBlur,
                ),
                BoxShadow(
                  color: tokens.pressedShadow,
                  offset: const Offset(
                    -AppElevation.controlOffset,
                    -AppElevation.controlOffset,
                  ),
                  blurRadius: AppElevation.controlBlur,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  row([
                    _buildModel3DControlButton(
                      icon: Icons.rotate_left,
                      tooltip: 'Orbit left',
                      onPressed: _rotateLeft,
                    ),
                    _buildModel3DControlButton(
                      icon: Icons.rotate_right,
                      tooltip: 'Orbit right',
                      onPressed: _rotateRight,
                    ),
                    _buildModel3DControlButton(
                      icon: Icons.keyboard_arrow_up,
                      tooltip: 'Orbit up',
                      onPressed: _rotateUp,
                    ),
                    _buildModel3DControlButton(
                      icon: Icons.keyboard_arrow_down,
                      tooltip: 'Orbit down',
                      onPressed: _rotateDown,
                    ),
                    _buildModel3DControlButton(
                      icon: Icons.center_focus_strong,
                      tooltip: 'Reset 3D view',
                      onPressed: _resetView,
                    ),
                    _buildModel3DControlButton(
                      icon: _autoRotate
                          ? Icons.sync
                          : Icons.sync_disabled_outlined,
                      tooltip: _autoRotate
                          ? 'Disable auto-rotate'
                          : 'Enable auto-rotate',
                      onPressed: _toggleAutoRotate,
                    ),
                    _buildModel3DControlButton(
                      icon: Icons.bookmark_add_outlined,
                      tooltip: 'Capture camera bookmark',
                      onPressed: _captureCameraBookmark,
                    ),
                    _buildModel3DControlButton(
                      icon: Icons.camera_alt_outlined,
                      tooltip: 'Capture 3D snapshot',
                      onPressed: _captureSnapshot,
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.xxs),
                  row([
                    _buildModel3DControlButton(
                      icon: Icons.zoom_out,
                      tooltip: 'Zoom out',
                      onPressed: _zoomOut,
                    ),
                    _buildModel3DControlButton(
                      icon: Icons.zoom_in,
                      tooltip: 'Zoom in',
                      onPressed: _zoomIn,
                    ),
                    _buildModel3DControlButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Pan left',
                      onPressed: _panLeft,
                    ),
                    _buildModel3DControlButton(
                      icon: Icons.arrow_forward,
                      tooltip: 'Pan right',
                      onPressed: _panRight,
                    ),
                    _buildModel3DControlButton(
                      icon: Icons.arrow_upward,
                      tooltip: 'Pan up',
                      onPressed: _panUp,
                    ),
                    _buildModel3DControlButton(
                      icon: Icons.arrow_downward,
                      tooltip: 'Pan down',
                      onPressed: _panDown,
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _disposeViewer() {
    _shiftPanPointers.clear();
    _restartTimer?.cancel();
    _restartTimer = null;
    _rendererStartupTimer?.cancel();
    _rendererStartupTimer = null;
    _annotationRefreshTimer?.cancel();
    _annotationRefreshTimer = null;
    _controls?.dispose();
    _controls = null;
    _mixer?.stopAllAction();
    if (_mixer != null && _model != null) {
      _mixer!.uncacheRoot(_model!);
    }
    _mixer = null;
    _loader?.dispose();
    _loader = null;
    _textureUploadRepair.dispose();
    _presentation.dispose();
    _model = null;
    final viewer = _viewer;
    _viewer = null;
    if (viewer != null) {
      _releaseHydratedArtifactFor(viewer);
      _disposeThreeViewer(viewer);
    }
    _releaseHydratedArtifacts();
  }

  @override
  void dispose() {
    _disposed = true;
    _setHardwareKeyHandling(false);
    _disposeViewer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewer = _viewer;
    final transparent = widget.payload.transparentBackground;
    final fallback = _error != null || viewer == null
        ? Model3DFallbackCard(
            payload: widget.payload,
            error: _error,
            selected: widget.selected,
            canvasColor: widget.canvasColor,
            panelColor: transparent ? Colors.transparent : widget.panelColor,
            borderColor: widget.borderColor,
            textColor: widget.textColor,
            mutedColor: widget.mutedColor,
            onSelect: widget.onSelect,
            onDragDelta: null,
            onSecondaryTap: widget.onSecondaryTap,
            onRetry: _retry,
          )
        : viewer.build();
    final livePreview = viewer != null && _error == null
        ? GestureDetector(
            onSecondaryTapUp: (details) =>
                widget.onSecondaryTap?.call(details.globalPosition),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handlePointerDown,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerUp,
              child: RepaintBoundary(
                key: _snapshotBoundaryKey,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [fallback, ..._buildAnnotationOverlays()],
                ),
              ),
            ),
          )
        : fallback;
    final uvPane = Model3DPreviewPane(
      snapshot: _presentation.snapshot,
      checker:
          widget.payload.inspectorSelection ==
          Model3DInspectorSelection.uvChecker,
      canvasColor: widget.canvasColor,
      panelColor: widget.panelColor,
      borderColor: widget.borderColor,
      foregroundColor: widget.textColor,
      mutedColor: widget.mutedColor,
    );
    final viewport = switch (widget.payload.viewportMode) {
      Model3DViewportMode.twoD => Stack(
        key: const ValueKey('model3d-viewport-2d'),
        fit: StackFit.expand,
        children: [
          if (viewer != null && _error == null) Offstage(child: livePreview),
          uvPane,
        ],
      ),
      Model3DViewportMode.threeDAndTwoD => Row(
        key: const ValueKey('model3d-viewport-3d-and-2d'),
        children: [
          Expanded(child: _fitViewport(livePreview)),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: uvPane),
        ],
      ),
      Model3DViewportMode.threeD => KeyedSubtree(
        key: const ValueKey('model3d-viewport-3d'),
        child: livePreview,
      ),
    };
    final statusLabel = widget.payload.viewportMode == Model3DViewportMode.twoD
        ? 'UV PREVIEW'
        : widget.interactive
        ? 'LIVE 3D'
        : 'GLB PREVIEW';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: transparent ? Colors.transparent : widget.panelColor,
        border: Border.all(color: widget.borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          fit: StackFit.expand,
          children: [
            viewport,
            if (!_isReady && _error == null)
              Center(
                child: const UiProgressIndicator(
                  semanticsLabel: 'Loading 3D preview',
                  size: 22,
                ),
              ),
            if (_isReady && _error == null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 7,
                child: IgnorePointer(
                  child: Row(
                    children: [
                      UiSurface(
                        color: widget.panelColor.withValues(alpha: 0.92),
                        borderColor: widget.borderColor.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(
                          context.appTokens.controlRadius,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.xxs,
                        ),
                        child: Text(
                          statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: widget.textColor,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                              ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'GLB • ${widget.payload.fileSizeText}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: widget.mutedColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: AppControlSize.minimumHitTarget,
              child: _Model3DDragHeader(
                payload: widget.payload,
                canMove: widget.canMove,
                selected: widget.selected,
                backgroundColor: widget.panelColor,
                textColor: widget.textColor,
                onSelect: widget.onSelect,
                onDragDelta: widget.onDragDelta,
                onSecondaryTap: widget.onSecondaryTap,
              ),
            ),
            if (_viewerInteractionEnabled &&
                _isReady &&
                _controls != null &&
                _error == null)
              _buildControlDock(),
          ],
        ),
      ),
    );
  }

  Widget _fitViewport(Widget child) => FittedBox(
    fit: BoxFit.contain,
    child: SizedBox(width: widget.width, height: widget.height, child: child),
  );

  Widget _buildModel3DControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) =>
      Model3DControlButton(icon: icon, tooltip: tooltip, onPressed: onPressed);
}

class _Model3DDragHeader extends StatelessWidget {
  final Model3DPayload payload;
  final bool canMove;
  final bool selected;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback? onSelect;
  final ValueChanged<Offset>? onDragDelta;
  final ValueChanged<Offset>? onSecondaryTap;

  const _Model3DDragHeader({
    required this.payload,
    required this.canMove,
    required this.selected,
    required this.backgroundColor,
    required this.textColor,
    required this.onSelect,
    required this.onDragDelta,
    required this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      key: const ValueKey('model3d-drag-header-surface'),
      color: backgroundColor.withValues(alpha: selected ? 0.92 : 0.76),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.view_in_ar_outlined, size: 14, color: textColor),
          const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
          Expanded(
            child: Text(
              payload.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return Focus(
      key: const ValueKey('model3d-drag-header-focus'),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) &&
            onSelect != null) {
          onSelect!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        container: true,
        focusable: true,
        button: true,
        enabled: onSelect != null,
        label: '3D model ${payload.displayName}',
        hint: canMove && onDragDelta != null
            ? 'Drag to move this model.'
            : null,
        onTap: onSelect,
        child: ExcludeSemantics(
          child: GestureDetector(
            key: const ValueKey('model3d-drag-header-target'),
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            onSecondaryTapUp: onSecondaryTap == null
                ? null
                : (details) => onSecondaryTap!(details.globalPosition),
            child: Stack(
              fit: StackFit.expand,
              children: [
                content,
                if (canMove && onDragDelta != null)
                  Positioned(
                    left: AppSpacing.sm,
                    right: AppSpacing.sm,
                    top: AppSpacing.sm,
                    bottom: 0,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerMove: (event) {
                        if (event.buttons == 0) return;
                        onDragDelta!(event.delta);
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Model3DFallbackCard extends StatelessWidget {
  final Model3DPayload payload;
  final String? error;
  final bool selected;
  final Color canvasColor;
  final Color panelColor;
  final Color borderColor;
  final Color textColor;
  final Color mutedColor;
  final VoidCallback? onSelect;
  final ValueChanged<Offset>? onDragDelta;
  final ValueChanged<Offset>? onSecondaryTap;
  final VoidCallback? onRetry;

  const Model3DFallbackCard({
    required this.payload,
    required this.error,
    required this.selected,
    required this.canvasColor,
    required this.panelColor,
    required this.borderColor,
    required this.textColor,
    required this.mutedColor,
    this.onSelect,
    this.onDragDelta,
    this.onSecondaryTap,
    this.onRetry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final message = error?.trim().isNotEmpty == true
        ? error!.trim()
        : 'Select this model to try interactive preview.';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSelect,
      onPanStart: onDragDelta == null ? null : (_) {},
      onPanUpdate: onDragDelta == null
          ? null
          : (details) => onDragDelta!(details.delta),
      onPanEnd: onDragDelta == null ? null : (_) {},
      onSecondaryTapUp: onSecondaryTap == null
          ? null
          : (details) => onSecondaryTap!(details.globalPosition),
      child: Container(
        color: panelColor,
        padding: const EdgeInsets.fromLTRB(12, 34, 12, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 170 || constraints.maxWidth < 180;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : 0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.view_in_ar_outlined,
                      size: compact ? 30 : 42,
                      color: borderColor,
                    ),
                    SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
                    Text(
                      payload.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: compact ? AppSpacing.xxs : AppSpacing.xs),
                    Text(
                      message,
                      maxLines: compact ? 1 : 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: mutedColor, fontSize: 10),
                    ),
                    if (error != null && onRetry != null) ...[
                      SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
                      UiButton(
                        variant: UiButtonVariant.ghost,
                        size: UiButtonSize.sm,
                        onPressed: onRetry,
                        child: Text(
                          'Retry preview',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium!
                              .copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
