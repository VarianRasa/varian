import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:varian/domain/models/media_timeline.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../app/widgets/ui_primitives.dart';

class MediaTimelineEditorDialog extends StatefulWidget {
  final MediaTimeline initialTimeline;
  final String mediaTitle;

  const MediaTimelineEditorDialog({
    required this.initialTimeline,
    this.mediaTitle = 'Media',
    super.key,
  });

  @override
  State<MediaTimelineEditorDialog> createState() =>
      _MediaTimelineEditorDialogState();
}

class _MediaTimelineEditorDialogState extends State<MediaTimelineEditorDialog> {
  late MediaTimeline _timeline;
  late final TextEditingController _trimStartController;
  late final TextEditingController _trimEndController;
  late final TextEditingController _splitController;
  late final TextEditingController _markerPositionController;
  late final TextEditingController _markerLabelController;
  late final TextEditingController _posterPositionController;
  late final TextEditingController _cueStartController;
  late final TextEditingController _cueEndController;
  late final TextEditingController _cueTextController;
  late final TextEditingController _captionController;
  String? _selectedTrackId;

  @override
  void initState() {
    super.initState();
    _timeline = widget.initialTimeline.normalized();
    _trimStartController = TextEditingController(
      text: _seconds(_timeline.trimStartMs),
    );
    _trimEndController = TextEditingController(
      text: _seconds(_timeline.trimEndMs),
    );
    _splitController = TextEditingController();
    _markerPositionController = TextEditingController();
    _markerLabelController = TextEditingController();
    _posterPositionController = TextEditingController(
      text: _timeline.posterPositionMs == null
          ? ''
          : _seconds(_timeline.posterPositionMs!),
    );
    _cueStartController = TextEditingController();
    _cueEndController = TextEditingController();
    _cueTextController = TextEditingController();
    _captionController = TextEditingController(text: _timeline.caption ?? '');
    _selectedTrackId = _timeline.subtitleTracks.firstOrNull?.id;
  }

  @override
  void dispose() {
    _trimStartController.dispose();
    _trimEndController.dispose();
    _splitController.dispose();
    _markerPositionController.dispose();
    _markerLabelController.dispose();
    _posterPositionController.dispose();
    _cueStartController.dispose();
    _cueEndController.dispose();
    _cueTextController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  String _seconds(int milliseconds) =>
      (math.max(0, milliseconds) / 1000).toStringAsFixed(3);

  int? _milliseconds(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed.isNegative) return null;
    return (parsed * 1000).round();
  }

  void _applyTrim() {
    final start = _milliseconds(_trimStartController.text);
    final end = _milliseconds(_trimEndController.text);
    if (start == null || end == null || end <= start) {
      _showError('Trim end must be greater than trim start.');
      return;
    }
    setState(() => _timeline = _timeline.trim(startMs: start, endMs: end));
  }

  void _applySplit() {
    final position = _milliseconds(_splitController.text);
    if (position == null || position <= 0 || position >= _timeline.durationMs) {
      _showError('Split position must be inside the edited timeline.');
      return;
    }
    setState(() => _timeline = _timeline.splitAt(position));
    _splitController.clear();
  }

  void _addMarker() {
    final position = _milliseconds(_markerPositionController.text);
    if (position == null || position > _timeline.sourceDurationMs) {
      _showError('Marker position is outside the source duration.');
      return;
    }
    final id = 'marker-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _timeline = _timeline.upsertMarker(
        MediaMarker(
          id: id,
          positionMs: position,
          label: _markerLabelController.text.trim(),
        ),
      );
      _markerPositionController.clear();
      _markerLabelController.clear();
    });
  }

  void _setPoster() {
    final position = _milliseconds(_posterPositionController.text);
    if (position == null || position > _timeline.sourceDurationMs) {
      _showError('Poster position is outside the source duration.');
      return;
    }
    setState(() => _timeline = _timeline.copyWith(posterPositionMs: position));
  }

  void _addSubtitleTrack() {
    final id = 'track-${DateTime.now().microsecondsSinceEpoch}';
    final track = MediaSubtitleTrack(id: id, label: 'Subtitles');
    setState(() {
      _timeline = _timeline.upsertSubtitleTrack(track);
      _selectedTrackId = id;
    });
  }

  void _addCue() {
    final start = _milliseconds(_cueStartController.text);
    final end = _milliseconds(_cueEndController.text);
    final text = _cueTextController.text.trim();
    if (start == null || end == null || end <= start || text.isEmpty) {
      _showError('Subtitle cue needs valid start, end, and text.');
      return;
    }
    var track = _selectedTrack;
    if (track == null) {
      _addSubtitleTrack();
      track = _selectedTrack;
    }
    if (track == null) return;
    final updated = track.upsertCue(
      MediaSubtitleCue(
        id: 'cue-${DateTime.now().microsecondsSinceEpoch}',
        startMs: start,
        endMs: end,
        text: text,
      ),
    );
    setState(() {
      _timeline = _timeline.upsertSubtitleTrack(updated).normalized();
      _cueStartController.clear();
      _cueEndController.clear();
      _cueTextController.clear();
    });
  }

  MediaSubtitleTrack? get _selectedTrack {
    for (final track in _timeline.subtitleTracks) {
      if (track.id == _selectedTrackId) return track;
    }
    return _timeline.subtitleTracks.firstOrNull;
  }

  void _showError(String message) {
    showUiToast(context, message, variant: UiToastVariant.error);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 720);
    final maxWidth = AppResponsive.dialogWidth(context, preferred: 860);
    return UiDialog(
      semanticsLabel: 'Media timeline editor',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.movie_outlined, color: context.appTokens.accent),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      '${widget.mediaTitle} timeline',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close media timeline',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildWaveform(theme),
                      const SizedBox(height: AppSpacing.md),
                      _buildClipSection(theme),
                      const SizedBox(height: AppSpacing.md),
                      _buildPlaybackSection(theme),
                      const SizedBox(height: AppSpacing.md),
                      _buildMarkerSection(theme),
                      const SizedBox(height: AppSpacing.md),
                      _buildSubtitleSection(theme),
                      const SizedBox(height: AppSpacing.md),
                      _buildPosterAndCaptionSection(theme),
                      const SizedBox(height: AppSpacing.md),
                      _buildArtifactSection(theme),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    variant: UiButtonVariant.ghost,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  UiButton(
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(_timeline.normalized()),
                    prefix: const Icon(Icons.check, size: 16),
                    child: const Text('Apply timeline'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaveform(ThemeData theme) => _section(
    title: 'Waveform',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 82,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.appTokens.panelElevated,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: CustomPaint(
              painter: _WaveformPainter(
                samples: _timeline.waveformSamples,
                markers: _timeline.markers,
                sourceDurationMs: _timeline.sourceDurationMs,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${formatMediaDurationMs(_timeline.durationMs)} edited · ${formatMediaDurationMs(_timeline.sourceDurationMs)} source · ${_timeline.normalizedClips.length} clip(s)',
          style: theme.textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _buildClipSection(ThemeData theme) => _section(
    title: 'Clips and trim',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formRow([
          _field(
            controller: _trimStartController,
            label: 'Trim start (seconds)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          _field(
            controller: _trimEndController,
            label: 'Trim end (seconds)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          UiButton(
            variant: UiButtonVariant.ghost,
            onPressed: _applyTrim,
            child: const Text('Trim'),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        _formRow([
          _field(
            controller: _splitController,
            label: 'Split at edited position (seconds)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          UiButton(
            variant: UiButtonVariant.ghost,
            onPressed: _applySplit,
            child: const Text('Split'),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        if (_timeline.normalizedClips.isEmpty)
          const Text('No enabled clips. Apply trim or reset the timeline.'),
        for (final clip in _timeline.normalizedClips)
          _timelineRow(
            leading: const Icon(Icons.video_file_outlined, size: 18),
            title: Text(
              '${formatMediaDurationMs(clip.startMs)} – ${formatMediaDurationMs(clip.endMs)}',
            ),
            subtitle: Text(
              '${formatMediaDurationMs(clip.durationMs)} · ${clip.id}',
            ),
            trailing: UiIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Remove clip',
              onPressed: _timeline.normalizedClips.length <= 1
                  ? null
                  : () => setState(
                      () => _timeline = _timeline.removeClip(clip.id),
                    ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: UiButton(
            variant: UiButtonVariant.ghost,
            onPressed: () =>
                setState(() => _timeline = _timeline.copyWith(clips: const [])),
            prefix: const Icon(Icons.restart_alt, size: 16),
            child: const Text('Reset full source'),
          ),
        ),
      ],
    ),
  );

  Widget _buildPlaybackSection(ThemeData theme) => _section(
    title: 'Playback',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UiSelect<double>(
          label: 'Speed',
          items: {
            for (final speed in <double>[
              0.25,
              0.5,
              0.75,
              1,
              1.25,
              1.5,
              2,
              3,
              4,
            ])
              '${speed}x': speed,
          },
          value:
              <double>[
                0.25,
                0.5,
                0.75,
                1,
                1.25,
                1.5,
                2,
                3,
                4,
              ].contains(_timeline.playbackSpeed)
              ? _timeline.playbackSpeed
              : 1.0,
          onChanged: (speed) {
            if (speed == null) return;
            setState(
              () => _timeline = _timeline.copyWith(playbackSpeed: speed),
            );
          },
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Volume'),
            Row(
              children: [
                Expanded(
                  child: UiSlider(
                    value: _timeline.volume,
                    divisions: 20,
                    onChanged: (value) => setState(
                      () => _timeline = _timeline.copyWith(
                        volume: value.clamp(0.0, 1.0).toDouble(),
                      ),
                    ),
                    semanticValueFormatterCallback: (value) =>
                        '${(value * 100).round()}%',
                  ),
                ),
                Text('${(_timeline.volume * 100).round()}%'),
              ],
            ),
          ],
        ),
        UiSwitch(
          label: const Text('Muted'),
          value: _timeline.muted,
          onChange: (value) =>
              setState(() => _timeline = _timeline.copyWith(muted: value)),
        ),
      ],
    ),
  );

  Widget _buildMarkerSection(ThemeData theme) => _section(
    title: 'Markers',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formRow([
          _field(
            controller: _markerPositionController,
            label: 'Position (seconds)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          _field(controller: _markerLabelController, label: 'Label'),
          UiButton(
            variant: UiButtonVariant.ghost,
            onPressed: _addMarker,
            child: const Text('Add'),
          ),
        ]),
        const SizedBox(height: AppSpacing.xs),
        if (_timeline.markers.isEmpty)
          const Text('No markers yet.')
        else
          for (final marker in _timeline.markers)
            _timelineRow(
              leading: Icon(
                Icons.flag,
                size: 18,
                color: marker.colorArgb == null
                    ? theme.colorScheme.primary
                    : Color(marker.colorArgb!),
              ),
              title: Text(
                marker.label.trim().isEmpty ? 'Untitled marker' : marker.label,
              ),
              subtitle: Text(formatMediaDurationMs(marker.positionMs)),
              trailing: UiIconButton(
                tooltip: 'Remove marker',
                icon: Icons.delete_outline,
                onPressed: () => setState(
                  () => _timeline = _timeline.removeMarker(marker.id),
                ),
              ),
            ),
      ],
    ),
  );

  Widget _buildSubtitleSection(ThemeData theme) => _section(
    title: 'Subtitle tracks',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formRow([
          UiSelect<String>(
            label: 'Subtitle track',
            items: {
              for (final track in _timeline.subtitleTracks)
                '${track.label} (${track.language})': track.id,
            },
            value: _selectedTrackId,
            onChanged: (value) => setState(() => _selectedTrackId = value),
          ),
          UiButton(
            variant: UiButtonVariant.ghost,
            onPressed: _addSubtitleTrack,
            child: const Text('New track'),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        _formRow([
          _field(
            controller: _cueStartController,
            label: 'Cue start (seconds)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          _field(
            controller: _cueEndController,
            label: 'Cue end (seconds)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          UiButton(
            variant: UiButtonVariant.ghost,
            onPressed: _addCue,
            child: const Text('Add cue'),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        _field(controller: _cueTextController, label: 'Cue text', maxLines: 2),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        if (_selectedTrack == null)
          const Text('Create a track to add subtitle cues.')
        else if (_selectedTrack!.cues.isEmpty)
          const Text('No cues in this track.')
        else
          for (final cue in _selectedTrack!.cues)
            _timelineRow(
              leading: const Icon(Icons.closed_caption_outlined, size: 18),
              title: Text(cue.text),
              subtitle: Text(
                '${formatMediaDurationMs(cue.startMs)} – ${formatMediaDurationMs(cue.endMs)}',
              ),
              trailing: UiIconButton(
                tooltip: 'Remove cue',
                icon: Icons.delete_outline,
                onPressed: () {
                  final track = _selectedTrack;
                  if (track == null) return;
                  setState(
                    () => _timeline = _timeline
                        .upsertSubtitleTrack(track.removeCue(cue.id))
                        .normalized(),
                  );
                },
              ),
            ),
      ],
    ),
  );

  Widget _buildPosterAndCaptionSection(ThemeData theme) => _section(
    title: 'Poster and caption',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formRow([
          _field(
            controller: _posterPositionController,
            label: 'Poster position (seconds)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          UiButton(
            variant: UiButtonVariant.ghost,
            onPressed: _setPoster,
            child: const Text('Set poster'),
          ),
          UiButton(
            variant: UiButtonVariant.ghost,
            onPressed: () => setState(
              () => _timeline = _timeline.copyWith(posterPositionMs: null),
            ),
            child: const Text('Clear'),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        _field(
          controller: _captionController,
          label: 'Caption',
          maxLines: 3,
          onChanged: (value) =>
              setState(() => _timeline = _timeline.copyWith(caption: value)),
        ),
      ],
    ),
  );

  Widget _buildArtifactSection(ThemeData theme) => _section(
    title: 'Media artifacts',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final kind in MediaArtifactKind.values)
          Builder(
            builder: (context) {
              final artifact = _timeline.artifacts.find(kind);
              return _timelineRow(
                leading: Icon(
                  artifact == null
                      ? Icons.radio_button_unchecked
                      : Icons.check_circle_outline,
                  size: 18,
                  color: artifact == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
                title: Text(kind.name),
                subtitle: Text(
                  artifact == null
                      ? 'Not generated'
                      : artifact.url ?? artifact.path ?? 'Available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        Text(
          'Artifacts are generated by the background media queue and kept separate from the original.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _timelineRow({
    required Widget leading,
    required Widget title,
    Widget? subtitle,
    Widget? trailing,
  }) {
    final tokens = context.appTokens;
    return UiSurface(
      color: tokens.panelElevated,
      borderRadius: BorderRadius.circular(tokens.controlRadius),
      bordered: false,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          SizedBox(
            width: AppControlSize.compact,
            child: Center(child: leading),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [title, ?subtitle],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.xs),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _formRow(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 560) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(height: AppSpacing.sm),
              children[index],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.sm),
            index == children.length - 1
                ? children[index]
                : Expanded(child: children[index]),
          ],
        ],
      );
    },
  );

  Widget _section({required String title, required Widget child}) => UiSurface(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    ),
  );

  Widget _field({
    TextEditingController? controller,
    required String label,
    TextInputType? keyboardType,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return UiTextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      label: label,
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final List<MediaMarker> markers;
  final int sourceDurationMs;

  const _WaveformPainter({
    required this.samples,
    required this.markers,
    required this.sourceDurationMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 2;
    final markerPaint = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 1.5;
    if (samples.isEmpty) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        linePaint,
      );
    } else {
      final step = size.width / samples.length;
      for (var index = 0; index < samples.length; index++) {
        final amplitude = samples[index].clamp(0.0, 1.0).toDouble();
        final x = (index + 0.5) * step;
        final halfHeight = amplitude * (size.height * 0.42);
        canvas.drawLine(
          Offset(x, size.height / 2 - halfHeight),
          Offset(x, size.height / 2 + halfHeight),
          linePaint,
        );
      }
    }
    if (sourceDurationMs <= 0) return;
    for (final marker in markers) {
      final x = size.width * marker.positionMs / sourceDurationMs;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), markerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.markers != markers ||
      oldDelegate.sourceDurationMs != sourceDurationMs;
}
