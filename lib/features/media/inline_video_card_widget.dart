import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/media/data/transient_media_source_resolver.dart';
import 'package:varian/features/media/data/transient_media_source_types.dart';
import 'package:varian/features/video_card/data/video_source_policy.dart';
import 'transient_video_bytes_source.dart';
import 'package:video_player/video_player.dart' as vp;
import 'video_file_source.dart';

class InlineVideoCardWidget extends StatefulWidget {
  final String sourcePath;
  final String? networkUrl;
  final String? storagePath;
  final String? artifactReference;
  final TransientMediaSourceResolver? sourceResolver;
  final VoidCallback? onOpenPlayer;
  final VoidCallback? onDownload;
  final String? caption;
  final String? posterPath;
  final MediaTimeline? timeline;
  final ValueChanged<Offset>? onSecondaryTap;
  final ValueChanged<Offset>? onDragDelta;

  const InlineVideoCardWidget({
    super.key,
    required this.sourcePath,
    this.networkUrl,
    this.storagePath,
    this.artifactReference,
    this.sourceResolver,
    this.onOpenPlayer,
    this.onDownload,
    this.caption,
    this.posterPath,
    this.timeline,
    this.onSecondaryTap,
    this.onDragDelta,
  });

  @override
  State<InlineVideoCardWidget> createState() => _InlineVideoCardWidgetState();
}

class _InlineVideoCardWidgetState extends State<InlineVideoCardWidget> {
  vp.VideoPlayerController? _controller;
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<Duration>? _positionSubscription;
  String? _error;
  TransientMediaSource? _resolvedSource;
  TransientVideoByteSource? _byteSource;
  int _initializationGeneration = 0;
  int _timelineGeneration = 0;
  bool _ready = false;
  bool _trimEnded = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final generation = ++_initializationGeneration;
    _timelineGeneration++;
    final previousSource = _resolvedSource;
    _resolvedSource = null;
    final previousByteSource = _byteSource;
    _byteSource = null;
    final previousController = _controller;
    _controller = null;
    previousController?.removeListener(_handleVideoTick);
    final previousPlayer = _player;
    _player = null;
    final previousSubscription = _positionSubscription;
    _positionSubscription = null;
    _videoController = null;
    if (mounted) {
      setState(() {
        _ready = false;
        _error = null;
        _trimEnded = false;
      });
    }

    await _disposeRuntime(
      controller: previousController,
      player: previousPlayer,
      positionSubscription: previousSubscription,
      source: previousSource,
      byteSource: previousByteSource,
    );
    if (!mounted || generation != _initializationGeneration) return;

    TransientMediaSource? resolved;
    TransientVideoByteSource? materializedByteSource;
    Player? createdPlayer;
    VideoController? createdVideoController;
    vp.VideoPlayerController? createdController;
    try {
      resolved = widget.sourceResolver == null
          ? null
          : await widget.sourceResolver!.resolveVideo(
              VideoPayload(
                storagePath: widget.storagePath,
                videoPath: widget.sourcePath,
                videoUrl: widget.networkUrl,
                videoArtifactReference: widget.artifactReference,
                title: widget.caption ?? 'Video',
                caption: widget.caption,
                mediaTimeline: widget.timeline,
              ),
            );
      if (!mounted || generation != _initializationGeneration) {
        await resolved?.dispose();
        return;
      }
      var resolvedPath =
          resolved?.path ??
          (widget.sourceResolver == null
              ? safeTransientMediaSource(widget.sourcePath)
              : null);
      var resolvedUrl =
          resolved?.uri?.toString() ??
          (widget.sourceResolver == null
              ? safeTransientMediaSource(widget.networkUrl)
              : null);
      final resolvedBytes = await resolved?.readBytes();
      if (resolvedBytes != null && resolvedBytes.isNotEmpty) {
        materializedByteSource = await materializeTransientVideoBytes(
          resolvedBytes,
          mimeType:
              resolved?.mimeType ??
              transientVideoMimeType(
                widget.sourcePath.isNotEmpty
                    ? widget.sourcePath
                    : widget.storagePath,
              ),
        );
        if (!mounted || generation != _initializationGeneration) {
          await materializedByteSource?.dispose();
          await resolved?.dispose();
          return;
        }
        final materialized = materializedByteSource?.source;
        if (materialized != null && materialized.isNotEmpty) {
          if (transientVideoSourceIsUrl(materialized)) {
            resolvedUrl = materialized;
            resolvedPath = null;
          } else {
            resolvedPath = materialized;
            resolvedUrl = null;
          }
        }
      }
      final validation = VideoSourcePolicy.validate(
        path: resolvedPath,
        url: resolvedUrl,
      );
      if (!validation.isValid) {
        await _disposeRuntime(
          source: resolved,
          byteSource: materializedByteSource,
        );
        if (mounted && generation == _initializationGeneration) {
          setState(() => _error = validation.error);
        }
        return;
      }
      final source = resolvedUrl ?? resolvedPath;
      if (source == null || source.trim().isEmpty) {
        throw StateError('Video source is missing.');
      }
      if (isWindowsVideoPlayback) {
        if (!validation.isNetwork && await isNativeVideoFileMissing(source)) {
          throw StateError('Video file is missing or empty.');
        }
        final player = Player();
        final videoController = VideoController(player);
        createdPlayer = player;
        createdVideoController = videoController;
        await player.open(Media(source), play: false);
        await _applyWindowsTimelineSettings(
          player,
          isCurrent: () => mounted && generation == _initializationGeneration,
        );
        if (!mounted || generation != _initializationGeneration) {
          await _disposeRuntime(
            player: createdPlayer,
            source: resolved,
            byteSource: materializedByteSource,
          );
          return;
        }
      } else {
        final controller = validation.isNetwork || kIsWeb
            ? vp.VideoPlayerController.networkUrl(Uri.parse(source))
            : createNativeVideoController(source);
        createdController = controller;
        await controller.initialize();
        if (!mounted || generation != _initializationGeneration) {
          await _disposeRuntime(
            controller: controller,
            source: resolved,
            byteSource: materializedByteSource,
          );
          return;
        }
        await controller.setLooping(true);
        await _applyVideoTimelineSettings(
          controller,
          isCurrent: () => mounted && generation == _initializationGeneration,
        );
        if (!mounted || generation != _initializationGeneration) {
          await _disposeRuntime(
            controller: controller,
            source: resolved,
            byteSource: materializedByteSource,
          );
          return;
        }
      }
      if (!mounted || generation != _initializationGeneration) {
        await _disposeRuntime(
          controller: createdController,
          player: createdPlayer,
          source: resolved,
          byteSource: materializedByteSource,
        );
        return;
      }
      _resolvedSource = resolved;
      _byteSource = materializedByteSource;
      _player = createdPlayer;
      _videoController = createdVideoController;
      _controller = createdController;
      _positionSubscription = createdPlayer?.stream.position.listen(
        _enforceTrim,
      );
      createdController?.addListener(_handleVideoTick);
      setState(() => _ready = true);
    } catch (_) {
      await _disposeRuntime(
        controller: createdController,
        player: createdPlayer,
        source: resolved,
        byteSource: materializedByteSource,
      );
      if (mounted && generation == _initializationGeneration) {
        setState(() => _error = 'Video preview could not be loaded.');
      }
    }
  }

  Future<void> _disposeRuntime({
    vp.VideoPlayerController? controller,
    Player? player,
    StreamSubscription<Duration>? positionSubscription,
    TransientMediaSource? source,
    TransientVideoByteSource? byteSource,
  }) async {
    controller?.removeListener(_handleVideoTick);
    await positionSubscription?.cancel();
    await controller?.dispose();
    await player?.dispose();
    await source?.dispose();
    await byteSource?.dispose();
  }

  Widget _buildCompactWindowsControls(BuildContext context) {
    final player = _player!;
    final tokens = context.appTokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.panelElevated.withValues(alpha: 0.92),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<bool>(
            stream: player.stream.playing,
            initialData: false,
            builder: (context, snapshot) => UiIconButton(
              icon: snapshot.data == true ? Icons.pause : Icons.play_arrow,
              tooltip: snapshot.data == true ? 'Pause video' : 'Play video',
              size: UiButtonSize.sm,
              onPressed: () =>
                  snapshot.data == true ? player.pause() : player.play(),
            ),
          ),
          StreamBuilder<double>(
            stream: player.stream.volume,
            initialData: 100,
            builder: (context, snapshot) {
              final volume = (snapshot.data ?? 100).clamp(0.0, 100.0);
              final muted = volume == 0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UiIconButton(
                    icon: muted ? Icons.volume_off : Icons.volume_up,
                    tooltip: muted ? 'Unmute video' : 'Mute video',
                    size: UiButtonSize.sm,
                    onPressed: () => player.setVolume(muted ? 100 : 0),
                  ),
                  SizedBox(
                    width: 72,
                    child: UiSlider(
                      value: volume / 100,
                      onChanged: (value) => player.setVolume(value * 100),
                    ),
                  ),
                ],
              );
            },
          ),
          UiIconButton(
            icon: Icons.download_outlined,
            tooltip: 'Download video',
            size: UiButtonSize.sm,
            onPressed: widget.onDownload,
          ),
          UiIconButton(
            icon: Icons.open_in_full,
            tooltip: 'Open full player',
            size: UiButtonSize.sm,
            onPressed: widget.onOpenPlayer,
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant InlineVideoCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourcePath != widget.sourcePath ||
        oldWidget.networkUrl != widget.networkUrl ||
        oldWidget.storagePath != widget.storagePath ||
        oldWidget.artifactReference != widget.artifactReference ||
        oldWidget.sourceResolver != widget.sourceResolver) {
      _initialize();
    } else if (oldWidget.timeline != widget.timeline) {
      final generation = _initializationGeneration;
      final timelineGeneration = ++_timelineGeneration;
      final player = _player;
      final controller = _controller;
      final timeline = widget.timeline;
      if (player != null) {
        unawaited(
          _applyWindowsTimelineSettings(
            player,
            timeline: timeline,
            isCurrent: () =>
                mounted &&
                generation == _initializationGeneration &&
                timelineGeneration == _timelineGeneration &&
                identical(player, _player),
          ),
        );
      }
      if (controller != null) {
        unawaited(
          _applyVideoTimelineSettings(
            controller,
            timeline: timeline,
            isCurrent: () =>
                mounted &&
                generation == _initializationGeneration &&
                timelineGeneration == _timelineGeneration &&
                identical(controller, _controller),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _initializationGeneration++;
    unawaited(
      _disposeRuntime(
        controller: _controller,
        player: _player,
        positionSubscription: _positionSubscription,
        source: _resolvedSource,
        byteSource: _byteSource,
      ),
    );
    super.dispose();
  }

  Future<void> _applyVideoTimelineSettings(
    vp.VideoPlayerController controller, {
    MediaTimeline? timeline,
    bool Function()? isCurrent,
  }) async {
    timeline ??= widget.timeline;
    if (isCurrent?.call() == false) return;
    await controller.setPlaybackSpeed(
      (timeline?.playbackSpeed ?? 1.0).clamp(0.25, 4.0).toDouble(),
    );
    if (isCurrent?.call() == false) return;
    await controller.setVolume(
      timeline?.muted == true
          ? 0
          : (timeline?.volume ?? 1.0).clamp(0.0, 1.0).toDouble(),
    );
    final startMs = timeline?.trimStartMs ?? 0;
    if (startMs > 0) {
      if (isCurrent?.call() == false) return;
      await controller.seekTo(Duration(milliseconds: startMs));
    }
  }

  Future<void> _applyWindowsTimelineSettings(
    Player player, {
    MediaTimeline? timeline,
    bool Function()? isCurrent,
  }) async {
    timeline ??= widget.timeline;
    if (isCurrent?.call() == false) return;
    await player.setRate(
      (timeline?.playbackSpeed ?? 1.0).clamp(0.25, 4.0).toDouble(),
    );
    if (isCurrent?.call() == false) return;
    await player.setVolume(
      timeline?.muted == true
          ? 0
          : ((timeline?.volume ?? 1.0) * 100).clamp(0.0, 100.0).toDouble(),
    );
    final startMs = timeline?.trimStartMs ?? 0;
    if (startMs > 0) {
      if (isCurrent?.call() == false) return;
      await player.seek(Duration(milliseconds: startMs));
    }
  }

  void _handleVideoTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _enforceTrim(controller.value.position);
  }

  void _enforceTrim(Duration position) {
    final endMs = widget.timeline?.trimEndMs ?? 0;
    if (endMs <= 0 || position.inMilliseconds < endMs) {
      _trimEnded = false;
      return;
    }
    if (_trimEnded) return;
    _trimEnded = true;
    final startMs = widget.timeline?.trimStartMs ?? 0;
    if (_player != null) {
      unawaited(_player!.pause());
      unawaited(_player!.seek(Duration(milliseconds: startMs)));
    } else if (_controller != null) {
      unawaited(_controller!.pause());
      unawaited(_controller!.seekTo(Duration(milliseconds: startMs)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return GestureDetector(
      onDoubleTap: widget.onOpenPlayer,
      onPanUpdate: (details) => widget.onDragDelta?.call(details.delta),
      onSecondaryTapUp: widget.onSecondaryTap == null
          ? null
          : (details) => widget.onSecondaryTap!(details.globalPosition),
      child: DecoratedBox(
        decoration: BoxDecoration(color: tokens.videoBackground),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready && _videoController != null)
              Stack(
                fit: StackFit.expand,
                children: [
                  Video(
                    controller: _videoController!,
                    controls: (_) => const SizedBox.shrink(),
                  ),
                  Positioned(
                    left: AppSpacing.xs + AppSpacing.xxs,
                    right: AppSpacing.xs + AppSpacing.xxs,
                    bottom: AppSpacing.xs + AppSpacing.xxs,
                    child: _buildCompactWindowsControls(context),
                  ),
                ],
              )
            else if (_ready && _controller != null)
              FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: vp.VideoPlayer(_controller!),
                ),
              )
            else if (_error != null)
              Center(
                child: Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.danger),
                ),
              )
            else
              const Center(
                child: UiProgressIndicator(semanticsLabel: 'Loading video'),
              ),
            if (_ready && _controller != null && widget.onDownload != null)
              Positioned(
                top: AppSpacing.xs + AppSpacing.xxs,
                right: AppSpacing.xs + AppSpacing.xxs,
                child: UiIconButton(
                  icon: Icons.download_outlined,
                  tooltip: 'Download video',
                  onPressed: widget.onDownload,
                ),
              ),
            if (_ready && _controller != null)
              Positioned(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: vp.VideoProgressIndicator(
                  _controller!,
                  allowScrubbing: true,
                  colors: vp.VideoProgressColors(
                    playedColor: tokens.accent,
                    bufferedColor: tokens.videoBuffered,
                    backgroundColor: tokens.panelBorder.withValues(alpha: 0.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
