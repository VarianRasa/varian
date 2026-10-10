enum PluginPermission {
  readSelection,
  readDocument,
  writeNodes,
  writeEdges,
  export,
  storage,
  network,
  listenEvents,
  runAI,
}

enum PluginCapability {
  selection,
  document,
  nodes,
  edges,
  export,
  storage,
  network,
  events,
  ai,
  ui,
}

class PluginSandboxLimits {
  final int maxCommandsPerMinute;
  final int maxEventSubscriptions;
  final int maxStorageBytes;
  final int maxExecutionMillis;
  final int maxNetworkRequestsPerMinute;

  const PluginSandboxLimits({
    this.maxCommandsPerMinute = 60,
    this.maxEventSubscriptions = 20,
    this.maxStorageBytes = 10 * 1024 * 1024,
    this.maxExecutionMillis = 5000,
    this.maxNetworkRequestsPerMinute = 30,
  });

  List<String> validate() {
    final errors = <String>[];
    if (maxCommandsPerMinute < 1 || maxCommandsPerMinute > 1000) {
      errors.add('Plugin command limit must be between 1 and 1000 per minute.');
    }
    if (maxEventSubscriptions < 0 || maxEventSubscriptions > 100) {
      errors.add('Plugin event subscription limit must be between 0 and 100.');
    }
    if (maxStorageBytes < 0 || maxStorageBytes > 1024 * 1024 * 1024) {
      errors.add('Plugin storage limit must be between 0 and 1 GiB.');
    }
    if (maxExecutionMillis < 1 || maxExecutionMillis > 60000) {
      errors.add(
        'Plugin execution limit must be between 1 and 60000 milliseconds.',
      );
    }
    if (maxNetworkRequestsPerMinute < 0 || maxNetworkRequestsPerMinute > 600) {
      errors.add('Plugin network limit must be between 0 and 600 per minute.');
    }
    return errors;
  }

  Map<String, dynamic> toJson() => {
    'maxCommandsPerMinute': maxCommandsPerMinute,
    'maxEventSubscriptions': maxEventSubscriptions,
    'maxStorageBytes': maxStorageBytes,
    'maxExecutionMillis': maxExecutionMillis,
    'maxNetworkRequestsPerMinute': maxNetworkRequestsPerMinute,
  };

  factory PluginSandboxLimits.fromJson(Object? raw) {
    if (raw is! Map) return const PluginSandboxLimits();
    return PluginSandboxLimits(
      maxCommandsPerMinute:
          (raw['maxCommandsPerMinute'] as num?)?.toInt() ?? 60,
      maxEventSubscriptions:
          (raw['maxEventSubscriptions'] as num?)?.toInt() ?? 20,
      maxStorageBytes:
          (raw['maxStorageBytes'] as num?)?.toInt() ?? 10 * 1024 * 1024,
      maxExecutionMillis: (raw['maxExecutionMillis'] as num?)?.toInt() ?? 5000,
      maxNetworkRequestsPerMinute:
          (raw['maxNetworkRequestsPerMinute'] as num?)?.toInt() ?? 30,
    );
  }
}

class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String description;
  final List<PluginPermission> permissions;
  final String entrypoint;
  final String apiVersion;
  final List<PluginCapability> capabilities;
  final List<String> uiExtensionPoints;
  final PluginSandboxLimits sandboxLimits;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    this.description = '',
    this.permissions = const [],
    this.entrypoint = 'main.dart.js',
    this.apiVersion = '1.0',
    this.capabilities = const [],
    this.uiExtensionPoints = const [],
    this.sandboxLimits = const PluginSandboxLimits(),
  });

  List<String> validate() {
    final errors = <String>[];
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$').hasMatch(id)) {
      errors.add('Plugin ID must be a lowercase package-safe identifier.');
    }
    if (name.trim().isEmpty) errors.add('Plugin name is required.');
    if (!RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(version)) {
      errors.add('Plugin version must use semantic versioning.');
    }
    if (entrypoint.trim().isEmpty) errors.add('Plugin entrypoint is required.');
    if (!RegExp(r'^\d+\.\d+$').hasMatch(apiVersion)) {
      errors.add('Plugin API version must use major.minor format.');
    }
    if (permissions.toSet().length != permissions.length) {
      errors.add('Plugin permissions must not be duplicated.');
    }
    if (capabilities.toSet().length != capabilities.length) {
      errors.add('Plugin capabilities must not be duplicated.');
    }
    const supportedExtensionPoints = {
      'toolbar',
      'panel',
      'context_menu',
      'command_palette',
    };
    if (uiExtensionPoints.any(
      (point) => !supportedExtensionPoints.contains(point),
    )) {
      errors.add('Plugin UI extension point is not supported.');
    }
    errors.addAll(sandboxLimits.validate());
    final effective = effectiveCapabilities;
    if (effective.contains(PluginCapability.network) &&
        !requests(PluginPermission.network)) {
      errors.add('Network capability requires the network permission.');
    }
    if (effective.contains(PluginCapability.ai) &&
        !requests(PluginPermission.runAI)) {
      errors.add('AI capability requires the runAI permission.');
    }
    return errors;
  }

  bool requests(PluginPermission permission) =>
      permissions.contains(permission);

  List<PluginCapability> get effectiveCapabilities => capabilities.isNotEmpty
      ? capabilities
      : [
          if (requests(PluginPermission.readSelection))
            PluginCapability.selection,
          if (requests(PluginPermission.readDocument))
            PluginCapability.document,
          if (requests(PluginPermission.writeNodes)) PluginCapability.nodes,
          if (requests(PluginPermission.writeEdges)) PluginCapability.edges,
          if (requests(PluginPermission.export)) PluginCapability.export,
          if (requests(PluginPermission.storage)) PluginCapability.storage,
          if (requests(PluginPermission.network)) PluginCapability.network,
          if (requests(PluginPermission.listenEvents)) PluginCapability.events,
          if (requests(PluginPermission.runAI)) PluginCapability.ai,
        ];

  bool supports(PluginCapability capability) =>
      effectiveCapabilities.contains(capability);

  PluginSandbox createSandbox() => PluginSandbox(this);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'description': description,
    'permissions': permissions.map((permission) => permission.name).toList(),
    'entrypoint': entrypoint,
    'apiVersion': apiVersion,
    'capabilities': capabilities.map((capability) => capability.name).toList(),
    'uiExtensionPoints': uiExtensionPoints,
    'sandboxLimits': sandboxLimits.toJson(),
  };

  factory PluginManifest.fromJson(Map<String, dynamic> json) => PluginManifest(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    version: json['version'] as String? ?? '0.0.0',
    description: json['description'] as String? ?? '',
    permissions: _permissionsFromJson(json['permissions']),
    entrypoint: json['entrypoint'] as String? ?? 'main.dart.js',
    apiVersion: json['apiVersion'] as String? ?? '1.0',
    capabilities: (json['capabilities'] as List<dynamic>? ?? const [])
        .map(
          (value) => PluginCapability.values
              .where((item) => item.name == value)
              .firstOrNull,
        )
        .whereType<PluginCapability>()
        .toList(growable: false),
    uiExtensionPoints: (json['uiExtensionPoints'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false),
    sandboxLimits: PluginSandboxLimits.fromJson(json['sandboxLimits']),
  );

  static List<PluginPermission> _permissionsFromJson(Object? raw) {
    if (raw is! List) return const [];
    final permissions = <PluginPermission>[];
    for (final value in raw) {
      if (value is! String) {
        throw const FormatException('Plugin permission must be a string.');
      }
      final permission = PluginPermission.values
          .where((candidate) => candidate.name == value)
          .firstOrNull;
      if (permission == null) {
        throw FormatException('Unknown plugin permission: $value');
      }
      permissions.add(permission);
    }
    return permissions;
  }
}

enum PluginEventType { selectionChanged, documentChanged, exportRequested }

class PluginEvent {
  final PluginEventType type;
  final DateTime timestamp;
  final Map<String, dynamic> payload;

  const PluginEvent({
    required this.type,
    required this.timestamp,
    this.payload = const {},
  });
}

enum PluginCommandType { createNode, updateNode, deleteNode, exportDocument }

class PluginCommand {
  final PluginCommandType type;
  final Map<String, dynamic> payload;

  const PluginCommand({required this.type, this.payload = const {}});
}

class PluginSandbox {
  final PluginManifest manifest;

  const PluginSandbox(this.manifest);

  bool canReadEvent(PluginEventType event) =>
      manifest.requests(PluginPermission.listenEvents) ||
      (event == PluginEventType.selectionChanged &&
          manifest.requests(PluginPermission.readSelection));

  bool canRun(PluginCommand command) {
    final permission = switch (command.type) {
      PluginCommandType.createNode ||
      PluginCommandType.updateNode => PluginPermission.writeNodes,
      PluginCommandType.deleteNode => PluginPermission.writeNodes,
      PluginCommandType.exportDocument => PluginPermission.export,
    };
    return manifest.requests(permission);
  }

  void require(PluginPermission permission) {
    if (!manifest.requests(permission)) {
      throw StateError('Plugin is missing permission: ${permission.name}');
    }
  }
}

class AccessibilitySettings {
  final bool reducedMotion;
  final bool highContrast;
  final bool keyboardOnly;
  final bool largerText;
  final bool alwaysShowFocus;
  final Map<String, String> shortcuts;
  final String locale;
  final double textScaleFactor;
  final bool forceRtl;
  final bool colorBlindSafe;

  const AccessibilitySettings({
    this.reducedMotion = false,
    this.highContrast = false,
    this.keyboardOnly = false,
    this.largerText = false,
    this.alwaysShowFocus = true,
    this.shortcuts = const {},
    this.locale = 'en',
    this.textScaleFactor = 1.0,
    this.forceRtl = false,
    this.colorBlindSafe = false,
  });

  Duration motionDuration(Duration normal) =>
      reducedMotion ? Duration.zero : normal;

  AccessibilitySettings copyWith({
    bool? reducedMotion,
    bool? highContrast,
    bool? keyboardOnly,
    bool? largerText,
    bool? alwaysShowFocus,
    Map<String, String>? shortcuts,
    String? locale,
    double? textScaleFactor,
    bool? forceRtl,
    bool? colorBlindSafe,
  }) => AccessibilitySettings(
    reducedMotion: reducedMotion ?? this.reducedMotion,
    highContrast: highContrast ?? this.highContrast,
    keyboardOnly: keyboardOnly ?? this.keyboardOnly,
    largerText: largerText ?? this.largerText,
    alwaysShowFocus: alwaysShowFocus ?? this.alwaysShowFocus,
    shortcuts: shortcuts ?? this.shortcuts,
    locale: locale ?? this.locale,
    textScaleFactor: textScaleFactor ?? this.textScaleFactor,
    forceRtl: forceRtl ?? this.forceRtl,
    colorBlindSafe: colorBlindSafe ?? this.colorBlindSafe,
  );

  Map<String, dynamic> toJson() => {
    'reducedMotion': reducedMotion,
    'highContrast': highContrast,
    'keyboardOnly': keyboardOnly,
    'largerText': largerText,
    'alwaysShowFocus': alwaysShowFocus,
    'shortcuts': shortcuts,
    'locale': locale,
    'textScaleFactor': textScaleFactor,
    'forceRtl': forceRtl,
    'colorBlindSafe': colorBlindSafe,
  };

  factory AccessibilitySettings.fromJson(Object? raw) {
    if (raw is! Map) return const AccessibilitySettings();

    bool readBool(String key, bool fallback) =>
        raw[key] is bool ? raw[key] as bool : fallback;
    String readString(String key, String fallback) =>
        raw[key] is String ? raw[key] as String : fallback;
    double readScale() {
      final value = raw['textScaleFactor'];
      final scale = value is num ? value.toDouble() : 1.0;
      return scale.clamp(0.8, 2.0).toDouble();
    }

    final shortcuts = <String, String>{};
    final rawShortcuts = raw['shortcuts'];
    if (rawShortcuts is Map) {
      for (final entry in rawShortcuts.entries) {
        if (entry.key is String && entry.value is String) {
          shortcuts[entry.key as String] = entry.value as String;
        }
      }
    }

    return AccessibilitySettings(
      reducedMotion: readBool('reducedMotion', false),
      highContrast: readBool('highContrast', false),
      keyboardOnly: readBool('keyboardOnly', false),
      largerText: readBool('largerText', false),
      alwaysShowFocus: readBool('alwaysShowFocus', true),
      shortcuts: shortcuts,
      locale: readString('locale', 'en'),
      textScaleFactor: readScale(),
      forceRtl: readBool('forceRtl', false),
      colorBlindSafe: readBool('colorBlindSafe', false),
    );
  }
}

class WorkspaceQuota {
  final int storageBytes;
  final int assetBytes;
  final int aiCredits;
  final int projectCount;

  const WorkspaceQuota({
    this.storageBytes = 0,
    this.assetBytes = 0,
    this.aiCredits = 0,
    this.projectCount = 0,
  });

  bool allows({
    int storageBytes = 0,
    int assetBytes = 0,
    int aiCredits = 0,
    int projectCount = 0,
  }) =>
      storageBytes <= this.storageBytes &&
      assetBytes <= this.assetBytes &&
      aiCredits <= this.aiCredits &&
      projectCount <= this.projectCount;
}

class WorkspaceUsage {
  final int storageBytes;
  final int assetBytes;
  final int aiCredits;
  final int projectCount;

  const WorkspaceUsage({
    this.storageBytes = 0,
    this.assetBytes = 0,
    this.aiCredits = 0,
    this.projectCount = 0,
  });

  WorkspaceUsage add({
    int storageBytes = 0,
    int assetBytes = 0,
    int aiCredits = 0,
    int projectCount = 0,
  }) => WorkspaceUsage(
    storageBytes: this.storageBytes + storageBytes,
    assetBytes: this.assetBytes + assetBytes,
    aiCredits: this.aiCredits + aiCredits,
    projectCount: this.projectCount + projectCount,
  );

  bool within(WorkspaceQuota quota) => quota.allows(
    storageBytes: storageBytes,
    assetBytes: assetBytes,
    aiCredits: aiCredits,
    projectCount: projectCount,
  );

  factory WorkspaceUsage.fromJson(Object? raw) {
    if (raw is! Map) return const WorkspaceUsage();
    return WorkspaceUsage(
      storageBytes: (raw['storageBytes'] as num?)?.toInt() ?? 0,
      assetBytes: (raw['assetBytes'] as num?)?.toInt() ?? 0,
      aiCredits: (raw['aiCredits'] as num?)?.toInt() ?? 0,
      projectCount: (raw['projectCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'storageBytes': storageBytes,
    'assetBytes': assetBytes,
    'aiCredits': aiCredits,
    'projectCount': projectCount,
  };
}

class WorkspaceAuditEvent {
  final String id;
  final String actorId;
  final String action;
  final String operation;
  final String targetType;
  final String targetId;
  final String result;
  final String? correlationId;
  final String? projectId;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  const WorkspaceAuditEvent({
    required this.id,
    required this.actorId,
    required this.action,
    this.operation = '',
    this.targetType = '',
    this.targetId = '',
    this.result = 'success',
    this.correlationId,
    required this.timestamp,
    this.projectId,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'actorId': actorId,
    'action': action,
    'operation': operation,
    'targetType': targetType,
    'targetId': targetId,
    'result': result,
    'correlationId': correlationId,
    'projectId': projectId,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'metadata': metadata,
  };

  factory WorkspaceAuditEvent.fromJson(Map<String, dynamic> json) =>
      WorkspaceAuditEvent(
        id: _auditString(json, 'id', fallback: 'unknown'),
        actorId: _auditString(json, 'actorId', snakeCase: 'actor_id'),
        action: _auditString(json, 'action'),
        operation: _auditString(
          json,
          'operation',
          snakeCase: 'operation',
          fallback: _auditString(json, 'action'),
        ),
        targetType: _auditString(
          json,
          'targetType',
          snakeCase: 'target_type',
          fallback: 'project',
        ),
        targetId: _auditString(
          json,
          'targetId',
          snakeCase: 'target_id',
          fallback: _auditString(json, 'projectId', snakeCase: 'project_id'),
        ),
        result: _auditString(
          json,
          'result',
          snakeCase: 'result',
          fallback: 'success',
        ),
        correlationId: _auditNullableString(
          json,
          'correlationId',
          snakeCase: 'correlation_id',
        ),
        projectId: _auditNullableString(
          json,
          'projectId',
          snakeCase: 'project_id',
        ),
        timestamp: DateTime.parse(
          _auditString(json, 'timestamp', snakeCase: 'created_at'),
        ),
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const {},
      );

  static String _auditString(
    Map<String, dynamic> json,
    String key, {
    String? snakeCase,
    String fallback = '',
  }) {
    final value = json[key] ?? (snakeCase == null ? null : json[snakeCase]);
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  static String? _auditNullableString(
    Map<String, dynamic> json,
    String key, {
    String? snakeCase,
  }) {
    final value = json[key] ?? (snakeCase == null ? null : json[snakeCase]);
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class RetentionPolicy {
  final Duration auditLogRetention;
  final Duration trashRetention;
  final bool allowUserExport;

  const RetentionPolicy({
    this.auditLogRetention = const Duration(days: 365),
    this.trashRetention = const Duration(days: 30),
    this.allowUserExport = true,
  });

  bool shouldPurge(DateTime createdAt, DateTime now, Duration retention) =>
      !createdAt.add(retention).isAfter(now);
}

class WorkspacePolicy {
  final WorkspaceQuota quota;
  final RetentionPolicy retention;
  final bool allowPublicSharing;
  final bool allowEmbeds;
  final bool allowAiGeneration;
  final bool requireAuditLog;
  final bool allowDataExport;
  final String billingPlan;
  final String? billingCustomerReference;

  const WorkspacePolicy({
    this.quota = const WorkspaceQuota(),
    this.retention = const RetentionPolicy(),
    this.allowPublicSharing = true,
    this.allowEmbeds = true,
    this.allowAiGeneration = true,
    this.requireAuditLog = true,
    this.allowDataExport = true,
    this.billingPlan = 'free',
    this.billingCustomerReference,
  });

  bool canCreateProject(WorkspaceUsage usage) =>
      usage.projectCount < quota.projectCount;

  bool canSpendAi(WorkspaceUsage usage, int credits) =>
      allowAiGeneration && usage.aiCredits + credits <= quota.aiCredits;

  bool canExportData() => allowDataExport && retention.allowUserExport;

  WorkspacePolicy copyWith({
    WorkspaceQuota? quota,
    RetentionPolicy? retention,
    bool? allowPublicSharing,
    bool? allowEmbeds,
    bool? allowAiGeneration,
    bool? requireAuditLog,
    bool? allowDataExport,
    String? billingPlan,
    Object? billingCustomerReference = _sentinel,
  }) => WorkspacePolicy(
    quota: quota ?? this.quota,
    retention: retention ?? this.retention,
    allowPublicSharing: allowPublicSharing ?? this.allowPublicSharing,
    allowEmbeds: allowEmbeds ?? this.allowEmbeds,
    allowAiGeneration: allowAiGeneration ?? this.allowAiGeneration,
    requireAuditLog: requireAuditLog ?? this.requireAuditLog,
    allowDataExport: allowDataExport ?? this.allowDataExport,
    billingPlan: billingPlan ?? this.billingPlan,
    billingCustomerReference: billingCustomerReference == _sentinel
        ? this.billingCustomerReference
        : billingCustomerReference as String?,
  );

  Map<String, dynamic> toJson() => {
    'quota': {
      'storageBytes': quota.storageBytes,
      'assetBytes': quota.assetBytes,
      'aiCredits': quota.aiCredits,
      'projectCount': quota.projectCount,
    },
    'retention': {
      'auditLogRetentionDays': retention.auditLogRetention.inDays,
      'trashRetentionDays': retention.trashRetention.inDays,
      'allowUserExport': retention.allowUserExport,
    },
    'allowPublicSharing': allowPublicSharing,
    'allowEmbeds': allowEmbeds,
    'allowAiGeneration': allowAiGeneration,
    'requireAuditLog': requireAuditLog,
    'allowDataExport': allowDataExport,
    'billingPlan': billingPlan,
    'billingCustomerReference': billingCustomerReference,
  };

  factory WorkspacePolicy.fromJson(Object? raw) {
    if (raw is! Map) return const WorkspacePolicy();
    final quota = raw['quota'];
    final retention = raw['retention'];
    return WorkspacePolicy(
      quota: quota is Map
          ? WorkspaceQuota(
              storageBytes: (quota['storageBytes'] as num?)?.toInt() ?? 0,
              assetBytes: (quota['assetBytes'] as num?)?.toInt() ?? 0,
              aiCredits: (quota['aiCredits'] as num?)?.toInt() ?? 0,
              projectCount: (quota['projectCount'] as num?)?.toInt() ?? 0,
            )
          : const WorkspaceQuota(),
      retention: retention is Map
          ? RetentionPolicy(
              auditLogRetention: Duration(
                days:
                    (retention['auditLogRetentionDays'] as num?)?.toInt() ??
                    365,
              ),
              trashRetention: Duration(
                days: (retention['trashRetentionDays'] as num?)?.toInt() ?? 30,
              ),
              allowUserExport: retention['allowUserExport'] as bool? ?? true,
            )
          : const RetentionPolicy(),
      allowPublicSharing: raw['allowPublicSharing'] as bool? ?? true,
      allowEmbeds: raw['allowEmbeds'] as bool? ?? true,
      allowAiGeneration: raw['allowAiGeneration'] as bool? ?? true,
      requireAuditLog: raw['requireAuditLog'] as bool? ?? true,
      allowDataExport: raw['allowDataExport'] as bool? ?? true,
      billingPlan: raw['billingPlan'] as String? ?? 'free',
      billingCustomerReference: raw['billingCustomerReference'] as String?,
    );
  }

  static const Object _sentinel = Object();
}

class WorkspaceOwnerEligibility {
  final String projectId;
  final String ownerId;
  final String currentUserId;

  const WorkspaceOwnerEligibility({
    required this.projectId,
    required this.ownerId,
    required this.currentUserId,
  });

  bool get isOwner => currentUserId == ownerId;
}

class ProjectDeletionRequestReceipt {
  final String projectId;
  final DateTime deletionRequestedAt;

  const ProjectDeletionRequestReceipt({
    required this.projectId,
    required this.deletionRequestedAt,
  });

  factory ProjectDeletionRequestReceipt.fromJson(Map<String, dynamic> json) {
    final projectId = json['projectId'];
    final requestedAt = json['deletionRequestedAt'];
    if (projectId is! String || projectId.trim().isEmpty) {
      throw const FormatException(
        'Project deletion RPC returned no project ID.',
      );
    }
    if (requestedAt is! String) {
      throw const FormatException(
        'Project deletion RPC returned no request timestamp.',
      );
    }
    final parsedAt = DateTime.tryParse(requestedAt);
    if (parsedAt == null) {
      throw const FormatException(
        'Project deletion RPC returned an invalid request timestamp.',
      );
    }
    return ProjectDeletionRequestReceipt(
      projectId: projectId,
      deletionRequestedAt: parsedAt,
    );
  }
}

class WorkspaceGovernanceSnapshot {
  final String projectId;
  final WorkspacePolicy policy;
  final WorkspaceUsage usage;
  final DateTime? deletionRequestedAt;
  final DateTime? archivedAt;

  const WorkspaceGovernanceSnapshot({
    required this.projectId,
    required this.policy,
    required this.usage,
    this.deletionRequestedAt,
    this.archivedAt,
  });

  bool get hasPendingDeletionRequest => deletionRequestedAt != null;

  factory WorkspaceGovernanceSnapshot.fromJson(Map<String, dynamic> json) {
    final projectId = json['projectId'];
    if (projectId is! String || projectId.trim().isEmpty) {
      throw const FormatException(
        'Workspace governance response has no project ID.',
      );
    }
    if (!json.containsKey('deletionRequestedAt')) {
      throw const FormatException(
        'Workspace governance response has unknown deletion status.',
      );
    }
    final requestedAt = _parseLifecycleTimestamp(
      json['deletionRequestedAt'],
      field: 'deletionRequestedAt',
    );
    final archivedAt = _parseLifecycleTimestamp(
      json['archivedAt'],
      field: 'archivedAt',
    );
    return WorkspaceGovernanceSnapshot(
      projectId: projectId,
      policy: WorkspacePolicy.fromJson(json['policy']),
      usage: WorkspaceUsage.fromJson(json['usage']),
      deletionRequestedAt: requestedAt,
      archivedAt: archivedAt,
    );
  }

  static DateTime? _parseLifecycleTimestamp(
    Object? raw, {
    required String field,
  }) {
    if (raw == null) return null;
    if (raw is! String) {
      throw FormatException('Workspace governance $field is invalid.');
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw FormatException('Workspace governance $field is invalid.');
    }
    return parsed;
  }

  static const Object _unset = Object();

  WorkspaceGovernanceSnapshot copyWith({
    String? projectId,
    WorkspacePolicy? policy,
    WorkspaceUsage? usage,
    Object? deletionRequestedAt = _unset,
    Object? archivedAt = _unset,
  }) => WorkspaceGovernanceSnapshot(
    projectId: projectId ?? this.projectId,
    policy: policy ?? this.policy,
    usage: usage ?? this.usage,
    deletionRequestedAt: identical(deletionRequestedAt, _unset)
        ? this.deletionRequestedAt
        : deletionRequestedAt as DateTime?,
    archivedAt: identical(archivedAt, _unset)
        ? this.archivedAt
        : archivedAt as DateTime?,
  );
}
