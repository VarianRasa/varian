import 'dart:math' as math;

enum MediaArtifactKind { original, proxy, thumbnail, waveform, preview, export }

enum MediaStoragePolicy { ephemeral, cache, durable }

enum MediaProcessingStatus {
  queued,
  running,
  retrying,
  succeeded,
  failed,
  cancelled,
}

int parseMediaDurationMs(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 0;
  final parts = trimmed.split(':');
  if (parts.length > 1) {
    var totalSeconds = 0.0;
    for (final part in parts) {
      final parsed = double.tryParse(part.trim());
      if (parsed == null || parsed.isNegative) return 0;
      totalSeconds = totalSeconds * 60 + parsed;
    }
    return math.max(0, (totalSeconds * 1000).round());
  }
  final seconds = double.tryParse(trimmed);
  if (seconds == null || seconds.isNegative) return 0;
  return math.max(0, (seconds * 1000).round());
}

String formatMediaDurationMs(int milliseconds) {
  final totalSeconds = math.max(0, milliseconds) ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

class MediaArtifact {
  final MediaArtifactKind kind;
  final String? path;
  final String? url;
  final String? reference;
  final String? mimeType;
  final int? sizeBytes;
  final String? checksum;

  const MediaArtifact({
    required this.kind,
    this.path,
    this.url,
    this.reference,
    this.mimeType,
    this.sizeBytes,
    this.checksum,
  });

  bool get isAvailable =>
      path?.trim().isNotEmpty == true ||
      url?.trim().isNotEmpty == true ||
      reference?.trim().isNotEmpty == true;

  bool get isPersistent => reference?.trim().isNotEmpty == true;

  factory MediaArtifact.fromJson(Map<String, dynamic> json) {
    // `path` and `url` are runtime delivery values. Older manifests used the
    // url field for logical `varian-media://` references, so accept that field
    // only when it validates as durable metadata.
    final durableReference =
        _durableMediaArtifactReference(json['reference'] as String?) ??
        _durableMediaArtifactReference(json['url'] as String?);
    return MediaArtifact(
      kind: MediaArtifactKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => MediaArtifactKind.preview,
      ),
      path: null,
      url: null,
      reference: durableReference,
      mimeType: _safeMediaMimeType(json['mimeType'] as String?),
      sizeBytes: _safeMediaSize(json['sizeBytes']),
      checksum: _safeMediaChecksum(json['checksum'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    final durableReference =
        _durableMediaArtifactReference(reference) ??
        _durableMediaArtifactReference(url);
    return {
      'kind': kind.name,
      // Local paths, object URLs, data URLs, signed URLs, and temporary
      // artifact handles must never cross the durable serialization boundary.
      'reference': ?durableReference,
      'mimeType': ?_safeMediaMimeType(mimeType),
      if (sizeBytes != null && sizeBytes! >= 0) 'sizeBytes': sizeBytes,
      'checksum': ?_safeMediaChecksum(checksum),
    };
  }

  /// Serializes only a durable owned artifact. Cache and ephemeral handles are
  /// runtime playback state and must not be retained by document persistence.
  Map<String, dynamic>? toPersistenceJson() {
    final durableReference = [reference, url]
        .map(_durableMediaArtifactReference)
        .whereType<String>()
        .firstWhere(
          (value) =>
              Uri.tryParse(value)?.host == MediaStoragePolicy.durable.name,
          orElse: () => '',
        );
    if (durableReference.isEmpty) return null;
    return {
      'kind': kind.name,
      'reference': durableReference,
      'mimeType': ?_safeMediaMimeType(mimeType),
      if (sizeBytes != null && sizeBytes! >= 0) 'sizeBytes': sizeBytes,
      'checksum': ?_safeMediaChecksum(checksum),
    };
  }

  MediaArtifact copyWith({
    MediaArtifactKind? kind,
    String? path,
    String? url,
    String? reference,
    String? mimeType,
    int? sizeBytes,
    String? checksum,
  }) => MediaArtifact(
    kind: kind ?? this.kind,
    path: path ?? this.path,
    url: url ?? this.url,
    reference: reference ?? this.reference,
    mimeType: mimeType ?? this.mimeType,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    checksum: checksum ?? this.checksum,
  );
}

String? _durableMediaArtifactReference(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty || normalized != value) {
    return null;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.scheme != 'varian-media' || uri.host.isEmpty) {
    return null;
  }
  if (uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    return null;
  }
  final policy = MediaStoragePolicy.values.any(
    (candidate) => candidate.name == uri.host,
  );
  final segments = uri.pathSegments;
  if (!policy || segments.length != 2) return null;
  final checksum = segments.first;
  final kind = segments.last;
  if (checksum.isEmpty ||
      !RegExp(r'^[A-Za-z0-9:_-]{1,256}$').hasMatch(checksum) ||
      !MediaArtifactKind.values.any((candidate) => candidate.name == kind)) {
    return null;
  }
  return normalized;
}

String? _safeMediaMimeType(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null ||
      normalized.isEmpty ||
      normalized != value?.trim().toLowerCase() ||
      normalized.length > 128 ||
      normalized.codeUnits.any((code) => code <= 0x20 || code == 0x7f) ||
      !RegExp(
        r'^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$',
      ).hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

int? _safeMediaSize(Object? value) {
  final size = (value as num?)?.toInt();
  return size != null && size >= 0 && size <= maxMediaArtifactMetadataBytes
      ? size
      : null;
}

String? _safeMediaChecksum(String? value) {
  final normalized = value?.trim();
  if (normalized == null ||
      normalized.isEmpty ||
      normalized != value ||
      normalized.length > 256 ||
      !RegExp(r'^[A-Za-z0-9:_-]+$').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

const maxMediaArtifactMetadataBytes = 512 * 1024 * 1024;

class MediaArtifactManifest {
  final List<MediaArtifact> items;

  const MediaArtifactManifest({this.items = const []});

  MediaArtifact? find(MediaArtifactKind kind) {
    for (final item in items) {
      if (item.kind == kind) return item;
    }
    return null;
  }

  bool contains(MediaArtifactKind kind) => find(kind) != null;

  MediaArtifactManifest upsert(MediaArtifact artifact) {
    final next = [
      for (final item in items)
        if (item.kind != artifact.kind) item,
      artifact,
    ];
    return MediaArtifactManifest(items: List.unmodifiable(next));
  }

  MediaArtifactManifest remove(MediaArtifactKind kind) => MediaArtifactManifest(
    items: List.unmodifiable(items.where((item) => item.kind != kind)),
  );

  factory MediaArtifactManifest.fromJson(Map<String, dynamic> json) =>
      MediaArtifactManifest(
        items: [
          for (final raw in (json['items'] as List<dynamic>? ?? const []))
            if (raw is Map)
              MediaArtifact.fromJson(Map<String, dynamic>.from(raw)),
        ],
      );

  Map<String, dynamic> toJson() => {
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };

  Map<String, dynamic> toPersistenceJson() => {
    'items': [for (final item in items) ?item.toPersistenceJson()],
  };
}

class MediaClip {
  final String id;
  final int startMs;
  final int endMs;
  final bool enabled;

  const MediaClip({
    required this.id,
    required this.startMs,
    required this.endMs,
    this.enabled = true,
  });

  int get durationMs => math.max(0, endMs - startMs);

  MediaClip normalized(int sourceDurationMs) {
    final maximum = math.max(0, sourceDurationMs);
    final start = startMs.clamp(0, maximum).toInt();
    final end = endMs.clamp(start, maximum).toInt();
    return MediaClip(id: id, startMs: start, endMs: end, enabled: enabled);
  }

  factory MediaClip.fromJson(Map<String, dynamic> json) => MediaClip(
    id: json['id'] as String? ?? 'clip',
    startMs: (json['startMs'] as num?)?.toInt() ?? 0,
    endMs: (json['endMs'] as num?)?.toInt() ?? 0,
    enabled: json['enabled'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startMs': startMs,
    'endMs': endMs,
    'enabled': enabled,
  };

  MediaClip copyWith({String? id, int? startMs, int? endMs, bool? enabled}) =>
      MediaClip(
        id: id ?? this.id,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        enabled: enabled ?? this.enabled,
      );
}

class MediaMarker {
  final String id;
  final int positionMs;
  final String label;
  final int? colorArgb;

  const MediaMarker({
    required this.id,
    required this.positionMs,
    this.label = '',
    this.colorArgb,
  });

  MediaMarker normalized(int sourceDurationMs) => MediaMarker(
    id: id,
    positionMs: positionMs.clamp(0, math.max(0, sourceDurationMs)).toInt(),
    label: label,
    colorArgb: colorArgb,
  );

  factory MediaMarker.fromJson(Map<String, dynamic> json) => MediaMarker(
    id: json['id'] as String? ?? 'marker',
    positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
    label: json['label'] as String? ?? '',
    colorArgb: (json['colorArgb'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'positionMs': positionMs,
    'label': label,
    'colorArgb': colorArgb,
  };

  MediaMarker copyWith({
    String? id,
    int? positionMs,
    String? label,
    int? colorArgb,
  }) => MediaMarker(
    id: id ?? this.id,
    positionMs: positionMs ?? this.positionMs,
    label: label ?? this.label,
    colorArgb: colorArgb ?? this.colorArgb,
  );
}

class MediaSubtitleCue {
  final String id;
  final int startMs;
  final int endMs;
  final String text;

  const MediaSubtitleCue({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  int get durationMs => math.max(0, endMs - startMs);

  MediaSubtitleCue normalized(int sourceDurationMs) {
    final maximum = math.max(0, sourceDurationMs);
    final start = startMs.clamp(0, maximum).toInt();
    final end = endMs.clamp(start, maximum).toInt();
    return MediaSubtitleCue(id: id, startMs: start, endMs: end, text: text);
  }

  factory MediaSubtitleCue.fromJson(Map<String, dynamic> json) =>
      MediaSubtitleCue(
        id: json['id'] as String? ?? 'cue',
        startMs: (json['startMs'] as num?)?.toInt() ?? 0,
        endMs: (json['endMs'] as num?)?.toInt() ?? 0,
        text: json['text'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startMs': startMs,
    'endMs': endMs,
    'text': text,
  };

  MediaSubtitleCue copyWith({
    String? id,
    int? startMs,
    int? endMs,
    String? text,
  }) => MediaSubtitleCue(
    id: id ?? this.id,
    startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs,
    text: text ?? this.text,
  );
}

class MediaSubtitleTrack {
  final String id;
  final String language;
  final String label;
  final bool enabled;
  final List<MediaSubtitleCue> cues;

  const MediaSubtitleTrack({
    required this.id,
    this.language = 'und',
    this.label = 'Subtitles',
    this.enabled = true,
    this.cues = const [],
  });

  MediaSubtitleTrack normalized(int sourceDurationMs) => MediaSubtitleTrack(
    id: id,
    language: language.trim().isEmpty ? 'und' : language.trim(),
    label: label.trim().isEmpty ? 'Subtitles' : label.trim(),
    enabled: enabled,
    cues: List.unmodifiable(
      cues
          .map((cue) => cue.normalized(sourceDurationMs))
          .where((cue) => cue.durationMs > 0 && cue.text.trim().isNotEmpty),
    ),
  );

  MediaSubtitleTrack upsertCue(MediaSubtitleCue cue) {
    final next = [
      for (final item in cues)
        if (item.id != cue.id) item,
      cue,
    ]..sort((left, right) => left.startMs.compareTo(right.startMs));
    return copyWith(cues: List.unmodifiable(next));
  }

  MediaSubtitleTrack removeCue(String cueId) =>
      copyWith(cues: List.unmodifiable(cues.where((cue) => cue.id != cueId)));

  factory MediaSubtitleTrack.fromJson(Map<String, dynamic> json) =>
      MediaSubtitleTrack(
        id: json['id'] as String? ?? 'subtitles',
        language: json['language'] as String? ?? 'und',
        label: json['label'] as String? ?? 'Subtitles',
        enabled: json['enabled'] as bool? ?? true,
        cues: [
          for (final raw in (json['cues'] as List<dynamic>? ?? const []))
            if (raw is Map)
              MediaSubtitleCue.fromJson(Map<String, dynamic>.from(raw)),
        ],
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'language': language,
    'label': label,
    'enabled': enabled,
    'cues': cues.map((cue) => cue.toJson()).toList(growable: false),
  };

  MediaSubtitleTrack copyWith({
    String? id,
    String? language,
    String? label,
    bool? enabled,
    List<MediaSubtitleCue>? cues,
  }) => MediaSubtitleTrack(
    id: id ?? this.id,
    language: language ?? this.language,
    label: label ?? this.label,
    enabled: enabled ?? this.enabled,
    cues: cues ?? this.cues,
  );
}

class MediaTimeline {
  static const Object _sentinel = Object();

  final int sourceDurationMs;
  final List<MediaClip> clips;
  final List<MediaMarker> markers;
  final List<MediaSubtitleTrack> subtitleTracks;
  final List<double> waveformSamples;
  final int? posterPositionMs;
  final double playbackSpeed;
  final double volume;
  final bool muted;
  final String? caption;
  final MediaArtifactManifest artifacts;

  const MediaTimeline({
    this.sourceDurationMs = 0,
    this.clips = const [],
    this.markers = const [],
    this.subtitleTracks = const [],
    this.waveformSamples = const [],
    this.posterPositionMs,
    this.playbackSpeed = 1.0,
    this.volume = 1.0,
    this.muted = false,
    this.caption,
    this.artifacts = const MediaArtifactManifest(),
  });

  List<MediaClip> get normalizedClips {
    if (clips.isEmpty && sourceDurationMs > 0) {
      return [MediaClip(id: 'clip-0', startMs: 0, endMs: sourceDurationMs)];
    }
    return List.unmodifiable(
      clips
          .map((clip) => clip.normalized(sourceDurationMs))
          .where((clip) => clip.enabled && clip.durationMs > 0),
    );
  }

  int get durationMs =>
      normalizedClips.fold(0, (total, clip) => total + clip.durationMs);

  int get effectiveDurationMs =>
      playbackSpeed <= 0 ? durationMs : (durationMs / playbackSpeed).round();

  int get trimStartMs => normalizedClips.isEmpty
      ? 0
      : normalizedClips.map((clip) => clip.startMs).reduce(math.min);

  int get trimEndMs => normalizedClips.isEmpty
      ? sourceDurationMs
      : normalizedClips.map((clip) => clip.endMs).reduce(math.max);

  bool get hasProxy => artifacts.contains(MediaArtifactKind.proxy);

  MediaTimeline normalized() {
    final sourceDuration = math.max(0, sourceDurationMs);
    final List<MediaClip> nextClips = clips.isEmpty
        ? clips
        : List.unmodifiable(
            clips.map((clip) => clip.normalized(sourceDuration)),
          );
    return copyWith(
      sourceDurationMs: sourceDuration,
      clips: nextClips,
      markers: List.unmodifiable(
        markers.map((marker) => marker.normalized(sourceDuration)),
      ),
      subtitleTracks: List.unmodifiable(
        subtitleTracks.map((track) => track.normalized(sourceDuration)),
      ),
      waveformSamples: List.unmodifiable(
        waveformSamples
            .where((sample) => sample.isFinite)
            .map((sample) => sample.clamp(0.0, 1.0).toDouble()),
      ),
      posterPositionMs: posterPositionMs?.clamp(0, sourceDuration).toInt(),
      playbackSpeed: playbackSpeed.clamp(0.25, 4.0).toDouble(),
      volume: volume.clamp(0.0, 1.0).toDouble(),
    );
  }

  MediaTimeline trim({required int startMs, required int endMs}) {
    final sourceDuration = math.max(0, sourceDurationMs);
    final start = startMs.clamp(0, sourceDuration).toInt();
    final end = endMs.clamp(start, sourceDuration).toInt();
    final id = clips.isEmpty ? 'clip-0' : clips.first.id;
    return copyWith(
      clips: [MediaClip(id: id, startMs: start, endMs: end)],
    ).normalized();
  }

  MediaTimeline splitAt(int timelinePositionMs) {
    final position = timelinePositionMs.clamp(0, durationMs).toInt();
    if (position <= 0 || position >= durationMs) return this;

    var remaining = position;
    final next = <MediaClip>[];
    for (final clip in normalizedClips) {
      if (remaining <= 0) {
        next.add(clip);
        continue;
      }
      if (remaining >= clip.durationMs) {
        next.add(clip);
        remaining -= clip.durationMs;
        continue;
      }
      final cut = clip.startMs + remaining;
      next.add(clip.copyWith(id: '${clip.id}-a', endMs: cut));
      next.add(clip.copyWith(id: '${clip.id}-b', startMs: cut));
      remaining = 0;
    }
    return copyWith(clips: next).normalized();
  }

  MediaTimeline removeClip(String clipId) {
    final remaining = clips.where((clip) => clip.id != clipId).toList();
    if (remaining.isEmpty) {
      remaining.add(
        const MediaClip(id: 'empty', startMs: 0, endMs: 0, enabled: false),
      );
    }
    return copyWith(clips: List.unmodifiable(remaining)).normalized();
  }

  MediaTimeline upsertMarker(MediaMarker marker) {
    final next = [
      for (final item in markers)
        if (item.id != marker.id) item,
      marker,
    ]..sort((left, right) => left.positionMs.compareTo(right.positionMs));
    return copyWith(markers: List.unmodifiable(next)).normalized();
  }

  MediaTimeline removeMarker(String markerId) => copyWith(
    markers: List.unmodifiable(
      markers.where((marker) => marker.id != markerId),
    ),
  );

  MediaTimeline upsertSubtitleTrack(MediaSubtitleTrack track) {
    final next = [
      for (final item in subtitleTracks)
        if (item.id != track.id) item,
      track,
    ];
    return copyWith(subtitleTracks: List.unmodifiable(next)).normalized();
  }

  MediaTimeline removeSubtitleTrack(String trackId) => copyWith(
    subtitleTracks: List.unmodifiable(
      subtitleTracks.where((track) => track.id != trackId),
    ),
  );

  MediaTimeline copyWith({
    int? sourceDurationMs,
    List<MediaClip>? clips,
    List<MediaMarker>? markers,
    List<MediaSubtitleTrack>? subtitleTracks,
    List<double>? waveformSamples,
    Object? posterPositionMs = _sentinel,
    double? playbackSpeed,
    double? volume,
    bool? muted,
    Object? caption = _sentinel,
    MediaArtifactManifest? artifacts,
  }) => MediaTimeline(
    sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs,
    clips: clips ?? this.clips,
    markers: markers ?? this.markers,
    subtitleTracks: subtitleTracks ?? this.subtitleTracks,
    waveformSamples: waveformSamples ?? this.waveformSamples,
    posterPositionMs: posterPositionMs == _sentinel
        ? this.posterPositionMs
        : posterPositionMs as int?,
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    volume: volume ?? this.volume,
    muted: muted ?? this.muted,
    caption: caption == _sentinel ? this.caption : caption as String?,
    artifacts: artifacts ?? this.artifacts,
  );

  factory MediaTimeline.fromJson(Map<String, dynamic> json) => MediaTimeline(
    sourceDurationMs: (json['sourceDurationMs'] as num?)?.toInt() ?? 0,
    clips: [
      for (final raw in (json['clips'] as List<dynamic>? ?? const []))
        if (raw is Map) MediaClip.fromJson(Map<String, dynamic>.from(raw)),
    ],
    markers: [
      for (final raw in (json['markers'] as List<dynamic>? ?? const []))
        if (raw is Map) MediaMarker.fromJson(Map<String, dynamic>.from(raw)),
    ],
    subtitleTracks: [
      for (final raw in (json['subtitleTracks'] as List<dynamic>? ?? const []))
        if (raw is Map)
          MediaSubtitleTrack.fromJson(Map<String, dynamic>.from(raw)),
    ],
    waveformSamples: [
      for (final raw in (json['waveformSamples'] as List<dynamic>? ?? const []))
        if (raw is num) raw.toDouble(),
    ],
    posterPositionMs: (json['posterPositionMs'] as num?)?.toInt(),
    playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    muted: json['muted'] as bool? ?? false,
    caption: json['caption'] as String?,
    artifacts: json['artifacts'] is Map
        ? MediaArtifactManifest.fromJson(
            Map<String, dynamic>.from(json['artifacts'] as Map),
          )
        : const MediaArtifactManifest(),
  ).normalized();

  Map<String, dynamic> toJson() => {
    'sourceDurationMs': sourceDurationMs,
    'clips': clips.map((clip) => clip.toJson()).toList(growable: false),
    'markers': markers.map((marker) => marker.toJson()).toList(growable: false),
    'subtitleTracks': subtitleTracks
        .map((track) => track.toJson())
        .toList(growable: false),
    'waveformSamples': waveformSamples,
    'posterPositionMs': posterPositionMs,
    'playbackSpeed': playbackSpeed,
    'volume': volume,
    'muted': muted,
    'caption': caption,
    'artifacts': artifacts.toJson(),
  };

  Map<String, dynamic> toPersistenceJson() => {
    'sourceDurationMs': sourceDurationMs,
    'clips': clips.map((clip) => clip.toJson()).toList(growable: false),
    'markers': markers.map((marker) => marker.toJson()).toList(growable: false),
    'subtitleTracks': subtitleTracks
        .map((track) => track.toJson())
        .toList(growable: false),
    'waveformSamples': waveformSamples,
    'posterPositionMs': posterPositionMs,
    'playbackSpeed': playbackSpeed,
    'volume': volume,
    'muted': muted,
    'caption': caption,
    'artifacts': artifacts.toPersistenceJson(),
  };
}
