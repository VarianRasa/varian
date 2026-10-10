import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/prototype_interaction.dart';
import 'package:varian/domain/models/viewport.dart';
import 'package:varian/features/canvas/presentation/painters/canvas_painter.dart';
import 'package:varian/features/canvas/presentation/painters/grid_painter.dart';
import 'package:varian/features/presentation/domain/presentation_plan.dart';
import 'package:varian/features/presentation/domain/presenter_remote_controller.dart';
import 'package:varian/features/presentation/domain/remote_presenter_control.dart';
import 'package:varian/features/presentation/domain/prototype_interaction_engine.dart';
import 'package:varian/features/presentation/domain/storyboard_timeline.dart';
import 'presentation_timeline_dialog.dart';

class PresentationScreen extends StatefulWidget {
  final CanvasDocument document;
  final PresenterRemoteSession? remoteSession;
  final Stream<PresenterRemoteCommand>? remoteCommands;
  final ValueChanged<PresenterRemoteCommandResult>? onRemoteCommand;

  const PresentationScreen({
    super.key,
    required this.document,
    this.remoteSession,
    this.remoteCommands,
    this.onRemoteCommand,
  });

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  late List<CanvasNode> _frames;
  late PresentationPlan _presentationPlan;
  int _currentFrameIndex = 0;
  bool _laserActive = false;
  final List<Offset> _laserTrail = [];
  StreamSubscription<PresenterRemoteCommand>? _remoteCommandSubscription;
  PresenterRemoteCommandController? _remoteController;
  bool _remotePaused = false;
  final List<String> _frameHistory = [];
  String? _activeOverlayNodeId;
  String? _activePrototypeStateId;
  String? _hoveredPrototypeNodeId;
  Offset? _lastPointerPosition;
  PrototypeTransition _activeTransition = PrototypeTransition.instant;
  int _activeTransitionDurationMs = 0;
  String _devicePresetId = 'desktop';
  bool _deviceLandscape = false;

  PrototypeDevicePreset get _activeDevicePreset {
    final preset = prototypeDevicePresets.firstWhere(
      (item) => item.id == _devicePresetId,
      orElse: () => prototypeDevicePresets.first,
    );
    return _deviceLandscape ? preset.landscape : preset;
  }

  void _toggleDeviceOrientation() {
    setState(() => _deviceLandscape = !_deviceLandscape);
  }

  @override
  void initState() {
    super.initState();
    _presentationPlan = PresentationPlan.fromDocument(widget.document);
    _frames = _presentationPlan.resolveFrames(widget.document.nodes);
    _configureRemoteControl();
  }

  @override
  void didUpdateWidget(covariant PresentationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      _presentationPlan = PresentationPlan.fromDocument(widget.document);
      _frames = _presentationPlan.resolveFrames(widget.document.nodes);
      _currentFrameIndex = _frames.isEmpty
          ? 0
          : _currentFrameIndex.clamp(0, _frames.length - 1).toInt();
      _frameHistory.clear();
      _activeOverlayNodeId = null;
      _activePrototypeStateId = null;
    }
    if (oldWidget.remoteSession != widget.remoteSession ||
        oldWidget.remoteCommands != widget.remoteCommands) {
      _configureRemoteControl();
    }
  }

  void _configureRemoteControl() {
    final previousSubscription = _remoteCommandSubscription;
    _remoteCommandSubscription = null;
    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }
    _remoteController = widget.remoteSession == null
        ? null
        : PresenterRemoteCommandController(session: widget.remoteSession);
    _remotePaused = false;
    final stream = widget.remoteCommands;
    if (stream != null) {
      _remoteCommandSubscription = stream.listen(_handleRemoteCommand);
    }
  }

  void _handleRemoteCommand(PresenterRemoteCommand command) {
    final controller = _remoteController;
    if (controller == null) return;
    final result = controller.apply(
      command,
      now: DateTime.now().toUtc(),
      frameCount: _frames.length,
    );
    widget.onRemoteCommand?.call(result);
    if (!result.applied || !mounted) return;
    setState(() {
      _currentFrameIndex = result.frameIndex;
      _remotePaused = result.paused;
      _activeOverlayNodeId = null;
    });
  }

  void _nextSlide() {
    if (_frames.isNotEmpty && _currentFrameIndex < _frames.length - 1) {
      _showFrame(
        _currentFrameIndex + 1,
        recordHistory: false,
        transition: PrototypeTransition.instant,
      );
    }
  }

  void _prevSlide() {
    if (_frames.isNotEmpty && _currentFrameIndex > 0) {
      _showFrame(
        _currentFrameIndex - 1,
        recordHistory: false,
        transition: PrototypeTransition.instant,
      );
    }
  }

  void _jumpToFrame(String frameId) {
    final idx = _frames.indexWhere((f) => f.id == frameId);
    if (idx != -1) {
      _showFrame(idx, recordHistory: true);
    }
  }

  void _showFrame(
    int index, {
    bool recordHistory = true,
    PrototypeTransition transition = PrototypeTransition.instant,
    int durationMs = 300,
  }) {
    if (_frames.isEmpty || index < 0 || index >= _frames.length) return;
    if (index == _currentFrameIndex) return;
    if (recordHistory) _frameHistory.add(_frames[_currentFrameIndex].id);
    setState(() {
      _currentFrameIndex = index;
      _activeTransition = transition;
      _activeTransitionDurationMs = durationMs;
      _activeOverlayNodeId = null;
      _activePrototypeStateId = null;
      _remoteController?.syncLocalFrame(index, _frames.length);
    });
  }

  CanvasNode? _hitTest(Offset worldPosition) {
    if (_frames.isEmpty) return null;
    final frameId = _frames[_currentFrameIndex].id;
    final candidates =
        widget.document.nodes
            .where(
              (node) =>
                  node.visible &&
                  _belongsToFrame(node, frameId) &&
                  node.bounds.contains(worldPosition),
            )
            .toList()
          ..sort((left, right) => left.zIndex.compareTo(right.zIndex));
    return candidates.isEmpty ? null : candidates.last;
  }

  bool _belongsToFrame(CanvasNode node, String frameId) {
    if (node.id == frameId) return true;
    final visited = <String>{};
    var parentId = node.parentId;
    while (parentId != null && visited.add(parentId)) {
      if (parentId == frameId) return true;
      parentId = widget.document.nodes
          .where((candidate) => candidate.id == parentId)
          .firstOrNull
          ?.parentId;
    }
    return false;
  }

  Offset _toWorldPosition(
    Offset localPosition,
    double offsetX,
    double offsetY,
    double scale,
  ) => Offset(
    (localPosition.dx - offsetX) / scale,
    (localPosition.dy - offsetY) / scale,
  );

  void _triggerAt(
    Offset localPosition,
    double offsetX,
    double offsetY,
    double scale,
    PrototypeTrigger trigger,
  ) {
    final node = _hitTest(
      _toWorldPosition(localPosition, offsetX, offsetY, scale),
    );
    if (node == null) return;
    _triggerNode(node.id, trigger);
  }

  void _triggerNode(String nodeId, PrototypeTrigger trigger) {
    final node = widget.document.nodes
        .where((candidate) => candidate.id == nodeId)
        .firstOrNull;
    final result = PrototypeInteractionEngine(
      widget.document.nodes,
    ).resolve(nodeId: nodeId, trigger: trigger);
    if (result.action == null) {
      if (trigger == PrototypeTrigger.tap &&
          node?.payload.hotspotTargetFrameId != null) {
        _jumpToFrame(node!.payload.hotspotTargetFrameId!);
      }
      return;
    }
    if (!result.applied) {
      _showPrototypeError(result.error);
      return;
    }
    unawaited(_applyPrototypeExecution(result));
  }

  List<Widget> _buildPrototypeSemantics(
    double offsetX,
    double offsetY,
    double scale,
  ) {
    final frameId = _frames[_currentFrameIndex].id;
    return widget.document.nodes
        .where((node) {
          if (!node.visible || !_belongsToFrame(node, frameId)) return false;
          final hasTapInteraction = node.prototypeInteractions.any(
            (interaction) =>
                interaction.enabled &&
                interaction.trigger == PrototypeTrigger.tap &&
                interaction.isValid,
          );
          return hasTapInteraction ||
              node.payload.hotspotTargetFrameId?.trim().isNotEmpty == true;
        })
        .map((node) {
          final cosine = math.cos(node.rotation).abs();
          final sine = math.sin(node.rotation).abs();
          final width = (node.width * cosine + node.height * sine) * scale;
          final height = (node.width * sine + node.height * cosine) * scale;
          final centerX = offsetX + (node.x + node.width / 2) * scale;
          final centerY = offsetY + (node.y + node.height / 2) * scale;
          final targetWidth = math.max(48.0, width);
          final targetHeight = math.max(48.0, height);
          void activate() => _triggerNode(node.id, PrototypeTrigger.tap);

          return Positioned(
            left: centerX - targetWidth / 2,
            top: centerY - targetHeight / 2,
            width: targetWidth,
            height: targetHeight,
            child: Focus(
              onKeyEvent: (focusNode, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.space)) {
                  activate();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Semantics(
                container: true,
                button: true,
                focusable: true,
                label: node.name?.trim().isNotEmpty == true
                    ? node.name!.trim()
                    : '${node.type.name} hotspot',
                onTap: activate,
                child: ExcludeSemantics(child: SizedBox.expand()),
              ),
            ),
          );
        })
        .toList(growable: false);
  }

  Future<void> _applyPrototypeExecution(
    PrototypeInteractionExecution execution,
  ) async {
    final action = execution.action;
    if (action == null) return;
    switch (action) {
      case PrototypeAction.navigate:
        final targetFrameId = execution.targetFrameId;
        if (targetFrameId != null) {
          _showFrame(
            _frames.indexWhere((frame) => frame.id == targetFrameId),
            transition: execution.transition,
            durationMs: MediaQuery.disableAnimationsOf(context)
                ? 0
                : execution.durationMs,
          );
        }
      case PrototypeAction.overlay:
        if (!mounted) return;
        setState(() => _activeOverlayNodeId = execution.targetNodeId);
      case PrototypeAction.setState:
        if (!mounted) return;
        setState(() => _activePrototypeStateId = execution.stateId);
      case PrototypeAction.openUrl:
        final rawUrl = execution.url;
        if (rawUrl != null) await _openPrototypeUrl(rawUrl);
      case PrototypeAction.back:
        if (_frameHistory.isNotEmpty) {
          final previousFrameId = _frameHistory.removeLast();
          final previousIndex = _frames.indexWhere(
            (frame) => frame.id == previousFrameId,
          );
          if (previousIndex >= 0) {
            _showFrame(previousIndex, recordHistory: false);
          }
        } else if (mounted) {
          Navigator.of(context).maybePop();
        }
    }
  }

  Future<void> _openPrototypeUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme) {
      _showPrototypeError('URL prototype tidak valid.');
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) _showPrototypeError('URL prototype tidak dapat dibuka.');
  }

  void _showPrototypeError(String? message) {
    if (!mounted || message == null || message.isEmpty) return;
    showUiToast(context, message);
  }

  Widget _buildPrototypeTransition(Widget child, Animation<double> animation) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    switch (_activeTransition) {
      case PrototypeTransition.instant:
        return child;
      case PrototypeTransition.dissolve:
        return FadeTransition(opacity: animation, child: child);
      case PrototypeTransition.smartAnimate:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.98, end: 1.0).animate(animation),
            child: child,
          ),
        );
      case PrototypeTransition.slideLeft:
        return SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      case PrototypeTransition.slideRight:
        return SlideTransition(
          position: Tween(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      case PrototypeTransition.slideUp:
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      case PrototypeTransition.slideDown:
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      case PrototypeTransition.push:
        return SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
    }
  }

  Widget _buildOverlayLayer(
    BuildContext context,
    double offsetX,
    double offsetY,
    double scale,
  ) {
    CanvasNode? overlay;
    for (final node in widget.document.nodes) {
      if (node.id == _activeOverlayNodeId) {
        overlay = node;
        break;
      }
    }
    if (overlay == null) return const SizedBox.shrink();

    final overlayNodes = <CanvasNode>[overlay];
    overlayNodes.addAll(
      widget.document.nodes.where((node) {
        if (node.id == overlay!.id) return false;
        var parentId = node.parentId;
        final visited = <String>{};
        while (parentId != null && visited.add(parentId)) {
          if (parentId == overlay.id) return true;
          parentId = widget.document.nodes
              .where((candidate) => candidate.id == parentId)
              .firstOrNull
              ?.parentId;
        }
        return false;
      }),
    );
    final width = overlay.width * scale < 1 ? 1.0 : overlay.width * scale;
    final height = overlay.height * scale < 1 ? 1.0 : overlay.height * scale;
    final tokens = context.appTokens;
    final viewport = Viewport(
      x: -overlay.x * scale,
      y: -overlay.y * scale,
      zoom: scale,
    );

    return Positioned(
      left: offsetX + overlay.x * scale,
      top: offsetY + overlay.y * scale,
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              CustomPaint(
                size: Size(width, height),
                painter: CanvasPainter(
                  nodes: overlayNodes,
                  edges: const [],
                  viewport: viewport,
                  selectedNodeIds: const {},
                  renderTokens: CanvasRenderTokens.fromAppTokens(tokens),
                ),
              ),
              Positioned(
                top: AppSpacing.xxs,
                right: AppSpacing.xxs,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.panel.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: UiIconButton(
                    icon: Icons.close,
                    iconSize: 16,
                    tooltip: 'Close overlay',
                    size: UiButtonSize.lg,
                    color: tokens.textMuted,
                    onPressed: () =>
                        setState(() => _activeOverlayNodeId = null),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editTimeline() async {
    final timeline =
        _presentationPlan.timeline ??
        PresentationTimeline(
          shots: [
            for (var index = 0; index < _frames.length; index++)
              StoryboardShot(
                id: 'shot-${_frames[index].id}',
                title: 'Shot ${index + 1}',
                frameId: _frames[index].id,
              ),
          ],
        );
    final edited = await showUiDialog<PresentationTimeline>(
      context: context,
      builder: (_) => PresentationTimelineDialog(initialTimeline: timeline),
    );
    if (edited == null || !mounted) return;
    setState(() {
      _presentationPlan = PresentationPlan(
        frames: _presentationPlan.frames,
        timeline: edited,
      );
      _frames = _presentationPlan.resolveFrames(widget.document.nodes);
      _currentFrameIndex = _currentFrameIndex
          .clamp(0, _frames.length - 1)
          .toInt();
    });
  }

  Widget _buildControlButton({
    required AppTokens tokens,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool selected = false,
    bool destructive = false,
  }) => UiIconButton(
    icon: icon,
    tooltip: tooltip,
    onPressed: onPressed,
    variant: selected ? UiButtonVariant.primary : UiButtonVariant.ghost,
    selected: selected,
    size: UiButtonSize.lg,
    color: destructive ? tokens.danger : null,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    if (_frames.isEmpty) {
      return UiPageScaffold(
        title: const SizedBox.shrink(),
        showHeader: false,
        child: UiEmptyState(
          icon: Icons.slideshow_outlined,
          title: 'No Frames Found for Presentation',
          message:
              'Add Frame containers on the canvas to use Presentation Mode.',
          action: UiButton(
            onPressed: () => Navigator.pop(context),
            prefix: const Icon(Icons.arrow_back),
            child: const Text('Return to Canvas'),
          ),
        ),
      );
    }

    final currentFrame = _frames[_currentFrameIndex];
    final framePayload = currentFrame.payload is FramePayload
        ? currentFrame.payload as FramePayload
        : FramePayload();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _nextSlide,
        const SingleActivator(LogicalKeyboardKey.space): _nextSlide,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _prevSlide,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: UiPageScaffold(
          title: const SizedBox.shrink(),
          showHeader: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final device = _activeDevicePreset;
              final scaleX = constraints.maxWidth / device.width;
              final scaleY = constraints.maxHeight / device.height;
              final scale = (scaleX < scaleY ? scaleX : scaleY) * 0.92;

              final offsetX =
                  (constraints.maxWidth - device.width * scale) / 2 -
                  currentFrame.x * scale;
              final offsetY =
                  (constraints.maxHeight - device.height * scale) / 2 -
                  currentFrame.y * scale;

              final presentationViewport = Viewport(
                x: offsetX,
                y: offsetY,
                zoom: scale,
              );

              return Stack(
                children: [
                  MouseRegion(
                    onHover: (event) {
                      if (_laserActive) {
                        setState(() {
                          _laserTrail.add(event.localPosition);
                          if (_laserTrail.length > 25) _laserTrail.removeAt(0);
                        });
                      }
                      final hoveredNode = _hitTest(
                        _toWorldPosition(
                          event.localPosition,
                          offsetX,
                          offsetY,
                          scale,
                        ),
                      );
                      if (hoveredNode?.id != _hoveredPrototypeNodeId) {
                        _hoveredPrototypeNodeId = hoveredNode?.id;
                        if (hoveredNode != null) {
                          _triggerAt(
                            event.localPosition,
                            offsetX,
                            offsetY,
                            scale,
                            PrototypeTrigger.hover,
                          );
                        }
                      }
                    },
                    onExit: (_) => _hoveredPrototypeNodeId = null,
                    child: GestureDetector(
                      onTapDown: (details) => _triggerAt(
                        details.localPosition,
                        offsetX,
                        offsetY,
                        scale,
                        PrototypeTrigger.press,
                      ),
                      onTapUp: (details) {
                        _triggerAt(
                          details.localPosition,
                          offsetX,
                          offsetY,
                          scale,
                          PrototypeTrigger.tap,
                        );
                      },
                      onPanStart: (details) {
                        _lastPointerPosition = details.localPosition;
                      },
                      onPanUpdate: (details) {
                        _lastPointerPosition = details.localPosition;
                      },
                      onPanEnd: (_) {
                        final position = _lastPointerPosition;
                        _lastPointerPosition = null;
                        if (position != null) {
                          _triggerAt(
                            position,
                            offsetX,
                            offsetY,
                            scale,
                            PrototypeTrigger.drag,
                          );
                        }
                      },
                      child: AnimatedSwitcher(
                        duration: AppMotion.durationFor(
                          context,
                          Duration(
                            milliseconds: _activeTransitionDurationMs <= 0
                                ? 1
                                : _activeTransitionDurationMs,
                          ),
                        ),
                        transitionBuilder: _buildPrototypeTransition,
                        child: CustomPaint(
                          key: ValueKey(currentFrame.id),
                          painter: CanvasPainter(
                            nodes: widget.document.nodes,
                            edges: widget.document.edges,
                            cursors: const [],
                            viewport: presentationViewport,
                            selectedNodeIds: const {},
                            renderTokens: CanvasRenderTokens.fromAppTokens(
                              tokens,
                            ),
                          ),
                          foregroundPainter: LaserPointerPainter(
                            trail: _laserTrail,
                            enabled: _laserActive,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),

                  ..._buildPrototypeSemantics(offsetX, offsetY, scale),
                  if (_activeOverlayNodeId != null)
                    _buildOverlayLayer(context, offsetX, offsetY, scale),

                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 560;
                        final statuses = Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          children: [
                            if (_activePrototypeStateId != null)
                              UiBadge(
                                'STATE ${_activePrototypeStateId!}',
                                variant: UiBadgeVariant.primary,
                              ),
                            if (_remoteController != null)
                              UiBadge(
                                _remotePaused
                                    ? 'REMOTE PAUSED'
                                    : 'REMOTE ACTIVE',
                                variant: _remotePaused
                                    ? UiBadgeVariant.warning
                                    : UiBadgeVariant.success,
                              ),
                          ],
                        );
                        final slideTitle = Text(
                          'SLIDE ${_currentFrameIndex + 1} / ${_frames.length}: ${framePayload.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge!
                              .copyWith(
                                color: tokens.text,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .4,
                              ),
                        );
                        return UiSurface(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          color: tokens.panel.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(
                            tokens.panelRadius,
                          ),
                          child: compact
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    slideTitle,
                                    if (_activePrototypeStateId != null ||
                                        _remoteController != null) ...[
                                      const SizedBox(
                                        height: AppSpacing.xs + AppSpacing.xxs,
                                      ),
                                      statuses,
                                    ],
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(child: slideTitle),
                                    if (_activePrototypeStateId != null ||
                                        _remoteController != null) ...[
                                      const SizedBox(width: AppSpacing.md),
                                      statuses,
                                    ],
                                  ],
                                ),
                        );
                      },
                    ),
                  ),

                  // Bottom Controls
                  Positioned(
                    bottom: AppSpacing.pageWide,
                    left: 0,
                    right: 0,
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: (constraints.maxWidth - AppSpacing.lg)
                                .clamp(0.0, double.infinity)
                                .toDouble(),
                          ),
                          child: UiSurface(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.xs + AppSpacing.xxs,
                            ),
                            color: tokens.panel.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(
                              tokens.panelRadius,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 144,
                                  child: UiSelect<String>(
                                    hint: 'Device',
                                    items: {
                                      for (final preset
                                          in prototypeDevicePresets)
                                        preset.label: preset.id,
                                    },
                                    value: _devicePresetId,
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() => _devicePresetId = value);
                                    },
                                  ),
                                ),
                                _buildControlButton(
                                  tokens: tokens,
                                  icon: _deviceLandscape
                                      ? Icons.stay_current_landscape
                                      : Icons.stay_current_portrait,
                                  tooltip: 'Toggle device orientation',
                                  onPressed: _toggleDeviceOrientation,
                                ),
                                Text(
                                  '${_activeDevicePreset.width.toInt()}×${_activeDevicePreset.height.toInt()} @${_activeDevicePreset.devicePixelRatio.toStringAsFixed(0)}x',
                                  style: Theme.of(context).textTheme.labelSmall!
                                      .copyWith(color: tokens.textMuted),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _buildControlButton(
                                  tokens: tokens,
                                  icon: Icons.arrow_back,
                                  tooltip: 'Previous Slide (Left Arrow)',
                                  onPressed: _currentFrameIndex > 0
                                      ? _prevSlide
                                      : null,
                                ),
                                _buildControlButton(
                                  tokens: tokens,
                                  icon: Icons.arrow_forward,
                                  tooltip: 'Next Slide (Right Arrow / Space)',
                                  onPressed:
                                      _currentFrameIndex < _frames.length - 1
                                      ? _nextSlide
                                      : null,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _buildControlButton(
                                  tokens: tokens,
                                  icon: Icons.highlight,
                                  tooltip: 'Toggle Laser Pointer',
                                  selected: _laserActive,
                                  onPressed: () => setState(() {
                                    _laserActive = !_laserActive;
                                    if (!_laserActive) _laserTrail.clear();
                                  }),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _buildControlButton(
                                  tokens: tokens,
                                  icon: Icons.timeline_outlined,
                                  tooltip: 'Edit Storyboard Timeline',
                                  onPressed: _editTimeline,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _buildControlButton(
                                  tokens: tokens,
                                  icon: Icons.close,
                                  tooltip: 'Exit Presentation (Esc)',
                                  destructive: true,
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_remoteCommandSubscription?.cancel());
    super.dispose();
  }
}

class LaserPointerPainter extends CustomPainter {
  final List<Offset> trail;
  final bool enabled;

  LaserPointerPainter({required this.trail, required this.enabled});

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || trail.isEmpty) return;

    for (int i = 0; i < trail.length; i++) {
      final alpha = ((i + 1) / trail.length).clamp(0.0, 1.0);
      final radius = 2.0 + (i / trail.length) * 5.0;
      final paint = Paint()
        ..color = AppTheme.braunOrange.withValues(alpha: alpha * 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(trail[i], radius, paint);
    }

    final tipPaint = Paint()
      ..color = AppTheme.handleFill
      ..style = PaintingStyle.fill;
    canvas.drawCircle(trail.last, 3.5, tipPaint);
  }

  @override
  bool shouldRepaint(covariant LaserPointerPainter oldDelegate) => true;
}
