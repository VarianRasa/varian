import 'ai_workflow_contract.dart';

class AIProviderHealthRegistry {
  final Map<String, AIProviderHealth> providers;

  const AIProviderHealthRegistry({this.providers = const {}});

  AIProviderHealth? operator [](String provider) => providers[provider];

  bool canStart(String provider) => providers[provider]?.canStartJob ?? false;

  AIProviderHealthRegistry update(AIProviderHealth health) =>
      AIProviderHealthRegistry(
        providers: {...providers, health.provider: health},
      );

  AIProviderHealthRegistry remove(String provider) {
    if (!providers.containsKey(provider)) return this;
    final next = {...providers}..remove(provider);
    return AIProviderHealthRegistry(providers: next);
  }

  Map<String, dynamic> toJson() => {
    for (final entry in providers.entries)
      entry.key: {
        'provider': entry.value.provider,
        'status': entry.value.status.name,
        'checkedAt': entry.value.checkedAt.toUtc().toIso8601String(),
        'message': entry.value.message,
        'latencyMs': entry.value.latency?.inMilliseconds,
      },
  };

  factory AIProviderHealthRegistry.fromJson(Object? raw) {
    if (raw is! Map) return const AIProviderHealthRegistry();
    final providers = <String, AIProviderHealth>{};
    for (final item in raw.entries) {
      if (item.value is! Map) continue;
      final data = Map<String, dynamic>.from(item.value as Map);
      final provider = (data['provider'] ?? item.key).toString().trim();
      final checkedAt = DateTime.tryParse(data['checkedAt']?.toString() ?? '');
      if (provider.isEmpty || checkedAt == null) continue;
      final status = AIProviderStatus.values.firstWhere(
        (value) => value.name == data['status'],
        orElse: () => AIProviderStatus.unavailable,
      );
      providers[provider] = AIProviderHealth(
        provider: provider,
        status: status,
        checkedAt: checkedAt,
        message: data['message'] as String?,
        latency: (data['latencyMs'] as num?) == null
            ? null
            : Duration(milliseconds: (data['latencyMs'] as num).toInt()),
      );
    }
    return AIProviderHealthRegistry(providers: providers);
  }
}

class AIQuotaLedger {
  final Map<String, AIQuotaSnapshot> snapshots;

  const AIQuotaLedger({this.snapshots = const {}});

  AIQuotaSnapshot? operator [](String scope) => snapshots[scope];

  AIQuotaLedger withSnapshot(AIQuotaSnapshot snapshot) =>
      AIQuotaLedger(snapshots: {...snapshots, snapshot.scope: snapshot});

  bool canSpend(String scope, double amount) =>
      snapshots[scope]?.allows(amount) ?? false;

  AIQuotaLedger recordSpend(String scope, double amount) {
    final snapshot = snapshots[scope];
    if (snapshot == null || !amount.isFinite || !snapshot.allows(amount)) {
      return this;
    }
    return AIQuotaLedger(
      snapshots: {
        ...snapshots,
        scope: AIQuotaSnapshot(
          scope: snapshot.scope,
          used: snapshot.used + amount,
          limit: snapshot.limit,
          unit: snapshot.unit,
          resetsAt: snapshot.resetsAt,
        ),
      },
    );
  }

  AIQuotaLedger releaseSpend(String scope, double amount) {
    final snapshot = snapshots[scope];
    if (snapshot == null || !amount.isFinite || amount < 0) return this;
    return AIQuotaLedger(
      snapshots: {
        ...snapshots,
        scope: AIQuotaSnapshot(
          scope: snapshot.scope,
          used: (snapshot.used - amount).clamp(0, snapshot.limit).toDouble(),
          limit: snapshot.limit,
          unit: snapshot.unit,
          resetsAt: snapshot.resetsAt,
        ),
      },
    );
  }

  Map<String, dynamic> toJson() => {
    for (final entry in snapshots.entries)
      entry.key: {
        'scope': entry.value.scope,
        'used': entry.value.used,
        'limit': entry.value.limit,
        'unit': entry.value.unit,
        'resetsAt': entry.value.resetsAt?.toUtc().toIso8601String(),
      },
  };

  factory AIQuotaLedger.fromJson(Object? raw) {
    if (raw is! Map) return const AIQuotaLedger();
    final snapshots = <String, AIQuotaSnapshot>{};
    for (final item in raw.entries) {
      if (item.value is! Map) continue;
      final data = Map<String, dynamic>.from(item.value as Map);
      final scope = (data['scope'] ?? item.key).toString().trim();
      final used = (data['used'] as num?)?.toDouble();
      final limit = (data['limit'] as num?)?.toDouble();
      final unit = data['unit']?.toString().trim();
      if (scope.isEmpty || used == null || limit == null || unit == null) {
        continue;
      }
      snapshots[scope] = AIQuotaSnapshot(
        scope: scope,
        used: used,
        limit: limit,
        unit: unit,
        resetsAt: DateTime.tryParse(data['resetsAt']?.toString() ?? ''),
      );
    }
    return AIQuotaLedger(snapshots: snapshots);
  }
}
