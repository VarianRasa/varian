import 'dart:math' as math;

import '../../../domain/models/document.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import 'storyboard_timeline.dart';

enum PresentationTransition { cut, fade, slide, zoom }

class PresentationFrameConfig {
  final String frameId;
  final int order;
  final Duration duration;
  final PresentationTransition transition;
  final String speakerNotes;

  const PresentationFrameConfig({
    required this.frameId,
    required this.order,
    this.duration = const Duration(seconds: 8),
    this.transition = PresentationTransition.cut,
    this.speakerNotes = '',
  });

  PresentationFrameConfig copyWith({
    String? frameId,
    int? order,
    Duration? duration,
    PresentationTransition? transition,
    String? speakerNotes,
  }) => PresentationFrameConfig(
    frameId: frameId ?? this.frameId,
    order: order ?? this.order,
    duration: duration ?? this.duration,
    transition: transition ?? this.transition,
    speakerNotes: speakerNotes ?? this.speakerNotes,
  );

  Map<String, dynamic> toJson() => {
    'frameId': frameId,
    'order': order,
    'durationMs': duration.inMilliseconds,
    'transition': transition.name,
    'speakerNotes': speakerNotes,
  };

  factory PresentationFrameConfig.fromJson(Map<String, dynamic> json) =>
      PresentationFrameConfig(
        frameId: json['frameId'] as String,
        order: (json['order'] as num?)?.toInt() ?? 0,
        duration: Duration(
          milliseconds: math.max(
            0,
            (json['durationMs'] as num?)?.toInt() ?? 8000,
          ),
        ),
        transition: PresentationTransition.values.firstWhere(
          (value) => value.name == json['transition'],
          orElse: () => PresentationTransition.cut,
        ),
        speakerNotes: json['speakerNotes'] as String? ?? '',
      );
}

class PresentationHotspotIssue {
  final String nodeId;
  final String targetFrameId;
  final String message;

  const PresentationHotspotIssue({
    required this.nodeId,
    required this.targetFrameId,
    required this.message,
  });
}

class PresentationPlan {
  final List<PresentationFrameConfig> frames;
  final PresentationTimeline? timeline;

  const PresentationPlan({this.frames = const [], this.timeline});

  List<PresentationFrameConfig> get orderedFrames {
    final result = [...frames]
      ..sort((left, right) {
        final order = left.order.compareTo(right.order);
        return order != 0 ? order : left.frameId.compareTo(right.frameId);
      });
    return result;
  }

  PresentationFrameConfig? configFor(String frameId) =>
      frames.where((frame) => frame.frameId == frameId).firstOrNull;

  List<CanvasNode> resolveFrames(Iterable<CanvasNode> nodes) {
    final visibleFrames = nodes
        .where((node) => node.type == NodeType.frame && node.visible)
        .toList();
    final byId = {for (final frame in visibleFrames) frame.id: frame};
    final timelineOrdered = timeline?.shots
        .map((shot) => byId[shot.frameId])
        .whereType<CanvasNode>()
        .toList(growable: false);
    if (timelineOrdered != null && timelineOrdered.isNotEmpty) {
      final used = timelineOrdered.map((frame) => frame.id).toSet();
      final remaining =
          visibleFrames.where((frame) => !used.contains(frame.id)).toList()
            ..sort((left, right) {
              final x = left.x.compareTo(right.x);
              return x != 0 ? x : left.y.compareTo(right.y);
            });
      return [...timelineOrdered, ...remaining];
    }
    final explicit = orderedFrames
        .map((config) => byId[config.frameId])
        .whereType<CanvasNode>();
    final used = explicit.map((frame) => frame.id).toSet();
    final remaining =
        visibleFrames.where((frame) => !used.contains(frame.id)).toList()
          ..sort((left, right) {
            final x = left.x.compareTo(right.x);
            return x != 0 ? x : left.y.compareTo(right.y);
          });
    return [...explicit, ...remaining];
  }

  List<PresentationHotspotIssue> validateHotspots(Iterable<CanvasNode> nodes) {
    final frameIds = nodes
        .where((node) => node.type == NodeType.frame)
        .map((node) => node.id)
        .toSet();
    return [
      for (final node in nodes)
        if (node.payload.hotspotTargetFrameId != null &&
            !frameIds.contains(node.payload.hotspotTargetFrameId))
          PresentationHotspotIssue(
            nodeId: node.id,
            targetFrameId: node.payload.hotspotTargetFrameId!,
            message: 'Hotspot target frame does not exist.',
          ),
    ];
  }

  Map<String, dynamic> toJson() => {
    'frames': orderedFrames.map((frame) => frame.toJson()).toList(),
    if (timeline != null) 'timeline': timeline!.toJson(),
  };

  factory PresentationPlan.fromJson(Object? raw) {
    if (raw is! Map || raw['frames'] is! List) {
      return const PresentationPlan();
    }
    return PresentationPlan(
      frames: [
        for (final item in raw['frames'] as List)
          if (item is Map)
            PresentationFrameConfig.fromJson(Map<String, dynamic>.from(item)),
      ],
      timeline: raw['timeline'] is Map
          ? PresentationTimeline.fromJson(
              Map<String, dynamic>.from(raw['timeline'] as Map),
            )
          : null,
    );
  }

  factory PresentationPlan.fromDocument(CanvasDocument document) {
    final raw = document.metadata['presentation'];
    final parsed = PresentationPlan.fromJson(raw);
    if (parsed.frames.isNotEmpty || parsed.timeline != null) return parsed;
    final frames =
        document.nodes
            .where((node) => node.type == NodeType.frame && node.visible)
            .toList()
          ..sort((left, right) {
            final x = left.x.compareTo(right.x);
            return x != 0 ? x : left.y.compareTo(right.y);
          });
    return PresentationPlan(
      frames: [
        for (var index = 0; index < frames.length; index++)
          PresentationFrameConfig(frameId: frames[index].id, order: index),
      ],
      timeline: PresentationTimeline(
        shots: [
          for (var index = 0; index < frames.length; index++)
            StoryboardShot(
              id: 'shot-${frames[index].id}',
              title: 'Shot ${index + 1}',
              frameId: frames[index].id,
              duration: PresentationFrameConfig(
                frameId: frames[index].id,
                order: index,
              ).duration,
              speakerNotes: '',
            ),
        ],
      ),
    );
  }
}

class PresentationPlaybackClock {
  final PresentationPlan plan;
  Duration position;

  PresentationPlaybackClock(this.plan, {this.position = Duration.zero});

  Duration get totalDuration => plan.orderedFrames.fold(
    Duration.zero,
    (total, frame) => total + frame.duration,
  );

  Duration seek(Duration next) {
    final maxPosition = totalDuration;
    position = next < Duration.zero
        ? Duration.zero
        : next > maxPosition
        ? maxPosition
        : next;
    return position;
  }

  int get frameIndexAtPosition {
    var remaining = position;
    final frames = plan.orderedFrames;
    for (var index = 0; index < frames.length; index++) {
      if (remaining < frames[index].duration || index == frames.length - 1) {
        return index;
      }
      remaining -= frames[index].duration;
    }
    return 0;
  }
}
