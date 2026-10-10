enum PresenterRemoteRole { owner, presenter, viewer }

enum PresenterRemoteAction { next, previous, jump, pause, resume, stop }

class PresenterRemoteSession {
  final String sessionId;
  final String projectId;
  final String presenterId;
  final PresenterRemoteRole role;
  final DateTime expiresAt;
  final bool consentGranted;

  const PresenterRemoteSession({
    required this.sessionId,
    required this.projectId,
    required this.presenterId,
    required this.role,
    required this.expiresAt,
    this.consentGranted = false,
  });

  bool isActive(DateTime now) =>
      consentGranted &&
      role != PresenterRemoteRole.viewer &&
      expiresAt.isAfter(now);

  bool canPerform(PresenterRemoteAction action, DateTime now) =>
      isActive(now) &&
      (action != PresenterRemoteAction.stop ||
          role == PresenterRemoteRole.owner ||
          role == PresenterRemoteRole.presenter);

  PresenterRemoteSession copyWith({
    String? sessionId,
    String? projectId,
    String? presenterId,
    PresenterRemoteRole? role,
    DateTime? expiresAt,
    bool? consentGranted,
  }) => PresenterRemoteSession(
    sessionId: sessionId ?? this.sessionId,
    projectId: projectId ?? this.projectId,
    presenterId: presenterId ?? this.presenterId,
    role: role ?? this.role,
    expiresAt: expiresAt ?? this.expiresAt,
    consentGranted: consentGranted ?? this.consentGranted,
  );

  PresenterRemoteSession grantConsent() => PresenterRemoteSession(
    sessionId: sessionId,
    projectId: projectId,
    presenterId: presenterId,
    role: role,
    expiresAt: expiresAt,
    consentGranted: true,
  );

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'projectId': projectId,
    'presenterId': presenterId,
    'role': role.name,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'consentGranted': consentGranted,
  };

  factory PresenterRemoteSession.fromJson(Map<String, dynamic> json) {
    final rawRole = json['role']?.toString();
    final role = PresenterRemoteRole.values.firstWhere(
      (value) => value.name == rawRole,
      orElse: () => PresenterRemoteRole.viewer,
    );
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    if (json['sessionId'] is! String ||
        json['projectId'] is! String ||
        json['presenterId'] is! String ||
        expiresAt == null) {
      throw const FormatException('Invalid presenter remote session payload.');
    }
    return PresenterRemoteSession(
      sessionId: json['sessionId'] as String,
      projectId: json['projectId'] as String,
      presenterId: json['presenterId'] as String,
      role: role,
      expiresAt: expiresAt,
      consentGranted: json['consentGranted'] as bool? ?? false,
    );
  }
}

class PresenterRemoteCommand {
  final String commandId;
  final String sessionId;
  final PresenterRemoteAction action;
  final int? frameIndex;
  final DateTime createdAt;
  final String? actorId;
  final String? projectId;

  const PresenterRemoteCommand({
    required this.commandId,
    required this.sessionId,
    required this.action,
    required this.createdAt,
    this.frameIndex,
    this.actorId,
    this.projectId,
  });

  bool isValidFor(PresenterRemoteSession session, DateTime now) =>
      session.sessionId == sessionId &&
      (projectId == null || projectId == session.projectId) &&
      session.canPerform(action, now);

  Map<String, dynamic> toJson() => {
    'commandId': commandId,
    'sessionId': sessionId,
    'action': action.name,
    'frameIndex': frameIndex,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (actorId != null) 'actorId': actorId,
    if (projectId != null) 'projectId': projectId,
  };

  factory PresenterRemoteCommand.fromJson(Map<String, dynamic> json) {
    final rawAction = json['action']?.toString();
    final action = PresenterRemoteAction.values.firstWhere(
      (value) => value.name == rawAction,
      orElse: () => PresenterRemoteAction.stop,
    );
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (json['commandId'] is! String ||
        json['sessionId'] is! String ||
        createdAt == null) {
      throw const FormatException('Invalid presenter remote command payload.');
    }
    return PresenterRemoteCommand(
      commandId: json['commandId'] as String,
      sessionId: json['sessionId'] as String,
      action: action,
      frameIndex: (json['frameIndex'] as num?)?.toInt(),
      createdAt: createdAt,
      actorId: json['actorId'] as String?,
      projectId: json['projectId'] as String?,
    );
  }
}
