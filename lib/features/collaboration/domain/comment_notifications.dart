import '../../../domain/models/collaboration.dart';

enum CommentNotificationType {
  mention,
  reply,
  assignment,
  dueDate,
  resolved;

  String get wireName => name;

  static CommentNotificationType fromWire(Object? value) => values.firstWhere(
    (type) => type.wireName == value?.toString(),
    orElse: () => CommentNotificationType.reply,
  );
}

class CommentNotificationPreferences {
  final bool mentions;
  final bool replies;
  final bool assignments;
  final bool dueDates;
  final bool resolvedThreads;
  final bool unresolvedOnly;

  const CommentNotificationPreferences({
    this.mentions = true,
    this.replies = true,
    this.assignments = true,
    this.dueDates = true,
    this.resolvedThreads = false,
    this.unresolvedOnly = false,
  });

  bool allows(CommentNotificationType type) => switch (type) {
    CommentNotificationType.mention => mentions,
    CommentNotificationType.reply => replies,
    CommentNotificationType.assignment => assignments,
    CommentNotificationType.dueDate => dueDates,
    CommentNotificationType.resolved => resolvedThreads,
  };

  CommentNotificationPreferences copyWith({
    bool? mentions,
    bool? replies,
    bool? assignments,
    bool? dueDates,
    bool? resolvedThreads,
    bool? unresolvedOnly,
  }) => CommentNotificationPreferences(
    mentions: mentions ?? this.mentions,
    replies: replies ?? this.replies,
    assignments: assignments ?? this.assignments,
    dueDates: dueDates ?? this.dueDates,
    resolvedThreads: resolvedThreads ?? this.resolvedThreads,
    unresolvedOnly: unresolvedOnly ?? this.unresolvedOnly,
  );

  Map<String, dynamic> toJson() => {
    'mentions': mentions,
    'replies': replies,
    'assignments': assignments,
    'dueDates': dueDates,
    'resolvedThreads': resolvedThreads,
    'unresolvedOnly': unresolvedOnly,
  };

  factory CommentNotificationPreferences.fromJson(Object? raw) {
    if (raw is! Map) return const CommentNotificationPreferences();
    return CommentNotificationPreferences(
      mentions: raw['mentions'] as bool? ?? true,
      replies: raw['replies'] as bool? ?? true,
      assignments: raw['assignments'] as bool? ?? true,
      dueDates: raw['dueDates'] as bool? ?? true,
      resolvedThreads: raw['resolvedThreads'] as bool? ?? false,
      unresolvedOnly: raw['unresolvedOnly'] as bool? ?? false,
    );
  }
}

class CommentNotification {
  final String id;
  final String projectId;
  final String commentId;
  final CommentNotificationType type;
  final String actorId;
  final String actorName;
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> payload;

  const CommentNotification({
    required this.id,
    required this.projectId,
    required this.commentId,
    required this.type,
    required this.actorId,
    required this.actorName,
    required this.message,
    required this.createdAt,
    this.readAt,
    this.payload = const {},
  });

  bool get isRead => readAt != null;

  CommentNotification copyWith({
    String? id,
    String? projectId,
    String? commentId,
    CommentNotificationType? type,
    String? actorId,
    String? actorName,
    String? message,
    DateTime? createdAt,
    Object? readAt = _unset,
    Map<String, dynamic>? payload,
  }) => CommentNotification(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    commentId: commentId ?? this.commentId,
    type: type ?? this.type,
    actorId: actorId ?? this.actorId,
    actorName: actorName ?? this.actorName,
    message: message ?? this.message,
    createdAt: createdAt ?? this.createdAt,
    readAt: readAt == _unset ? this.readAt : readAt as DateTime?,
    payload: payload ?? this.payload,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'commentId': commentId,
    'type': type.wireName,
    'actorId': actorId,
    'actorName': actorName,
    'message': message,
    'createdAt': createdAt.toIso8601String(),
    'readAt': readAt?.toIso8601String(),
    'payload': payload,
  };

  factory CommentNotification.fromJson(Map<String, dynamic> json) =>
      CommentNotification(
        id: json['id']?.toString() ?? '',
        projectId: json['projectId']?.toString() ?? '',
        commentId: json['commentId']?.toString() ?? '',
        type: CommentNotificationType.fromWire(json['type']),
        actorId: json['actorId']?.toString() ?? '',
        actorName: json['actorName']?.toString() ?? 'Collaborator',
        message: json['message']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        readAt: DateTime.tryParse(json['readAt']?.toString() ?? ''),
        payload: json['payload'] is Map
            ? Map<String, dynamic>.from(json['payload'] as Map)
            : const {},
      );

  static const Object _unset = Object();
}

class CommentNotificationFactory {
  static List<String> extractMentions(String text) {
    final mentions = <String>{};
    for (final match in RegExp(
      r'@([a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*)',
    ).allMatches(text)) {
      final mention = match.group(1)?.trim();
      if (mention != null && mention.isNotEmpty) mentions.add(mention);
    }
    return mentions.toList(growable: false);
  }

  static List<CommentNotification> fromCommentChange({
    required String projectId,
    required String localUserId,
    required String localUserName,
    required CanvasComment current,
    required String actorId,
    required String actorName,
    Iterable<String> localIdentityAliases = const [],
    CanvasComment? previous,
    DateTime? now,
  }) {
    final aliases =
        <String>{localUserId, localUserName, ...localIdentityAliases}
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toSet();
    bool matchesLocal(Object? value) =>
        value != null &&
        aliases.contains(value.toString().trim().toLowerCase());

    if (matchesLocal(actorId) || matchesLocal(actorName)) return const [];

    final createdAt = now ?? DateTime.now();
    final currentMentions = <String>{
      ...current.mentions,
      ...extractMentions(current.text),
    };
    final previousMentions = <String>{
      ...?previous?.mentions,
      ...extractMentions(previous?.text ?? ''),
    };
    final targetsLocal =
        matchesLocal(current.authorId) ||
        matchesLocal(current.authorName) ||
        matchesLocal(current.assigneeId) ||
        matchesLocal(current.assigneeName) ||
        current.watchers.any(matchesLocal) ||
        currentMentions.any(matchesLocal);
    final result = <CommentNotification>[];

    void add(
      CommentNotificationType type,
      String eventKey,
      String message, {
      Map<String, dynamic> payload = const {},
      String? eventActorId,
      String? eventActorName,
    }) {
      result.add(
        CommentNotification(
          id: '$projectId:${current.id}:$eventKey',
          projectId: projectId,
          commentId: current.id,
          type: type,
          actorId: eventActorId ?? actorId,
          actorName: (eventActorName ?? actorName).trim().isEmpty
              ? 'Collaborator'
              : (eventActorName ?? actorName).trim(),
          message: message,
          createdAt: createdAt,
          payload: {
            'nodeId': current.nodeId,
            'threadId': current.feedbackThreadKey,
            ...payload,
          },
        ),
      );
    }

    final addedMentions = currentMentions.difference(previousMentions);
    if (addedMentions.any(matchesLocal)) {
      add(
        CommentNotificationType.mention,
        'mention:${addedMentions.where(matchesLocal).join(',')}',
        '${actorName.trim().isEmpty ? 'Collaborator' : actorName.trim()} menyebut Anda di komentar.',
        payload: {'mentions': addedMentions.toList(growable: false)},
      );
    }

    final previousReplyIds = {...?previous?.replies.map((reply) => reply.id)};
    for (final reply in current.replies) {
      if (previousReplyIds.contains(reply.id) ||
          matchesLocal(reply.authorId) ||
          !targetsLocal) {
        continue;
      }
      add(
        CommentNotificationType.reply,
        'reply:${reply.id}',
        '${reply.authorName} membalas komentar.',
        eventActorId: reply.authorId,
        eventActorName: reply.authorName,
      );
    }

    final assignmentChanged =
        previous?.assigneeId != current.assigneeId ||
        previous?.assigneeName != current.assigneeName;
    if (assignmentChanged &&
        (matchesLocal(current.assigneeId) ||
            matchesLocal(current.assigneeName))) {
      add(
        CommentNotificationType.assignment,
        'assignment',
        '${actorName.trim().isEmpty ? 'Collaborator' : actorName.trim()} menugaskan komentar kepada Anda.',
        payload: {
          'assigneeId': current.assigneeId,
          'assigneeName': current.assigneeName,
        },
      );
    }

    if (previous?.dueDate != current.dueDate && targetsLocal) {
      add(
        CommentNotificationType.dueDate,
        'due-date:${current.dueDate?.toIso8601String() ?? 'cleared'}',
        current.dueDate == null
            ? '${actorName.trim().isEmpty ? 'Collaborator' : actorName.trim()} menghapus due date komentar.'
            : '${actorName.trim().isEmpty ? 'Collaborator' : actorName.trim()} memperbarui due date komentar.',
        payload: {'dueDate': current.dueDate?.toIso8601String()},
      );
    }

    if (previous?.resolved != current.resolved && targetsLocal) {
      add(
        CommentNotificationType.resolved,
        'resolved:${current.resolved}',
        current.resolved
            ? '${actorName.trim().isEmpty ? 'Collaborator' : actorName.trim()} menyelesaikan komentar.'
            : '${actorName.trim().isEmpty ? 'Collaborator' : actorName.trim()} membuka kembali komentar.',
        payload: {'resolved': current.resolved},
      );
    }

    return result;
  }
}

class CommentNotificationCenter {
  final List<CommentNotification> notifications;

  CommentNotificationCenter(Iterable<CommentNotification> notifications)
    : notifications = List<CommentNotification>.unmodifiable(notifications);

  List<CommentNotification> get unread => notifications
      .where((notification) => !notification.isRead)
      .toList(growable: false);

  List<CommentNotification> forComments(Iterable<String> commentIds) {
    final ids = commentIds.toSet();
    return notifications
        .where((notification) => ids.contains(notification.commentId))
        .toList(growable: false);
  }

  List<CommentNotification> filtered({
    CommentNotificationType? type,
    bool unreadOnly = false,
    Iterable<String>? commentIds,
  }) {
    final ids = commentIds?.toSet();
    return notifications
        .where(
          (notification) =>
              (type == null || notification.type == type) &&
              (!unreadOnly || !notification.isRead) &&
              (ids == null || ids.contains(notification.commentId)),
        )
        .toList(growable: false);
  }

  List<Map<String, dynamic>> toJson() =>
      notifications.map((notification) => notification.toJson()).toList();

  static CommentNotificationCenter fromJson(Object? raw) {
    if (raw is! List) return CommentNotificationCenter(const []);
    return CommentNotificationCenter(
      raw.whereType<Map>().map(
        (item) => CommentNotification.fromJson(Map<String, dynamic>.from(item)),
      ),
    );
  }
}
