import '../../../domain/models/ai_job.dart';
import 'ai_provider_health.dart';
import 'ai_workflow_contract.dart';

class AIProviderPolicy {
  final String provider;
  final bool enabled;
  final Set<String> allowedModels;
  final bool allowExperimental;
  final int? maxCreditsPerJob;
  final int? rateLimitCount;
  final Duration? rateLimitWindow;

  const AIProviderPolicy({
    required this.provider,
    this.enabled = true,
    this.allowedModels = const {},
    this.allowExperimental = false,
    this.maxCreditsPerJob,
    this.rateLimitCount,
    this.rateLimitWindow,
  });

  bool allowsModel(String? model) {
    if (allowedModels.isEmpty) return true;
    final normalized = model?.trim();
    return normalized != null && allowedModels.contains(normalized);
  }

  List<String> validate() {
    final errors = <String>[];
    if (provider.trim().isEmpty) errors.add('Provider name is required.');
    if (maxCreditsPerJob != null && maxCreditsPerJob! <= 0) {
      errors.add('Provider max credits per job must be greater than zero.');
    }
    if (rateLimitCount != null && rateLimitCount! <= 0) {
      errors.add('Provider rate limit count must be greater than zero.');
    }
    if (rateLimitWindow != null && rateLimitWindow!.inSeconds <= 0) {
      errors.add('Provider rate limit window must be greater than zero.');
    }
    if (allowedModels.any((model) => model.trim().isEmpty)) {
      errors.add('Provider model allowlist cannot contain empty values.');
    }
    return errors;
  }

  AIProviderPolicy copyWith({
    String? provider,
    bool? enabled,
    Set<String>? allowedModels,
    bool? allowExperimental,
    int? maxCreditsPerJob,
    int? rateLimitCount,
    Duration? rateLimitWindow,
  }) => AIProviderPolicy(
    provider: provider ?? this.provider,
    enabled: enabled ?? this.enabled,
    allowedModels: allowedModels ?? this.allowedModels,
    allowExperimental: allowExperimental ?? this.allowExperimental,
    maxCreditsPerJob: maxCreditsPerJob ?? this.maxCreditsPerJob,
    rateLimitCount: rateLimitCount ?? this.rateLimitCount,
    rateLimitWindow: rateLimitWindow ?? this.rateLimitWindow,
  );

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'enabled': enabled,
    'allowedModels': allowedModels.toList(growable: false),
    'allowExperimental': allowExperimental,
    'maxCreditsPerJob': maxCreditsPerJob,
    'rateLimitCount': rateLimitCount,
    'rateLimitWindowSeconds': rateLimitWindow?.inSeconds,
  };

  factory AIProviderPolicy.fromJson(Map<String, dynamic> json) {
    final provider = json['provider']?.toString().trim() ?? '';
    return AIProviderPolicy(
      provider: provider,
      enabled: json['enabled'] as bool? ?? true,
      allowedModels: (json['allowedModels'] as List<dynamic>? ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toSet(),
      allowExperimental: json['allowExperimental'] as bool? ?? false,
      maxCreditsPerJob: (json['maxCreditsPerJob'] as num?)?.toInt(),
      rateLimitCount: (json['rateLimitCount'] as num?)?.toInt(),
      rateLimitWindow: (json['rateLimitWindowSeconds'] as num?) == null
          ? null
          : Duration(seconds: (json['rateLimitWindowSeconds'] as num).toInt()),
    );
  }
}

class AIDataRetentionPolicy {
  final Duration jobRetention;
  final bool retainPrompt;
  final bool retainInputArtifacts;
  final bool retainOutputArtifacts;
  final bool allowProvenanceExport;

  const AIDataRetentionPolicy({
    this.jobRetention = const Duration(days: 30),
    this.retainPrompt = true,
    this.retainInputArtifacts = false,
    this.retainOutputArtifacts = true,
    this.allowProvenanceExport = true,
  });

  bool isExpired(DateTime createdAt, DateTime now) =>
      !createdAt.add(jobRetention).isAfter(now);

  Map<String, dynamic> toJson() => {
    'jobRetentionDays': jobRetention.inDays,
    'retainPrompt': retainPrompt,
    'retainInputArtifacts': retainInputArtifacts,
    'retainOutputArtifacts': retainOutputArtifacts,
    'allowProvenanceExport': allowProvenanceExport,
  };

  factory AIDataRetentionPolicy.fromJson(Object? raw) {
    if (raw is! Map) return const AIDataRetentionPolicy();
    return AIDataRetentionPolicy(
      jobRetention: Duration(
        days: (raw['jobRetentionDays'] as num?)?.toInt() ?? 30,
      ),
      retainPrompt: raw['retainPrompt'] as bool? ?? true,
      retainInputArtifacts: raw['retainInputArtifacts'] as bool? ?? false,
      retainOutputArtifacts: raw['retainOutputArtifacts'] as bool? ?? true,
      allowProvenanceExport: raw['allowProvenanceExport'] as bool? ?? true,
    );
  }
}

class AIGovernancePolicy {
  final bool allowGeneration;
  final bool allowUnknownProviders;
  final Map<String, AIProviderPolicy> providers;
  final List<String> fallbackProviders;
  final double quotaCredits;
  final double budgetAlertThreshold;
  final int maxCreditsPerJob;
  final int rateLimitCount;
  final Duration rateLimitWindow;
  final AIDataRetentionPolicy retention;

  const AIGovernancePolicy({
    this.allowGeneration = true,
    this.allowUnknownProviders = true,
    this.providers = const {},
    this.fallbackProviders = const [],
    this.quotaCredits = 1000,
    this.budgetAlertThreshold = 0.8,
    this.maxCreditsPerJob = 100,
    this.rateLimitCount = 20,
    this.rateLimitWindow = const Duration(minutes: 1),
    this.retention = const AIDataRetentionPolicy(),
  });

  bool get hasStrictProviderAllowlist =>
      !allowUnknownProviders || providers.isNotEmpty;

  List<String> validate() {
    final errors = <String>[];
    if (!quotaCredits.isFinite || quotaCredits < 0) {
      errors.add('AI quota must be a finite non-negative number.');
    }
    if (!budgetAlertThreshold.isFinite ||
        budgetAlertThreshold < 0 ||
        budgetAlertThreshold > 1) {
      errors.add('Budget alert threshold must be between 0 and 1.');
    }
    if (maxCreditsPerJob <= 0) {
      errors.add('Maximum credits per job must be greater than zero.');
    }
    if (rateLimitCount <= 0 || rateLimitWindow.inSeconds <= 0) {
      errors.add('AI rate limit must be greater than zero.');
    }
    final fallbackSet = <String>{};
    for (final provider in fallbackProviders) {
      final normalized = provider.trim();
      if (normalized.isEmpty) {
        errors.add('Fallback provider names cannot be empty.');
      } else if (!fallbackSet.add(normalized)) {
        errors.add('Fallback providers must be unique.');
      }
    }
    for (final entry in providers.entries) {
      if (entry.key.trim() != entry.value.provider.trim()) {
        errors.add('Provider policy key must match its provider name.');
      }
      errors.addAll(entry.value.validate());
    }
    return errors;
  }

  AIGovernancePolicy copyWith({
    bool? allowGeneration,
    bool? allowUnknownProviders,
    Map<String, AIProviderPolicy>? providers,
    List<String>? fallbackProviders,
    double? quotaCredits,
    double? budgetAlertThreshold,
    int? maxCreditsPerJob,
    int? rateLimitCount,
    Duration? rateLimitWindow,
    AIDataRetentionPolicy? retention,
  }) => AIGovernancePolicy(
    allowGeneration: allowGeneration ?? this.allowGeneration,
    allowUnknownProviders: allowUnknownProviders ?? this.allowUnknownProviders,
    providers: providers ?? this.providers,
    fallbackProviders: fallbackProviders ?? this.fallbackProviders,
    quotaCredits: quotaCredits ?? this.quotaCredits,
    budgetAlertThreshold: budgetAlertThreshold ?? this.budgetAlertThreshold,
    maxCreditsPerJob: maxCreditsPerJob ?? this.maxCreditsPerJob,
    rateLimitCount: rateLimitCount ?? this.rateLimitCount,
    rateLimitWindow: rateLimitWindow ?? this.rateLimitWindow,
    retention: retention ?? this.retention,
  );

  Map<String, dynamic> toJson() => {
    'allowGeneration': allowGeneration,
    'allowUnknownProviders': allowUnknownProviders,
    'providers': {
      for (final entry in providers.entries) entry.key: entry.value.toJson(),
    },
    'fallbackProviders': fallbackProviders,
    'quotaCredits': quotaCredits,
    'budgetAlertThreshold': budgetAlertThreshold,
    'maxCreditsPerJob': maxCreditsPerJob,
    'rateLimitCount': rateLimitCount,
    'rateLimitWindowSeconds': rateLimitWindow.inSeconds,
    'retention': retention.toJson(),
  };

  factory AIGovernancePolicy.fromJson(Object? raw) {
    if (raw is! Map) return const AIGovernancePolicy();
    final rawProviders = raw['providers'];
    final providers = <String, AIProviderPolicy>{};
    if (rawProviders is Map) {
      for (final item in rawProviders.entries) {
        if (item.value is! Map) continue;
        final json = Map<String, dynamic>.from(item.value as Map)
          ..putIfAbsent('provider', () => item.key.toString());
        final policy = AIProviderPolicy.fromJson(json);
        if (policy.provider.isNotEmpty) providers[policy.provider] = policy;
      }
    }
    final threshold = (raw['budgetAlertThreshold'] as num?)?.toDouble() ?? 0.8;
    return AIGovernancePolicy(
      allowGeneration: raw['allowGeneration'] as bool? ?? true,
      allowUnknownProviders: raw['allowUnknownProviders'] as bool? ?? true,
      providers: providers,
      fallbackProviders:
          (raw['fallbackProviders'] as List<dynamic>? ?? const [])
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false),
      quotaCredits: (raw['quotaCredits'] as num?)?.toDouble() ?? 1000,
      budgetAlertThreshold: threshold.clamp(0.0, 1.0).toDouble(),
      maxCreditsPerJob: (raw['maxCreditsPerJob'] as num?)?.toInt() ?? 100,
      rateLimitCount: (raw['rateLimitCount'] as num?)?.toInt() ?? 20,
      rateLimitWindow: Duration(
        seconds: (raw['rateLimitWindowSeconds'] as num?)?.toInt() ?? 60,
      ),
      retention: AIDataRetentionPolicy.fromJson(raw['retention']),
    );
  }

  factory AIGovernancePolicy.fromWorkspaceResponse(Object? raw) {
    if (raw is! Map) return const AIGovernancePolicy();
    final response = Map<String, dynamic>.from(raw);
    final workspacePolicy = response['policy'];
    final aiPolicy = <String, dynamic>{
      if (response['aiGovernance'] is Map)
        ...Map<String, dynamic>.from(response['aiGovernance'] as Map),
      if (workspacePolicy is Map && workspacePolicy['aiGovernance'] is Map)
        ...Map<String, dynamic>.from(workspacePolicy['aiGovernance'] as Map),
    };
    if (workspacePolicy is Map) {
      if (workspacePolicy['allowAiGeneration'] is bool) {
        aiPolicy['allowGeneration'] = workspacePolicy['allowAiGeneration'];
      }
      final workspaceQuota = workspacePolicy['quota'];
      if (workspaceQuota is Map && workspaceQuota['aiCredits'] is num) {
        aiPolicy['quotaCredits'] = (workspaceQuota['aiCredits'] as num)
            .toDouble();
      }
    }
    final providerPolicies = response['providerPolicies'];
    if (providerPolicies is Map) aiPolicy['providers'] = providerPolicies;
    return AIGovernancePolicy.fromJson(aiPolicy);
  }
}

enum AIAuthorizationStatus { allowed, duplicate, denied }

class AIAuthorizationDecision {
  final AIAuthorizationStatus status;
  final String jobId;
  final String provider;
  final String? model;
  final double estimatedCredits;
  final bool usedFallback;
  final bool budgetAlert;
  final double remainingCredits;
  final Duration? retryAfter;
  final String? message;
  final DateTime authorizedAt;

  const AIAuthorizationDecision({
    required this.status,
    required this.jobId,
    required this.provider,
    required this.estimatedCredits,
    required this.usedFallback,
    required this.budgetAlert,
    required this.remainingCredits,
    required this.authorizedAt,
    this.model,
    this.retryAfter,
    this.message,
  });

  bool get isAllowed =>
      status == AIAuthorizationStatus.allowed ||
      status == AIAuthorizationStatus.duplicate;

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'jobId': jobId,
    'provider': provider,
    'model': model,
    'estimatedCredits': estimatedCredits,
    'usedFallback': usedFallback,
    'budgetAlert': budgetAlert,
    'remainingCredits': remainingCredits,
    'retryAfterSeconds': retryAfter?.inSeconds,
    'message': message,
    'authorizedAt': authorizedAt.toUtc().toIso8601String(),
  };
}

class _AIAuthorizationRecord {
  final AIAuthorizationDecision decision;
  final DateTime requestedAt;

  const _AIAuthorizationRecord(this.decision, this.requestedAt);
}

class AIGovernanceRuntime {
  AIGovernancePolicy policy;
  AIProviderHealthRegistry health;
  AIQuotaLedger quota;
  final Map<String, _AIAuthorizationRecord> _authorizations = {};
  final Map<String, List<DateTime>> _requestTimes = {};

  AIGovernanceRuntime({
    this.policy = const AIGovernancePolicy(),
    this.health = const AIProviderHealthRegistry(),
    AIQuotaLedger? quota,
  }) : quota =
           quota ??
           AIQuotaLedger(
             snapshots: {
               'workspace': AIQuotaSnapshot(
                 scope: 'workspace',
                 used: 0,
                 limit: policy.quotaCredits,
                 unit: 'credits',
               ),
             },
           );

  void updatePolicy(AIGovernancePolicy nextPolicy) {
    policy = nextPolicy;
    final current = quota['workspace'];
    if (current == null) {
      quota = quota.withSnapshot(
        AIQuotaSnapshot(
          scope: 'workspace',
          used: 0,
          limit: nextPolicy.quotaCredits,
          unit: 'credits',
        ),
      );
      return;
    }
    quota = quota.withSnapshot(
      AIQuotaSnapshot(
        scope: current.scope,
        used: current.used,
        limit: nextPolicy.quotaCredits,
        unit: current.unit,
        resetsAt: current.resetsAt,
      ),
    );
  }

  AIAuthorizationDecision authorize({
    required String jobId,
    required String provider,
    String? model,
    required double estimatedCredits,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final normalizedJobId = jobId.trim();
    final normalizedProvider = provider.trim();
    final normalizedModel = model?.trim().isEmpty == true
        ? null
        : model?.trim();
    final existing = _authorizations[normalizedJobId];
    if (existing != null) {
      return AIAuthorizationDecision(
        status: AIAuthorizationStatus.duplicate,
        jobId: normalizedJobId,
        provider: existing.decision.provider,
        model: existing.decision.model,
        estimatedCredits: existing.decision.estimatedCredits,
        usedFallback: existing.decision.usedFallback,
        budgetAlert: existing.decision.budgetAlert,
        remainingCredits: existing.decision.remainingCredits,
        authorizedAt: existing.decision.authorizedAt,
        message: 'AI job authorization already exists.',
      );
    }
    if (normalizedJobId.isEmpty || normalizedProvider.isEmpty) {
      return _denied(
        normalizedJobId,
        normalizedProvider,
        normalizedModel,
        estimatedCredits,
        'AI authorization requires a job ID and provider.',
        timestamp,
      );
    }
    if (!policy.allowGeneration) {
      return _denied(
        normalizedJobId,
        normalizedProvider,
        normalizedModel,
        estimatedCredits,
        'Workspace AI generation is disabled.',
        timestamp,
      );
    }
    if (!estimatedCredits.isFinite || estimatedCredits <= 0) {
      return _denied(
        normalizedJobId,
        normalizedProvider,
        normalizedModel,
        estimatedCredits,
        'AI authorization credit estimate is invalid.',
        timestamp,
      );
    }
    if (estimatedCredits > policy.maxCreditsPerJob) {
      return _denied(
        normalizedJobId,
        normalizedProvider,
        normalizedModel,
        estimatedCredits,
        'AI job exceeds the workspace per-job credit limit.',
        timestamp,
      );
    }

    final workspaceQuota =
        quota['workspace'] ??
        AIQuotaSnapshot(
          scope: 'workspace',
          used: 0,
          limit: policy.quotaCredits,
          unit: 'credits',
        );
    if (quota['workspace'] == null) quota = quota.withSnapshot(workspaceQuota);
    if (!workspaceQuota.allows(estimatedCredits)) {
      return _denied(
        normalizedJobId,
        normalizedProvider,
        normalizedModel,
        estimatedCredits,
        'Workspace AI quota exceeded.',
        timestamp,
      );
    }

    final candidates = <String>[
      normalizedProvider,
      ...policy.fallbackProviders,
    ];
    final seen = <String>{};
    String? selectedProvider;
    AIProviderPolicy? selectedPolicy;
    Duration? retryAfter;
    for (final candidate in candidates) {
      final candidateId = candidate.trim();
      if (candidateId.isEmpty || !seen.add(candidateId)) continue;
      final candidatePolicy = policy.providers[candidateId];
      if (candidatePolicy == null && !policy.allowUnknownProviders) continue;
      if (candidatePolicy != null && !candidatePolicy.enabled) continue;
      if (candidatePolicy != null &&
          !candidatePolicy.allowsModel(normalizedModel)) {
        continue;
      }
      final candidateHealth = health[candidateId];
      if (candidateHealth?.status == AIProviderStatus.unavailable) continue;
      if (candidatePolicy != null &&
          candidateHealth != null &&
          !candidateHealth.canStartJob) {
        continue;
      }
      if (candidateHealth?.status == AIProviderStatus.experimental &&
          candidatePolicy?.allowExperimental != true) {
        continue;
      }
      final candidateLimit =
          candidatePolicy?.maxCreditsPerJob ?? policy.maxCreditsPerJob;
      if (estimatedCredits > candidateLimit) continue;
      final window = candidatePolicy?.rateLimitWindow ?? policy.rateLimitWindow;
      final limit = candidatePolicy?.rateLimitCount ?? policy.rateLimitCount;
      final requests = _requestTimes.putIfAbsent(candidateId, () => []);
      requests.removeWhere((entry) => !entry.add(window).isAfter(timestamp));
      if (requests.length >= limit) {
        final oldest = requests.isEmpty ? timestamp : requests.first;
        final candidateRetry = oldest.add(window).difference(timestamp);
        if (retryAfter == null || candidateRetry > retryAfter) {
          retryAfter = candidateRetry;
        }
        continue;
      }
      selectedProvider = candidateId;
      selectedPolicy = candidatePolicy;
      break;
    }
    if (selectedProvider == null) {
      return _denied(
        normalizedJobId,
        normalizedProvider,
        normalizedModel,
        estimatedCredits,
        retryAfter == null
            ? 'No allowed and healthy AI provider is available.'
            : 'AI provider rate limit exceeded.',
        timestamp,
        retryAfter: retryAfter,
      );
    }

    final nextUsed = workspaceQuota.used + estimatedCredits;
    final budgetAlert =
        workspaceQuota.limit > 0 &&
        nextUsed / workspaceQuota.limit >= policy.budgetAlertThreshold;
    quota = quota.recordSpend('workspace', estimatedCredits);
    _requestTimes[selectedProvider]!.add(timestamp);
    final decision = AIAuthorizationDecision(
      status: AIAuthorizationStatus.allowed,
      jobId: normalizedJobId,
      provider: selectedProvider,
      model: normalizedModel,
      estimatedCredits: estimatedCredits,
      usedFallback: selectedProvider != normalizedProvider,
      budgetAlert: budgetAlert,
      remainingCredits: (workspaceQuota.limit - nextUsed)
          .clamp(0, workspaceQuota.limit)
          .toDouble(),
      authorizedAt: timestamp,
      message: selectedPolicy == null
          ? null
          : 'AI provider policy accepted the request.',
    );
    _authorizations[normalizedJobId] = _AIAuthorizationRecord(
      decision,
      timestamp,
    );
    return decision;
  }

  void release(String jobId) {
    final record = _authorizations.remove(jobId.trim());
    if (record == null) return;
    quota = quota.releaseSpend('workspace', record.decision.estimatedCredits);
    final requests = _requestTimes[record.decision.provider];
    requests?.remove(record.requestedAt);
  }

  void reportProviderResult({
    required String provider,
    required bool success,
    Duration? latency,
    String? message,
    DateTime? checkedAt,
  }) {
    final previous = health[provider];
    final status = success
        ? AIProviderStatus.healthy
        : previous?.status == AIProviderStatus.unavailable
        ? AIProviderStatus.unavailable
        : AIProviderStatus.degraded;
    health = health.update(
      AIProviderHealth(
        provider: provider,
        status: status,
        checkedAt: (checkedAt ?? DateTime.now()).toUtc(),
        latency: latency,
        message: message,
      ),
    );
  }

  Map<String, dynamic> provenanceFor(AIJob job) => {
    'governance': {
      'policyVersion': 1,
      'provider': job.provider,
      'model': job.model,
      'estimatedCredits': job.estimatedCost,
      'retentionDays': policy.retention.jobRetention.inDays,
      'promptRetained': policy.retention.retainPrompt,
      'inputArtifactsRetained': policy.retention.retainInputArtifacts,
      'outputArtifactsRetained': policy.retention.retainOutputArtifacts,
    },
  };

  Map<String, dynamic> exportProvenance(AIJob job, {DateTime? exportedAt}) {
    if (!policy.retention.allowProvenanceExport) {
      throw StateError('Workspace provenance export is disabled.');
    }
    final safeJob = redactAIJobJson(
      job,
      redactPrompt: !policy.retention.retainPrompt,
      retainInputArtifacts: policy.retention.retainInputArtifacts,
      retainOutputArtifacts: policy.retention.retainOutputArtifacts,
    );
    return {
      'schemaVersion': 1,
      'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'jobId': job.id,
      'projectId': job.projectId,
      'capability': job.capability.name,
      'provider': job.provider,
      'model': job.model,
      'sourceAssetIds': job.sourceAssetIds,
      'sourceNodeIds': job.sourceNodeIds,
      'job': safeJob,
      'provenance': _sanitizeMap(job.provenance),
    };
  }

  AIAuthorizationDecision _denied(
    String jobId,
    String provider,
    String? model,
    double credits,
    String message,
    DateTime timestamp, {
    Duration? retryAfter,
  }) => AIAuthorizationDecision(
    status: AIAuthorizationStatus.denied,
    jobId: jobId,
    provider: provider,
    model: model,
    estimatedCredits: credits,
    usedFallback: false,
    budgetAlert: false,
    remainingCredits: quota['workspace']?.remaining ?? policy.quotaCredits,
    retryAfter: retryAfter,
    message: message,
    authorizedAt: timestamp,
  );
}

Map<String, dynamic> redactAIJobJson(
  AIJob job, {
  bool redactPrompt = false,
  bool retainInputArtifacts = false,
  bool retainOutputArtifacts = true,
}) {
  // AIJob.toPersistenceJson() is the mandatory boundary. The retention
  // switches only further reduce already-safe metadata; they never restore
  // runtime paths, provider URLs, signed delivery URLs, or source bytes.
  final data = _sanitizeMap(job.toPersistenceJson());
  if (redactPrompt) data['prompt'] = '[redacted by workspace policy]';
  final params = data['creativeParams'];
  if (params is Map) {
    if (!retainInputArtifacts) {
      params.remove('maskPayload');
    }
    data['creativeParams'] = params;
  }
  if (!retainOutputArtifacts) data.remove('resultArtifact');
  return data;
}

Map<String, dynamic> _sanitizeMap(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  for (final entry in source.entries) {
    final key = entry.key;
    final lowerKey = key.toLowerCase();
    if (lowerKey.contains('base64') ||
        lowerKey.contains('secret') ||
        lowerKey.contains('token') ||
        lowerKey.contains('password') ||
        lowerKey.contains('api_key') ||
        lowerKey.contains('apikey') ||
        lowerKey == 'authorization') {
      continue;
    }
    result[key] = _sanitizeValue(entry.value);
  }
  return result;
}

Object? _sanitizeValue(Object? value) {
  if (value is Map) return _sanitizeMap(Map<String, dynamic>.from(value));
  if (value is List) return value.map(_sanitizeValue).toList(growable: false);
  if (value is String && value.toLowerCase().startsWith('data:')) {
    return '[redacted data URI]';
  }
  return value;
}
