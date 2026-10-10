import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/media/data/transient_media_source_resolver.dart';
import 'package:varian/features/media/data/transient_media_source_types.dart';
import 'package:varian/features/video_card/data/video_source_policy.dart';
import 'transient_video_bytes_source.dart';
import 'package:video_player/video_player.dart';
import 'video_file_source.dart';

MaterialVideoControlsThemeData _materialKitVideoTheme(AppTokens tokens) =>
    MaterialVideoControlsThemeData(
      buttonBarButtonColor: tokens.accentForeground,
      seekBarColor: tokens.panelBorder,
      seekBarPositionColor: tokens.accent,
      seekBarBufferColor: tokens.videoBuffered,
      seekBarThumbColor: tokens.accent,
    );

MaterialDesktopVideoControlsThemeData _desktopKitVideoTheme(AppTokens tokens) =>
    MaterialDesktopVideoControlsThemeData(
      buttonBarButtonColor: tokens.accentForeground,
      seekBarColor: tokens.videoBackground,
      seekBarHoverColor: tokens.videoBuffered,
      seekBarPositionColor: tokens.accent,
      seekBarBufferColor: tokens.videoBuffered,
      seekBarThumbColor: tokens.accent,
      volumeBarColor: tokens.videoBackground,
      volumeBarActiveColor: tokens.accent,
      volumeBarThumbColor: tokens.accent,
    );

class VideoPlayerScreen extends StatefulWidget {
  final String sourcePath;
  final String? networkUrl;
  final String? storagePath;
  final String? artifactReference;
  final TransientMediaSourceResolver? sourceResolver;
  final String? caption;
  final MediaTimeline? timeline;
  final VoidCallback? onDownload;

  const VideoPlayerScreen({
    super.key,
    required this.sourcePath,
    this.networkUrl,
    this.storagePath,
    this.artifactReference,
    this.sourceResolver,
    this.caption,
    this.timeline,
    this.onDownload,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  Player? _mediaPlayer;
  VideoController? _mediaController;
  bool _mediaReady = false;
  bool _initialized = false;
  bool _looping = false;
  bool _muted = false;
  double _volume = 1.0;
  StreamSubscription<Duration>? _positionSubscription;
  bool _trimEnded = false;
  String? _error;
  TransientMediaSource? _resolvedSource;
  TransientVideoByteSource? _byteSource;
  int _initializationGeneration = 0;
  int _timelineGeneration = 0;

  @override
  void initState() {
    super.initState();
    _muted = widget.timeline?.muted ?? false;
    _volume = widget.timeline?.volume ?? 1.0;
    _init();
  }

  Future<void> _init() async {
    final generation = ++_initializationGeneration;
    _timelineGeneration++;
    final previousSource = _resolvedSource;
    _resolvedSource = null;
    final previousByteSource = _byteSource;
    _byteSource = null;
    final previousController = _controller;
    _controller = null;
    previousController?.removeListener(_handleVideoTick);
    final previousPlayer = _mediaPlayer;
    _mediaPlayer = null;
    _mediaController = null;
    final previousSubscription = _positionSubscription;
    _positionSubscription = null;
    if (mounted) {
      setState(() {
        _initialized = false;
        _mediaReady = false;
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
    VideoPlayerController? createdController;
    Player? createdPlayer;
    VideoController? createdMediaController;
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
              ? safeTransientMediaSource(widget.sourcePath) ?? ''
              : '');
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
            resolvedPath = '';
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
      if (source.trim().isEmpty) {
        throw StateError('Video source is missing.');
      }
      if (isWindowsVideoPlayback) {
        if (!validation.isNetwork && await isNativeVideoFileMissing(source)) {
          throw StateError('Video file is missing or empty.');
        }
        final player = Player();
        final mediaController = VideoController(player);
        createdPlayer = player;
        createdMediaController = mediaController;
        await player.open(Media(source), play: false);
        await _applyMediaKitSettings(
          player,
          isCurrent: () => mounted && generation == _initializationGeneration,
        );
        if (!mounted || generation != _initializationGeneration) {
          await _disposeRuntime(
            player: player,
            source: resolved,
            byteSource: materializedByteSource,
          );
          return;
        }
      } else {
        final controller = validation.isNetwork || kIsWeb
            ? VideoPlayerController.networkUrl(Uri.parse(source))
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
        await controller.setLooping(_looping);
        await _applyVideoSettings(
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
      _controller = createdController;
      _mediaPlayer = createdPlayer;
      _mediaController = createdMediaController;
      _positionSubscription = createdPlayer?.stream.position.listen(
        _enforceTrim,
      );
      createdController?.addListener(_handleVideoTick);
      setState(() {
        _mediaReady = createdMediaController != null;
        _initialized = true;
      });
    } catch (_) {
      await _disposeRuntime(
        controller: createdController,
        player: createdPlayer,
        source: resolved,
        byteSource: materializedByteSource,
      );
      if (mounted && generation == _initializationGeneration) {
        setState(() => _error = 'Video could not be loaded on this platform.');
      }
    }
  }

  Future<void> _disposeRuntime({
    VideoPlayerController? controller,
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

  @override
  void didUpdateWidget(covariant VideoPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.sourcePath != widget.sourcePath ||
        oldWidget.networkUrl != widget.networkUrl ||
        oldWidget.storagePath != widget.storagePath ||
        oldWidget.artifactReference != widget.artifactReference ||
        oldWidget.sourceResolver != widget.sourceResolver;
    if (sourceChanged) {
      _init();
      return;
    }
    if (oldWidget.timeline != widget.timeline) {
      final generation = _initializationGeneration;
      final timelineGeneration = ++_timelineGeneration;
      final controller = _controller;
      final player = _mediaPlayer;
      final timeline = widget.timeline;
      if (controller != null) {
        unawaited(
          _applyVideoSettings(
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
      if (player != null) {
        unawaited(
          _applyMediaKitSettings(
            player,
            timeline: timeline,
            isCurrent: () =>
                mounted &&
                generation == _initializationGeneration &&
                timelineGeneration == _timelineGeneration &&
                identical(player, _mediaPlayer),
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
        player: _mediaPlayer,
        positionSubscription: _positionSubscription,
        source: _resolvedSource,
        byteSource: _byteSource,
      ),
    );
    super.dispose();
  }

  Future<void> _applyVideoSettings(
    VideoPlayerController controller, {
    MediaTimeline? timeline,
    bool Function()? isCurrent,
  }) async {
    timeline ??= widget.timeline;
    final volume = (timeline?.volume ?? 1.0).clamp(0.0, 1.0).toDouble();
    final muted = timeline?.muted ?? _muted;
    if (isCurrent?.call() == false) return;
    _volume = volume;
    _muted = muted;
    await controller.setPlaybackSpeed(
      (timeline?.playbackSpeed ?? 1.0).clamp(0.25, 4.0).toDouble(),
    );
    if (isCurrent?.call() == false) return;
    await controller.setVolume(muted ? 0 : volume);
    final startMs = timeline?.trimStartMs ?? 0;
    if (startMs > 0) {
      if (isCurrent?.call() == false) return;
      await controller.seekTo(Duration(milliseconds: startMs));
    }
  }

  Future<void> _applyMediaKitSettings(
    Player player, {
    MediaTimeline? timeline,
    bool Function()? isCurrent,
  }) async {
    timeline ??= widget.timeline;
    final volume = (timeline?.volume ?? 1.0).clamp(0.0, 1.0).toDouble();
    final muted = timeline?.muted ?? _muted;
    if (isCurrent?.call() == false) return;
    _volume = volume;
    _muted = muted;
    await player.setRate(
      (timeline?.playbackSpeed ?? 1.0).clamp(0.25, 4.0).toDouble(),
    );
    if (isCurrent?.call() == false) return;
    await player.setVolume(
      muted ? 0 : (volume * 100).clamp(0.0, 100.0).toDouble(),
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
    if (mounted) setState(() {});
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
    if (_mediaPlayer != null) {
      unawaited(_mediaPlayer!.pause());
      unawaited(_mediaPlayer!.seek(Duration(milliseconds: startMs)));
    } else if (_controller != null) {
      unawaited(_controller!.pause());
      unawaited(_controller!.seekTo(Duration(milliseconds: startMs)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final controller = _controller;
    final mediaController = _mediaController;
    return UiPageScaffold(
      title: Text(
        'VIDEO PLAYER',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      leading: UiIconButton(
        icon: Icons.arrow_back,
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      actions: [
        if (widget.onDownload != null)
          UiIconButton(
            icon: Icons.download_outlined,
            tooltip: 'Download video',
            onPressed: widget.onDownload,
          ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controlsHeight = (constraints.maxHeight * 0.4)
              .clamp(64.0, 180.0)
              .toDouble();
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: _error != null
                      ? _buildError()
                      : _mediaReady && mediaController != null
                      ? MaterialVideoControlsTheme(
                          normal: _materialKitVideoTheme(tokens),
                          fullscreen: _materialKitVideoTheme(tokens),
                          child: MaterialDesktopVideoControlsTheme(
                            normal: _desktopKitVideoTheme(tokens),
                            fullscreen: _desktopKitVideoTheme(tokens),
                            child: Video(
                              controller: mediaController,
                              controls: AdaptiveVideoControls,
                            ),
                          ),
                        )
                      : !_initialized || controller == null
                      ? const UiProgressIndicator(
                          semanticsLabel: 'Loading video',
                        )
                      : AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                ),
              ),
              if (_initialized && controller != null ||
                  (widget.caption != null && widget.caption!.isNotEmpty))
                SizedBox(
                  height: controlsHeight,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_initialized && controller != null)
                          _buildControls(controller),
                        if (widget.caption != null &&
                            widget.caption!.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 96),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Text(
                                widget.caption!,
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildError() {
    final tokens = context.appTokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: tokens.danger, size: 36),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _error!,
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: tokens.danger),
        ),
        const SizedBox(height: AppSpacing.md),
        UiButton(
          onPressed: _init,
          variant: UiButtonVariant.outline,
          child: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildControls(VideoPlayerController controller) {
    final tokens = context.appTokens;
    return UiSurface(
      color: tokens.panelElevated,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final playButton = UiIconButton(
                icon: controller.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                tooltip: controller.value.isPlaying
                    ? 'Pause video'
                    : 'Play video',
                size: UiButtonSize.lg,
                onPressed: () => setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                }),
              );
              final progress = VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: tokens.accent,
                  bufferedColor: tokens.videoBuffered,
                  backgroundColor: tokens.videoBackground,
                ),
              );
              final durationLabel = Text(
                '${_format(controller.value.position)} / '
                '${_format(controller.value.duration)}',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: tokens.textMuted,
                  fontFamily: 'monospace',
                ),
              );
              if (constraints.maxWidth < AppBreakpoints.compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    progress,
                    Row(
                      children: [
                        playButton,
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: durationLabel,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  playButton,
                  Expanded(child: progress),
                  const SizedBox(width: AppSpacing.sm),
                  durationLabel,
                ],
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.onDownload != null)
                UiIconButton(
                  icon: Icons.download_outlined,
                  tooltip: 'Download video',
                  onPressed: widget.onDownload,
                ),

              UiIconButton(
                icon: _muted ? Icons.volume_off : Icons.volume_up,
                tooltip: _muted ? 'Unmute video' : 'Mute video',
                onPressed: () {
                  setState(() => _muted = !_muted);
                  controller.setVolume(_muted ? 0 : _volume);
                },
              ),
              UiIconButton(
                icon: _looping ? Icons.repeat_one : Icons.repeat,
                tooltip: _looping ? 'Disable loop' : 'Enable loop',
                selected: _looping,
                onPressed: () {
                  setState(() => _looping = !_looping);
                  controller.setLooping(_looping);
                },
              ),
              UiMenuButton<double>(
                tooltip: 'Playback speed',
                icon: Icons.speed,
                items: const [
                  UiMenuAction(value: 0.25, icon: Icons.speed, label: '0.25x'),
                  UiMenuAction(value: 0.5, icon: Icons.speed, label: '0.5x'),
                  UiMenuAction(value: 0.75, icon: Icons.speed, label: '0.75x'),
                  UiMenuAction(value: 1.0, icon: Icons.speed, label: '1.0x'),
                  UiMenuAction(value: 1.25, icon: Icons.speed, label: '1.25x'),
                  UiMenuAction(value: 1.5, icon: Icons.speed, label: '1.5x'),
                  UiMenuAction(value: 2.0, icon: Icons.speed, label: '2.0x'),
                  UiMenuAction(value: 3.0, icon: Icons.speed, label: '3.0x'),
                  UiMenuAction(value: 4.0, icon: Icons.speed, label: '4.0x'),
                ],
                onSelected: (speed) {
                  controller.setPlaybackSpeed(speed);
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
