import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/media/data/transient_media_source_resolver.dart';
import 'package:varian/features/media/data/transient_media_source_types.dart';

class InlineAudioCardWidget extends StatefulWidget {
  final String? sourcePath;
  final String? networkUrl;
  final String? storagePath;
  final String? audioArtifactReference;
  final TransientMediaSourceResolver? sourceResolver;
  final String title;
  final String artist;
  final String description;
  final String durationText;
  final ValueChanged<Offset>? onDragDelta;
  final bool looping;
  final double playbackSpeed;
  final MediaTimeline? timeline;
  final VoidCallback? onOpenPlayer;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;

  const InlineAudioCardWidget({
    super.key,
    this.sourcePath,
    this.networkUrl,
    this.storagePath,
    this.audioArtifactReference,
    this.sourceResolver,
    required this.title,
    required this.artist,
    required this.description,
    required this.durationText,
    this.onDragDelta,
    this.looping = false,
    this.playbackSpeed = 1.0,
    this.timeline,
    this.onOpenPlayer,
    this.onTap,
    this.onSecondaryTap,
  });

  @override
  State<InlineAudioCardWidget> createState() => _InlineAudioCardWidgetState();
}

class _InlineAudioCardWidgetState extends State<InlineAudioCardWidget> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSubscription;
  String? _error;
  TransientMediaSource? _resolvedSource;
  bool _muted = false;
  double _volume = 1;

  @override
  void initState() {
    super.initState();
    _muted = widget.timeline?.muted ?? false;
    _init();
  }

  Future<void> _init() async {
    try {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      await _resolvedSource?.dispose();
      _resolvedSource = null;
      final resolver = widget.sourceResolver;
      final resolved = resolver == null
          ? null
          : await resolver.resolveAudio(
              AudioPayload(
                storagePath: widget.storagePath,
                audioArtifactReference: widget.audioArtifactReference,
                audioPath: widget.sourcePath,
                audioUrl: widget.networkUrl,
                trackName: widget.title,
                artist: widget.artist,
                description: widget.description,
                durationText: widget.durationText,
                mediaTimeline: widget.timeline,
              ),
            );
      _resolvedSource = resolved;
      final source =
          resolved?.uri?.toString() ??
          resolved?.path ??
          (widget.sourceResolver == null
              ? safeTransientMediaSource(widget.networkUrl) ??
                    safeTransientMediaSource(widget.sourcePath)
              : safeTransientMediaSource(widget.sourcePath));
      if (resolved?.bytes != null && resolved!.bytes!.isNotEmpty) {
        await _player.setAudioSource(
          AudioSource.uri(
            UriData.fromBytes(resolved.bytes!, mimeType: 'audio/mpeg').uri,
          ),
        );
      } else if (source == null || source.trim().isEmpty) {
        throw Exception('Audio source is empty');
      } else if (resolved?.path != null && !kIsWeb) {
        if (!await File(resolved!.path!).exists()) {
          throw Exception('Audio file not found');
        }
        await _player.setFilePath(resolved.path!);
      } else if (widget.networkUrl == null &&
          resolved?.uri == null &&
          !kIsWeb) {
        if (!await File(source).exists()) {
          throw Exception('Audio file not found');
        }
        await _player.setFilePath(source);
      } else {
        await _player.setUrl(source);
      }
      await _player.setLoopMode(widget.looping ? LoopMode.one : LoopMode.off);
      await _applyTimelineSettings();
      _positionSubscription = _player.positionStream.listen(_enforceTrim);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void didUpdateWidget(covariant InlineAudioCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourcePath != widget.sourcePath ||
        oldWidget.networkUrl != widget.networkUrl ||
        oldWidget.storagePath != widget.storagePath ||
        oldWidget.audioArtifactReference != widget.audioArtifactReference ||
        oldWidget.sourceResolver != widget.sourceResolver) {
      _error = null;
      _player.stop();
      _init();
    } else if (oldWidget.timeline != widget.timeline ||
        oldWidget.playbackSpeed != widget.playbackSpeed ||
        oldWidget.looping != widget.looping) {
      unawaited(_applyTimelineSettings());
    }
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    unawaited(_resolvedSource?.dispose());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return GestureDetector(
      onTap: widget.onTap,
      onPanUpdate: (details) => widget.onDragDelta?.call(details.delta),
      onSecondaryTapUp: (_) => widget.onSecondaryTap?.call(),
      onDoubleTap: widget.onOpenPlayer,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.panel,
          border: Border.all(color: tokens.panelBorder),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm + AppSpacing.xxs,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xs + AppSpacing.xxs,
        ),
        child: _error != null ? _errorView(context) : _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final tokens = context.appTokens;
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        final duration = _player.duration ?? Duration.zero;
        final ratio = duration.inMilliseconds == 0
            ? 0.0
            : (position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              );
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxHeight < 100) {
              return Row(
                children: [
                  StreamBuilder<PlayerState>(
                    stream: _player.playerStateStream,
                    builder: (context, snapshot) {
                      final playing = snapshot.data?.playing ?? false;
                      return UiIconButton(
                        icon: playing ? Icons.pause : Icons.play_arrow,
                        tooltip: playing ? 'Pause' : 'Play',
                        size: UiButtonSize.sm,
                        onPressed: () =>
                            playing ? _player.pause() : _player.play(),
                      );
                    },
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.text,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.artist.isEmpty ? '' : '${widget.artist} • '}${_format(duration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 9,
                          ),
                        ),
                        const SizedBox(
                          height: AppSpacing.xxs + AppSpacing.xxs / 2,
                        ),
                        UiLinearProgressIndicator(
                          value: ratio,
                          semanticsLabel: 'Audio playback progress',
                          height: 3,
                        ),
                      ],
                    ),
                  ),
                  UiIconButton(
                    icon: _muted ? Icons.volume_off : Icons.volume_up,
                    tooltip: _muted ? 'Unmute' : 'Mute',
                    size: UiButtonSize.sm,
                    onPressed: _toggleMute,
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      builder: (context, snapshot) {
                        final playing = snapshot.data?.playing ?? false;
                        return UiIconButton(
                          icon: playing ? Icons.pause : Icons.play_arrow,
                          tooltip: playing ? 'Pause' : 'Play',
                          size: UiButtonSize.sm,
                          onPressed: () =>
                              playing ? _player.pause() : _player.play(),
                        );
                      },
                    ),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.text,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    UiMenuButton<double>(
                      tooltip: 'Playback speed',
                      icon: Icons.speed,
                      items: const [
                        UiMenuAction(
                          value: 0.75,
                          icon: Icons.speed,
                          label: '0.75x',
                        ),
                        UiMenuAction(
                          value: 1.0,
                          icon: Icons.speed,
                          label: '1.0x',
                        ),
                        UiMenuAction(
                          value: 1.25,
                          icon: Icons.speed,
                          label: '1.25x',
                        ),
                        UiMenuAction(
                          value: 1.5,
                          icon: Icons.speed,
                          label: '1.5x',
                        ),
                        UiMenuAction(
                          value: 2.0,
                          icon: Icons.speed,
                          label: '2.0x',
                        ),
                      ],
                      onSelected: _player.setSpeed,
                    ),
                  ],
                ),
                Text(
                  widget.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.textMuted, fontSize: 9),
                ),
                if (widget.timeline?.waveformSamples.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                  SizedBox(
                    height: 32,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _AudioWaveformPainter(
                        samples: widget.timeline!.waveformSamples,
                        markers: widget.timeline!.markers,
                        sourceDurationMs: widget.timeline!.sourceDurationMs,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xxs + AppSpacing.xxs / 2),
                UiLinearProgressIndicator(
                  value: ratio,
                  semanticsLabel: 'Audio playback progress',
                  height: 3,
                ),
                Row(
                  children: [
                    Text(
                      '${_format(position)} / ${_format(duration)}',
                      style: TextStyle(color: tokens.textMuted, fontSize: 8),
                    ),
                    const Spacer(),
                    UiIconButton(
                      icon: _muted ? Icons.volume_off : Icons.volume_up,
                      tooltip: _muted ? 'Unmute' : 'Mute',
                      size: UiButtonSize.sm,
                      onPressed: _toggleMute,
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _errorView(BuildContext context) {
    final tokens = context.appTokens;
    return Row(
      children: [
        Icon(Icons.error_outline, color: tokens.danger, size: 18),
        const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
        Expanded(
          child: Text(
            'Audio unavailable',
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: tokens.danger),
          ),
        ),
        UiIconButton(
          icon: Icons.refresh,
          tooltip: 'Retry',
          size: UiButtonSize.sm,
          onPressed: _init,
        ),
      ],
    );
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _player.setVolume(_muted ? 0 : _volume);
  }

  Future<void> _applyTimelineSettings() async {
    final timeline = widget.timeline;
    _volume = (timeline?.volume ?? 1.0).clamp(0.0, 1.0).toDouble();
    _muted = timeline?.muted ?? false;
    await _player.setSpeed(
      (timeline?.playbackSpeed ?? widget.playbackSpeed).clamp(0.25, 4.0),
    );
    await _player.setVolume(_muted ? 0 : _volume);
    final startMs = timeline?.trimStartMs ?? 0;
    if (startMs > 0) {
      await _player.seek(Duration(milliseconds: startMs));
    }
  }

  void _enforceTrim(Duration position) {
    final endMs = widget.timeline?.trimEndMs ?? 0;
    if (endMs <= 0 || position.inMilliseconds < endMs) return;
    final startMs = widget.timeline?.trimStartMs ?? 0;
    if (widget.looping) {
      unawaited(_player.seek(Duration(milliseconds: startMs)));
    } else {
      unawaited(_player.pause());
    }
  }

  String _format(Duration value) =>
      '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

class _AudioWaveformPainter extends CustomPainter {
  final List<double> samples;
  final List<MediaMarker> markers;
  final int sourceDurationMs;

  const _AudioWaveformPainter({
    required this.samples,
    required this.markers,
    required this.sourceDurationMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bars = Paint()
      ..color = const Color(0xFF60A5FA)
      ..strokeWidth = 1.5;
    final markerPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 1;
    if (samples.isEmpty) return;
    final step = size.width / samples.length;
    for (var index = 0; index < samples.length; index++) {
      final amplitude = samples[index].clamp(0.0, 1.0).toDouble();
      final x = (index + 0.5) * step;
      final halfHeight = amplitude * size.height * 0.45;
      canvas.drawLine(
        Offset(x, size.height / 2 - halfHeight),
        Offset(x, size.height / 2 + halfHeight),
        bars,
      );
    }
    if (sourceDurationMs <= 0) return;
    for (final marker in markers) {
      final x = size.width * marker.positionMs / sourceDurationMs;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), markerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AudioWaveformPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.markers != markers ||
      oldDelegate.sourceDurationMs != sourceDurationMs;
}
