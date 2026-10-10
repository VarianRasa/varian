import 'package:flutter/material.dart';

class CollaborationDisplayNameGenerator {
  static const _adjectives = [
    'Amber',
    'Brave',
    'Bright',
    'Calm',
    'Clever',
    'Copper',
    'Cosmic',
    'Curious',
    'Daring',
    'Emerald',
    'Gentle',
    'Golden',
    'Kind',
    'Lucky',
    'Misty',
    'Nimble',
    'Orange',
    'Quiet',
    'Rapid',
    'Silver',
    'Sonic',
    'Sunny',
    'Swift',
    'Violet',
  ];

  static const _animals = [
    'Badger',
    'Bear',
    'Beaver',
    'Bison',
    'Butterfly',
    'Capybara',
    'Cat',
    'Deer',
    'Dolphin',
    'Eagle',
    'Fox',
    'Hedgehog',
    'Koala',
    'Lemur',
    'Otter',
    'Owl',
    'Panda',
    'Penguin',
    'Rabbit',
    'Raccoon',
    'Seal',
    'Tiger',
    'Turtle',
    'Wolf',
  ];

  static const _placeholders = {
    '',
    'architect',
    'collaborator',
    'guest',
    'host',
    'user',
  };

  static String generate(String stableId) {
    var hash = 2166136261;
    for (final codeUnit in stableId.trim().codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    final adjective = _adjectives[hash % _adjectives.length];
    final animal = _animals[(hash ~/ _adjectives.length) % _animals.length];
    final suffix = (hash % 100).toString().padLeft(2, '0');
    return '$adjective $animal $suffix';
  }

  static bool isPlaceholder(Object? value) =>
      _placeholders.contains(value?.toString().trim().toLowerCase());

  static String resolve({required String stableId, String? preferredName}) {
    final normalized = preferredName?.trim() ?? '';
    return isPlaceholder(normalized) ? generate(stableId) : normalized;
  }

  static String validate(String value) {
    final raw = value.trim();
    if (raw.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
      throw const FormatException('Display name contains invalid characters.');
    }
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length < 2 || normalized.length > 32) {
      throw const FormatException(
        'Display name must contain 2 to 32 characters.',
      );
    }
    return normalized;
  }
}

enum CollaborationRole {
  owner,
  editor,
  commenter,
  viewer;

  static CollaborationRole fromWire(Object? value) =>
      switch (value?.toString().trim().toLowerCase()) {
        'owner' => CollaborationRole.owner,
        'editor' => CollaborationRole.editor,
        'commenter' => CollaborationRole.commenter,
        'viewer' => CollaborationRole.viewer,
        _ => CollaborationRole.viewer,
      };

  String get wireName => name;
}

extension CollaborationRoleLabels on CollaborationRole {
  String get label => switch (this) {
    CollaborationRole.owner => 'Host',
    CollaborationRole.editor => 'Editor',
    CollaborationRole.commenter => 'Commenter',
    CollaborationRole.viewer => 'Viewer',
  };
}

class CollaborationPermissions {
  final CollaborationRole role;

  const CollaborationPermissions(this.role);

  bool get isHost => role == CollaborationRole.owner;
  bool get canEditCanvas =>
      role == CollaborationRole.owner || role == CollaborationRole.editor;
  bool get canComment => canEditCanvas || role == CollaborationRole.commenter;
  bool get canManageMembers => isHost;
  bool get canManageRoom => isHost;
  bool get canRequestFollow => true;
  bool get canApproveFollow => true;
  bool get canRequestScreenShare => true;
  bool get canApproveScreenShare => isHost;
}

enum CollaborationControlEventType {
  memberRoleChanged,
  memberRemoved,
  memberProfileUpdated,
  followRequest,
  followResponse,
  followState,
  screenShareRequest,
  screenShareResponse,
  screenShareSignal,
  screenShareState;

  String get wireName => switch (this) {
    CollaborationControlEventType.memberRoleChanged => 'member_role_changed',
    CollaborationControlEventType.memberRemoved => 'member_removed',
    CollaborationControlEventType.memberProfileUpdated =>
      'member_profile_updated',
    CollaborationControlEventType.followRequest => 'follow_request',
    CollaborationControlEventType.followResponse => 'follow_response',
    CollaborationControlEventType.followState => 'follow_state',
    CollaborationControlEventType.screenShareRequest => 'screen_share_request',
    CollaborationControlEventType.screenShareResponse =>
      'screen_share_response',
    CollaborationControlEventType.screenShareSignal => 'screen_share_signal',
    CollaborationControlEventType.screenShareState => 'screen_share_state',
  };

  static CollaborationControlEventType? fromWire(Object? value) {
    final wireName = value?.toString();
    for (final type in values) {
      if (type.wireName == wireName) return type;
    }
    return null;
  }
}

enum ScreenTrackingStatus {
  idle,
  requesting,
  awaitingConsent,
  connecting,
  sharing,
  viewing,
  stopped,
  error,
}

enum CollaborationNoticeKind {
  joined,
  left,
  removed,
  roleChanged,
  profileUpdated,
}

class CollaborationNotice {
  final String id;
  final String userId;
  final String displayName;
  final CollaborationNoticeKind kind;
  final CollaborationRole? role;
  final DateTime createdAt;

  const CollaborationNotice({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.kind,
    required this.createdAt,
    this.role,
  });

  String get message => switch (kind) {
    CollaborationNoticeKind.joined => '$displayName joined the room.',
    CollaborationNoticeKind.left => '$displayName left the room.',
    CollaborationNoticeKind.removed =>
      '$displayName was removed from the room.',
    CollaborationNoticeKind.roleChanged =>
      '$displayName is now ${role?.label ?? 'a member'}.',
    CollaborationNoticeKind.profileUpdated =>
      '$displayName updated their display name.',
  };
}

class CollaborationControlEvent {
  final String eventId;
  final String projectId;
  final String actorId;
  final String? targetUserId;
  final CollaborationControlEventType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const CollaborationControlEvent({
    required this.eventId,
    required this.projectId,
    required this.actorId,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.targetUserId,
  });

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'projectId': projectId,
    'actorId': actorId,
    'targetUserId': targetUserId,
    'controlType': type.wireName,
    'payload': payload,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static CollaborationControlEvent? tryParse(Map<String, dynamic> json) {
    final type = CollaborationControlEventType.fromWire(
      json['controlType'] ?? json['type'],
    );
    final eventId = json['eventId']?.toString();
    final projectId = json['projectId']?.toString();
    final actorId = json['actorId']?.toString();
    final rawPayload = json['payload'];
    if (type == null ||
        eventId == null ||
        eventId.isEmpty ||
        projectId == null ||
        projectId.isEmpty ||
        actorId == null ||
        actorId.isEmpty ||
        rawPayload is! Map) {
      return null;
    }
    return CollaborationControlEvent(
      eventId: eventId,
      projectId: projectId,
      actorId: actorId,
      targetUserId: json['targetUserId']?.toString(),
      type: type,
      payload: Map<String, dynamic>.from(rawPayload),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

class CommentReply {
  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime createdAt;
  final DateTime? editedAt;

  const CommentReply({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.editedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'authorId': authorId,
    'authorName': authorName,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'editedAt': editedAt?.toIso8601String(),
  };

  CommentReply copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? text,
    DateTime? createdAt,
    DateTime? editedAt,
  }) => CommentReply(
    id: id ?? this.id,
    authorId: authorId ?? this.authorId,
    authorName: authorName ?? this.authorName,
    text: text ?? this.text,
    createdAt: createdAt ?? this.createdAt,
    editedAt: editedAt ?? this.editedAt,
  );

  factory CommentReply.fromJson(Map<String, dynamic> json) => CommentReply(
    id: json['id'] as String,
    authorId: json['authorId'] as String,
    authorName: json['authorName'] as String,
    text: json['text'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    editedAt: DateTime.tryParse(json['editedAt']?.toString() ?? ''),
  );
}

class CommentAttachment {
  final String id;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String? assetId;
  final String? uri;
  final String? checksum;
  final DateTime createdAt;

  const CommentAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    this.sizeBytes = 0,
    this.assetId,
    this.uri,
    this.checksum,
    required this.createdAt,
  });

  bool get hasDurableReference =>
      (assetId?.trim().isNotEmpty ?? false) ||
      (uri?.trim().isNotEmpty ?? false);

  CommentAttachment copyWith({
    String? id,
    String? name,
    String? mimeType,
    int? sizeBytes,
    Object? assetId = _unset,
    Object? uri = _unset,
    Object? checksum = _unset,
    DateTime? createdAt,
  }) => CommentAttachment(
    id: id ?? this.id,
    name: name ?? this.name,
    mimeType: mimeType ?? this.mimeType,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    assetId: assetId == _unset ? this.assetId : assetId as String?,
    uri: uri == _unset ? this.uri : uri as String?,
    checksum: checksum == _unset ? this.checksum : checksum as String?,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'assetId': assetId,
    'uri': uri,
    'checksum': checksum,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CommentAttachment.fromJson(Map<String, dynamic> json) =>
      CommentAttachment(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Attachment',
        mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        assetId: json['assetId']?.toString(),
        uri: json['uri']?.toString(),
        checksum: json['checksum']?.toString(),
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  static const Object _unset = Object();
}

class CanvasComment {
  final String id;
  final String? feedbackThreadId;
  final String? nodeId;
  final String authorId;
  final String authorName;
  final String text;
  final double x;
  final double y;
  final bool resolved;
  final DateTime createdAt;
  final DateTime? editedAt;
  final List<CommentReply> replies;
  final List<String> mentions;
  final Map<String, int> reactions; // e.g. {'👍': 3, '❤️': 2, '🚀': 1}
  final List<CommentAttachment> attachments;
  final List<String> labels;
  final String? assigneeId;
  final String? assigneeName;
  final DateTime? dueDate;
  final List<String> watchers;

  const CanvasComment({
    required this.id,
    this.feedbackThreadId,
    this.nodeId,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.x,
    required this.y,
    this.resolved = false,
    required this.createdAt,
    this.editedAt,
    this.replies = const [],
    this.mentions = const [],
    this.reactions = const {},
    this.attachments = const [],
    this.labels = const [],
    this.assigneeId,
    this.assigneeName,
    this.dueDate,
    this.watchers = const [],
  });

  String get feedbackThreadKey => feedbackThreadId ?? id;

  List<String> get normalizedLabels {
    final seen = <String>{};
    return labels
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty && seen.add(label))
        .toList(growable: false);
  }

  bool isOverdue(DateTime now) {
    if (resolved || dueDate == null) return false;
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    final today = DateTime(now.year, now.month, now.day);
    return due.isBefore(today);
  }

  CanvasComment copyWith({
    String? id,
    String? feedbackThreadId,
    String? nodeId,
    String? authorId,
    String? authorName,
    String? text,
    double? x,
    double? y,
    bool? resolved,
    DateTime? createdAt,
    DateTime? editedAt,
    List<CommentReply>? replies,
    List<String>? mentions,
    Map<String, int>? reactions,
    List<CommentAttachment>? attachments,
    List<String>? labels,
    Object? assigneeId = _unset,
    Object? assigneeName = _unset,
    Object? dueDate = _unset,
    List<String>? watchers,
  }) {
    return CanvasComment(
      id: id ?? this.id,
      feedbackThreadId: feedbackThreadId ?? this.feedbackThreadId,
      nodeId: nodeId ?? this.nodeId,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      text: text ?? this.text,
      x: x ?? this.x,
      y: y ?? this.y,
      resolved: resolved ?? this.resolved,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      replies: replies ?? this.replies,
      mentions: mentions ?? this.mentions,
      reactions: reactions ?? this.reactions,
      attachments: attachments ?? this.attachments,
      labels: labels ?? this.labels,
      assigneeId: assigneeId == _unset
          ? this.assigneeId
          : assigneeId as String?,
      assigneeName: assigneeName == _unset
          ? this.assigneeName
          : assigneeName as String?,
      dueDate: dueDate == _unset ? this.dueDate : dueDate as DateTime?,
      watchers: watchers ?? this.watchers,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'feedbackThreadId': feedbackThreadId,
    'nodeId': nodeId,
    'authorId': authorId,
    'authorName': authorName,
    'text': text,
    'x': x,
    'y': y,
    'resolved': resolved,
    'createdAt': createdAt.toIso8601String(),
    'editedAt': editedAt?.toIso8601String(),
    'replies': replies.map((r) => r.toJson()).toList(),
    'mentions': mentions,
    'reactions': reactions,
    'attachments': attachments
        .map((attachment) => attachment.toJson())
        .toList(),
    'labels': normalizedLabels,
    'assigneeId': assigneeId,
    'assigneeName': assigneeName,
    'dueDate': dueDate?.toIso8601String(),
    'watchers': watchers,
  };

  factory CanvasComment.fromJson(Map<String, dynamic> json) => CanvasComment(
    id: json['id'] as String,
    feedbackThreadId: json['feedbackThreadId'] as String?,
    nodeId: json['nodeId'] as String?,
    authorId: json['authorId'] as String,
    authorName: json['authorName'] as String,
    text: json['text'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    resolved: json['resolved'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
    editedAt: DateTime.tryParse(json['editedAt']?.toString() ?? ''),
    replies:
        (json['replies'] as List<dynamic>?)
            ?.map((r) => CommentReply.fromJson(r as Map<String, dynamic>))
            .toList() ??
        const [],
    mentions:
        (json['mentions'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    reactions:
        (json['reactions'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ) ??
        const {},
    attachments:
        (json['attachments'] as List<dynamic>?)
            ?.whereType<Map>()
            .map(
              (attachment) => CommentAttachment.fromJson(
                Map<String, dynamic>.from(attachment),
              ),
            )
            .toList() ??
        const [],
    labels:
        (json['labels'] as List<dynamic>?)
            ?.map((value) => value.toString())
            .toList() ??
        const [],
    assigneeId: json['assigneeId']?.toString(),
    assigneeName: json['assigneeName']?.toString(),
    dueDate: DateTime.tryParse(json['dueDate']?.toString() ?? ''),
    watchers:
        (json['watchers'] as List<dynamic>?)
            ?.map((value) => value.toString())
            .toList() ??
        const [],
  );

  static const Object _unset = Object();
}

class RemoteCursor {
  final String userId;
  final String userName;
  final Color userColor;
  final double x;
  final double y;
  final String? selectedNodeId;
  final Set<String> selectedNodeIds;
  final DateTime lastActive;

  const RemoteCursor({
    required this.userId,
    required this.userName,
    required this.userColor,
    required this.x,
    required this.y,
    this.selectedNodeId,
    this.selectedNodeIds = const {},
    required this.lastActive,
  });

  RemoteCursor copyWith({
    String? userId,
    String? userName,
    Color? userColor,
    double? x,
    double? y,
    String? selectedNodeId,
    Set<String>? selectedNodeIds,
    DateTime? lastActive,
  }) {
    return RemoteCursor(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userColor: userColor ?? this.userColor,
      x: x ?? this.x,
      y: y ?? this.y,
      selectedNodeId: selectedNodeId ?? this.selectedNodeId,
      selectedNodeIds: selectedNodeIds ?? this.selectedNodeIds,
      lastActive: lastActive ?? this.lastActive,
    );
  }
}
