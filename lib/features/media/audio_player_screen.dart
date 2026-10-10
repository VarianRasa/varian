import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/media/data/transient_media_source_resolver.dart';
import 'package:varian/features/media/data/transient_media_source_types.dart';

class AudioPlayerScreen extends StatefulWidget {
  final String? sourcePath;
  final String? networkUrl;
  final String? storagePath;
  final String? audioArtifactReference;
  final TransientMediaSourceResolver? sourceResolver;
  final String title;
  final String artist;
  final MediaTimeline? timeline;

  const AudioPlayerScreen({
    super.key,
    this.sourcePath,
    this.networkUrl,
    this.storagePath,
    this.audioArtifactReference,
    this.sourceResolver,
    required this.title,
    required this.artist,
    this.timeline,
  });

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSubscription;
  String? _error;
  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  bool _muted = false;
  bool _trimEnded = false;
  TransientMediaSource? _resolvedSource;

  static const _playbackSpeeds = <double>[
    0.25,
    0.5,
    0.75,
    1,
    1.25,
    1.5,
    2,
    3,
    4,
  ];

  @override
  void initState() {
    super.initState();
    _volume = (widget.timeline?.volume ?? 1.0).clamp(0.0, 1.0).toDouble();
    _playbackSpeed = (widget.timeline?.playbackSpeed ?? 1.0)
        .clamp(0.25, 4.0)
        .toDouble();
    _muted = widget.timeline?.muted ?? false;
    _init();
  }

  Future<void> _init() async {
    try {
      await _resolvedSource?.dispose();
      _resolvedSource = null;
      final resolved = widget.sourceResolver == null
          ? null
          : await widget.sourceResolver!.resolveAudio(
              AudioPayload(
                storagePath: widget.storagePath,
                audioArtifactReference: widget.audioArtifactReference,
                audioPath: widget.sourcePath,
                audioUrl: widget.networkUrl,
                trackName: widget.title,
                artist: widget.artist,
                mediaTimeline: widget.timeline,
              ),
            );
      _resolvedSource = resolved;
      if (resolved?.bytes != null && resolved!.bytes!.isNotEmpty) {
        await _player.setAudioSource(
          AudioSource.uri(
            UriData.fromBytes(resolved.bytes!, mimeType: 'audio/mpeg').uri,
          ),
        );
      } else {
        final url =
            resolved?.uri?.toString() ??
            (widget.sourceResolver == null
                ? safeTransientMediaSource(widget.networkUrl) ??
                      safeTransientMediaSource(widget.sourcePath)
                : safeTransientMediaSource(widget.sourcePath));
        if (resolved?.path != null && !kIsWeb) {
          await _player.setFilePath(resolved!.path!);
        } else if (url != null) {
          await _player.setUrl(url);
        } else if (widget.sourcePath != null && !kIsWeb) {
          await _player.setFilePath(widget.sourcePath!);
        } else {
          throw Exception('Audio source is empty');
        }
      }
      if (!mounted) return;
      await _player.setLoopMode(LoopMode.off);
      await _player.setSpeed(_playbackSpeed);
      await _player.setVolume(_muted ? 0 : _volume);
      final startMs = widget.timeline?.trimStartMs ?? 0;
      if (startMs > 0) {
        await _player.seek(Duration(milliseconds: startMs));
      }
      _positionSubscription = _player.positionStream.listen(_enforceTrim);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    unawaited(_resolvedSource?.dispose());
    _player.dispose();
    super.dispose();
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
    unawaited(_player.pause());
    unawaited(_player.seek(Duration(milliseconds: startMs)));
  }

  String? _activeSubtitle(Duration position) {
    final tracks = widget.timeline?.subtitleTracks ?? const [];
    for (final track in tracks) {
      if (!track.enabled) continue;
      for (final cue in track.cues) {
        if (position.inMilliseconds >= cue.startMs &&
            position.inMilliseconds < cue.endMs) {
          return cue.text;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final contentWidth =
        (MediaQuery.sizeOf(context).width - AppSpacing.page * 2)
            .clamp(0.0, 420.0)
            .toDouble();
    final seekWidth = contentWidth.clamp(0.0, 360.0).toDouble();
    final volumeWidth = (contentWidth - 100).clamp(0.0, 180.0).toDouble();
    final speedWidth = (contentWidth * 0.4).clamp(136.0, 160.0).toDouble();
    return UiPageScaffold(
      title: Text(
        'AUDIO PLAYER',
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: _error != null
              ? Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentWidth),
                    child: UiSurface(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, color: tokens.danger),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _error!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: tokens.danger),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          UiButton(
                            onPressed: () {
                              setState(() => _error = null);
                              _init();
                            },
                            prefix: const Icon(Icons.refresh),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : SizedBox(
                  width: contentWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.audiotrack, size: 64, color: tokens.accent),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: tokens.text,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        widget.artist,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                      if (widget.timeline?.waveformSamples.isNotEmpty ==
                          true) ...[
                        const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                        SizedBox(
                          width: contentWidth,
                          height: 72,
                          child: CustomPaint(
                            painter: _AudioPlayerWaveformPainter(
                              samples: widget.timeline!.waveformSamples,
                              markers: widget.timeline!.markers,
                              sourceDurationMs:
                                  widget.timeline!.sourceDurationMs,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      StreamBuilder<PlayerState>(
                        stream: _player.playerStateStream,
                        builder: (context, snapshot) {
                          final playing = snapshot.data?.playing ?? false;
                          return UiIconButton(
                            icon: playing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            tooltip: playing ? 'Pause audio' : 'Play audio',
                            size: UiButtonSize.lg,
                            onPressed: () {
                              playing ? _player.pause() : _player.play();
                            },
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      StreamBuilder<Duration>(
                        stream: _player.positionStream,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final duration = _player.duration ?? Duration.zero;
                          final durationMs = duration.inMilliseconds;
                          final normalized = durationMs <= 0
                              ? 0.0
                              : (position.inMilliseconds / durationMs).clamp(
                                  0.0,
                                  1.0,
                                );
                          return Column(
                            children: [
                              SizedBox(
                                width: seekWidth,
                                child: UiSlider(
                                  value: normalized,
                                  label: 'Audio position',
                                  onChanged: (value) => _player.seek(
                                    Duration(
                                      milliseconds: (value * durationMs)
                                          .round(),
                                    ),
                                  ),
                                  semanticValueFormatterCallback: (value) =>
                                      _format(
                                        Duration(
                                          milliseconds: (value * durationMs)
                                              .round(),
                                        ),
                                      ),
                                ),
                              ),
                              Text(
                                '${_format(position)} / ${_format(duration)}',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: tokens.textMuted,
                                      fontFamily: 'monospace',
                                    ),
                              ),
                              if (_activeSubtitle(position) != null) ...[
                                const SizedBox(
                                  height: AppSpacing.sm + AppSpacing.xxs,
                                ),
                                Text(
                                  _activeSubtitle(position)!,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: tokens.text,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          UiIconButton(
                            icon: _muted ? Icons.volume_off : Icons.volume_up,
                            tooltip: _muted ? 'Unmute audio' : 'Mute audio',
                            onPressed: () {
                              setState(() => _muted = !_muted);
                              _player.setVolume(_muted ? 0 : _volume);
                            },
                          ),
                          SizedBox(
                            width: volumeWidth,
                            child: UiSlider(
                              key: const ValueKey('audio-volume-slider'),
                              value: _volume,
                              divisions: 100,
                              onChanged: (value) {
                                final volume = value.clamp(0.0, 1.0).toDouble();
                                setState(() {
                                  _volume = volume;
                                  _muted = false;
                                });
                                _player.setVolume(volume);
                              },
                              semanticValueFormatterCallback: (value) =>
                                  '${(value * 100).round()}%',
                            ),
                          ),
                          SizedBox(
                            width: speedWidth,
                            child: UiSelect<double>(
                              key: const ValueKey('audio-speed-select'),
                              hint: 'Speed',
                              items: {
                                for (final speed in _playbackSpeeds)
                                  '${speed}x': speed,
                              },
                              value: _playbackSpeed,
                              onChanged: (speed) {
                                if (speed == null) return;
                                setState(() => _playbackSpeed = speed);
                                _player.setSpeed(speed);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _AudioPlayerWaveformPainter extends CustomPainter {
  final List<double> samples;
  final List<MediaMarker> markers;
  final int sourceDurationMs;

  const _AudioPlayerWaveformPainter({
    required this.samples,
    required this.markers,
    required this.sourceDurationMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bars = Paint()
      ..color = const Color(0xFF60A5FA)
      ..strokeWidth = 2;
    final markerPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 1.5;
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
  bool shouldRepaint(covariant _AudioPlayerWaveformPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.markers != markers ||
      oldDelegate.sourceDurationMs != sourceDurationMs;
}
