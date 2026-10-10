enum StoryboardShotStatus { draft, ready, approved }

class StoryboardShot {
  final String id;
  final String title;
  final String frameId;
  final Duration duration;
  final String description;
  final String speakerNotes;
  final StoryboardShotStatus status;
  final List<String> tags;

  const StoryboardShot({
    required this.id,
    required this.title,
    required this.frameId,
    this.duration = const Duration(seconds: 8),
    this.description = '',
    this.speakerNotes = '',
    this.status = StoryboardShotStatus.draft,
    this.tags = const [],
  });

  StoryboardShot copyWith({
    String? title,
    String? frameId,
    Duration? duration,
    String? description,
    String? speakerNotes,
    StoryboardShotStatus? status,
    List<String>? tags,
  }) => StoryboardShot(
    id: id,
    title: title ?? this.title,
    frameId: frameId ?? this.frameId,
    duration: duration ?? this.duration,
    description: description ?? this.description,
    speakerNotes: speakerNotes ?? this.speakerNotes,
    status: status ?? this.status,
    tags: tags ?? this.tags,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'frameId': frameId,
    'durationMs': duration.inMilliseconds,
    'description': description,
    'speakerNotes': speakerNotes,
    'status': status.name,
    'tags': tags,
  };

  factory StoryboardShot.fromJson(Map<String, dynamic> json) => StoryboardShot(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? 'Untitled shot',
    frameId: json['frameId'] as String? ?? '',
    duration: Duration(
      milliseconds: (json['durationMs'] as num?)?.toInt() ?? 8000,
    ),
    description: json['description'] as String? ?? '',
    speakerNotes: json['speakerNotes'] as String? ?? '',
    status: StoryboardShotStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => StoryboardShotStatus.draft,
    ),
    tags:
        (json['tags'] as List<dynamic>?)?.whereType<String>().toList() ??
        const [],
  );
}

class TimelineKeyframe<T> {
  final Duration offset;
  final T value;

  const TimelineKeyframe({required this.offset, required this.value});
}

class TimelineTrack {
  final String id;
  final String targetNodeId;
  final String property;
  final List<TimelineKeyframe<double>> keyframes;

  const TimelineTrack({
    required this.id,
    required this.targetNodeId,
    required this.property,
    this.keyframes = const [],
  });

  double? valueAt(Duration position) {
    if (keyframes.isEmpty) return null;
    final ordered = [...keyframes]
      ..sort((left, right) => left.offset.compareTo(right.offset));
    if (position <= ordered.first.offset) return ordered.first.value;
    if (position >= ordered.last.offset) return ordered.last.value;
    for (var index = 1; index < ordered.length; index++) {
      final previous = ordered[index - 1];
      final next = ordered[index];
      if (position <= next.offset) {
        final span = next.offset - previous.offset;
        final progress = span.inMicroseconds == 0
            ? 1.0
            : (position - previous.offset).inMicroseconds / span.inMicroseconds;
        return previous.value + (next.value - previous.value) * progress;
      }
    }
    return ordered.last.value;
  }
}

class PresentationTimeline {
  final List<StoryboardShot> shots;
  final List<TimelineTrack> tracks;

  const PresentationTimeline({this.shots = const [], this.tracks = const []});

  Duration get totalDuration =>
      shots.fold(Duration.zero, (total, shot) => total + shot.duration);

  PresentationTimeline reorderShots(List<String> orderedIds) {
    final byId = {for (final shot in shots) shot.id: shot};
    final ordered = <StoryboardShot>[
      for (final id in orderedIds)
        if (byId[id] != null) byId[id]!,
      for (final shot in shots)
        if (!orderedIds.contains(shot.id)) shot,
    ];
    return PresentationTimeline(shots: ordered, tracks: tracks);
  }

  Map<String, dynamic> toJson() => {
    'shots': shots.map((shot) => shot.toJson()).toList(growable: false),
    'trackIds': tracks.map((track) => track.id).toList(growable: false),
  };

  factory PresentationTimeline.fromJson(Map<String, dynamic> json) =>
      PresentationTimeline(
        shots: [
          for (final rawShot in (json['shots'] as List<dynamic>? ?? const []))
            if (rawShot is Map)
              StoryboardShot.fromJson(Map<String, dynamic>.from(rawShot)),
        ],
      );
}
