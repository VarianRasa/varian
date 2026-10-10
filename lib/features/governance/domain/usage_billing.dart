enum UsageMetric {
  storageBytes,
  transferBytes,
  aiCredits,
  renderSeconds,
  seats,
}

enum OveragePolicy { block, grace, allow }

enum EntitlementStatus { active, trialing, pastDue, canceled, paused }

String _entitlementStatusToWire(EntitlementStatus status) => switch (status) {
  EntitlementStatus.active => 'active',
  EntitlementStatus.trialing => 'trialing',
  EntitlementStatus.pastDue => 'past_due',
  EntitlementStatus.canceled => 'canceled',
  EntitlementStatus.paused => 'paused',
};

EntitlementStatus _entitlementStatusFromWire(Object? raw) => switch (raw) {
  'trialing' => EntitlementStatus.trialing,
  'past_due' || 'past-due' => EntitlementStatus.pastDue,
  'canceled' || 'cancelled' => EntitlementStatus.canceled,
  'paused' => EntitlementStatus.paused,
  _ => EntitlementStatus.active,
};

class UsageLedgerEntry {
  final String id;
  final String workspaceId;
  final UsageMetric metric;
  final int delta;
  final String idempotencyKey;
  final String? correlationId;
  final DateTime recordedAt;
  final Map<String, dynamic> metadata;

  const UsageLedgerEntry({
    required this.id,
    required this.workspaceId,
    required this.metric,
    required this.delta,
    required this.idempotencyKey,
    required this.recordedAt,
    this.correlationId,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'workspaceId': workspaceId,
    'metric': metric.name,
    'delta': delta,
    'idempotencyKey': idempotencyKey,
    'correlationId': correlationId,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'metadata': metadata,
  };

  factory UsageLedgerEntry.fromJson(Map<String, dynamic> json) =>
      UsageLedgerEntry(
        id: json['id']?.toString() ?? '',
        workspaceId: json['workspaceId']?.toString() ?? '',
        metric: UsageMetric.values.firstWhere(
          (value) => value.name == json['metric'],
          orElse: () => UsageMetric.storageBytes,
        ),
        delta: (json['delta'] as num?)?.toInt() ?? 0,
        idempotencyKey: json['idempotencyKey']?.toString() ?? '',
        correlationId: json['correlationId']?.toString(),
        recordedAt:
            DateTime.tryParse(json['recordedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const {},
      );
}

class UsageLedgerRecordResult {
  final UsageLedgerEntry entry;
  final bool inserted;

  const UsageLedgerRecordResult({required this.entry, required this.inserted});
}

class UsageLedger {
  final List<UsageLedgerEntry> _entries;

  UsageLedger({Iterable<UsageLedgerEntry> entries = const []})
    : _entries = List<UsageLedgerEntry>.from(entries);

  List<UsageLedgerEntry> get entries => List.unmodifiable(_entries);

  UsageLedgerRecordResult record(UsageLedgerEntry entry) {
    if (entry.workspaceId.trim().isEmpty ||
        entry.idempotencyKey.trim().isEmpty) {
      throw ArgumentError('Workspace ID and idempotency key are required.');
    }
    final existing = _entries.where((item) {
      return item.workspaceId == entry.workspaceId &&
          item.idempotencyKey == entry.idempotencyKey;
    }).firstOrNull;
    if (existing != null) {
      return UsageLedgerRecordResult(entry: existing, inserted: false);
    }
    _entries.add(entry);
    return UsageLedgerRecordResult(entry: entry, inserted: true);
  }

  int total(String workspaceId, UsageMetric metric) => _entries
      .where(
        (entry) => entry.workspaceId == workspaceId && entry.metric == metric,
      )
      .fold(0, (total, entry) => total + entry.delta);

  Map<String, int> totals(String workspaceId) => {
    for (final metric in UsageMetric.values)
      metric.name: total(workspaceId, metric),
  };

  Map<String, dynamic> toJson() => {
    'entries': _entries.map((entry) => entry.toJson()).toList(growable: false),
  };

  factory UsageLedger.fromJson(Object? raw) {
    if (raw is! Map || raw['entries'] is! List) return UsageLedger();
    return UsageLedger(
      entries: (raw['entries'] as List<dynamic>).whereType<Map>().map(
        (entry) => UsageLedgerEntry.fromJson(Map<String, dynamic>.from(entry)),
      ),
    );
  }
}

class BillingPlan {
  final String id;
  final String displayName;
  final Map<UsageMetric, int> limits;
  final OveragePolicy overagePolicy;
  final Duration gracePeriod;

  const BillingPlan({
    required this.id,
    required this.displayName,
    this.limits = const {},
    this.overagePolicy = OveragePolicy.block,
    this.gracePeriod = Duration.zero,
  });

  int limitFor(UsageMetric metric) => limits[metric] ?? 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'limits': {for (final entry in limits.entries) entry.key.name: entry.value},
    'overagePolicy': overagePolicy.name,
    'gracePeriodSeconds': gracePeriod.inSeconds,
  };
}

class EntitlementSnapshot {
  final String planId;
  final int revision;
  final Map<UsageMetric, int> limits;
  final OveragePolicy overagePolicy;
  final DateTime fetchedAt;
  final DateTime? graceUntil;
  final EntitlementStatus status;
  final String provider;
  final String? externalCustomerId;
  final String? externalSubscriptionId;
  final DateTime? updatedAt;

  const EntitlementSnapshot({
    required this.planId,
    required this.revision,
    required this.limits,
    required this.overagePolicy,
    required this.fetchedAt,
    this.graceUntil,
    this.status = EntitlementStatus.active,
    this.provider = 'manual',
    this.externalCustomerId,
    this.externalSubscriptionId,
    this.updatedAt,
  });

  int limitFor(UsageMetric metric) => limits[metric] ?? 0;

  Map<String, dynamic> toJson() => {
    'planId': planId,
    'revision': revision,
    'limits': {for (final entry in limits.entries) entry.key.name: entry.value},
    'overagePolicy': overagePolicy.name,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'graceUntil': graceUntil?.toUtc().toIso8601String(),
    'status': _entitlementStatusToWire(status),
    'provider': provider,
    'externalCustomerId': externalCustomerId,
    'externalSubscriptionId': externalSubscriptionId,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };

  factory EntitlementSnapshot.fromJson(Map<String, dynamic> json) {
    final rawLimits = json['limits'];
    final limits = <UsageMetric, int>{};
    if (rawLimits is Map) {
      for (final metric in UsageMetric.values) {
        final value = rawLimits[metric.name];
        if (value is num) limits[metric] = value.toInt();
      }
    }
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    return EntitlementSnapshot(
      planId: json['planId']?.toString() ?? '',
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      limits: limits,
      overagePolicy: OveragePolicy.values.firstWhere(
        (value) => value.name == json['overagePolicy'],
        orElse: () => OveragePolicy.block,
      ),
      fetchedAt:
          DateTime.tryParse(json['fetchedAt']?.toString() ?? '') ??
          updatedAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      graceUntil: DateTime.tryParse(json['graceUntil']?.toString() ?? ''),
      status: _entitlementStatusFromWire(json['status']),
      provider: json['provider']?.toString() ?? 'manual',
      externalCustomerId: json['externalCustomerId']?.toString(),
      externalSubscriptionId: json['externalSubscriptionId']?.toString(),
      updatedAt: updatedAt,
    );
  }
}

class UsageDecision {
  final bool allowed;
  final bool overage;
  final String reason;

  const UsageDecision({
    required this.allowed,
    required this.reason,
    this.overage = false,
  });
}

class UsageGate {
  UsageGate._();

  static UsageDecision evaluate({
    required EntitlementSnapshot entitlement,
    required UsageMetric metric,
    required int currentUsage,
    required int requestedDelta,
    required DateTime now,
  }) {
    if (requestedDelta < 0) {
      return const UsageDecision(
        allowed: false,
        reason: 'Requested usage delta cannot be negative.',
      );
    }
    final nextUsage = currentUsage + requestedDelta;
    if (nextUsage <= entitlement.limitFor(metric)) {
      return const UsageDecision(
        allowed: true,
        reason: 'Usage is within plan limit.',
      );
    }
    if (entitlement.overagePolicy == OveragePolicy.allow) {
      return const UsageDecision(
        allowed: true,
        overage: true,
        reason: 'Usage is allowed and recorded as overage.',
      );
    }
    if (entitlement.overagePolicy == OveragePolicy.grace &&
        entitlement.graceUntil?.isAfter(now.toUtc()) == true) {
      return const UsageDecision(
        allowed: true,
        overage: true,
        reason: 'Usage is allowed during the active grace period.',
      );
    }
    return const UsageDecision(
      allowed: false,
      overage: true,
      reason: 'Usage exceeds the plan limit.',
    );
  }
}

class EntitlementCache {
  final Duration maxStale;
  EntitlementSnapshot? _snapshot;

  EntitlementCache({this.maxStale = const Duration(hours: 24)});

  EntitlementSnapshot? get snapshot => _snapshot;

  bool get hasValue => _snapshot != null;

  bool isUsableAt(DateTime now) {
    final snapshot = _snapshot;
    return snapshot != null &&
        now.toUtc().difference(snapshot.fetchedAt.toUtc()) <= maxStale;
  }

  void update(EntitlementSnapshot snapshot) {
    if (_snapshot != null && snapshot.revision < _snapshot!.revision) return;
    _snapshot = snapshot;
  }

  Map<String, dynamic> toJson() => {
    'maxStaleSeconds': maxStale.inSeconds,
    'snapshot': _snapshot?.toJson(),
  };

  factory EntitlementCache.fromJson(Object? raw) {
    if (raw is! Map) return EntitlementCache();
    final cache = EntitlementCache(
      maxStale: Duration(
        seconds: (raw['maxStaleSeconds'] as num?)?.toInt() ?? 86400,
      ),
    );
    if (raw['snapshot'] is Map) {
      cache.update(
        EntitlementSnapshot.fromJson(
          Map<String, dynamic>.from(raw['snapshot'] as Map),
        ),
      );
    }
    return cache;
  }
}

class BillingWebhookEvent {
  final String eventId;
  final String type;
  final String idempotencyKey;
  final DateTime receivedAt;
  final Map<String, dynamic> payload;

  const BillingWebhookEvent({
    required this.eventId,
    required this.type,
    required this.idempotencyKey,
    required this.receivedAt,
    this.payload = const {},
  });
}

class BillingWebhookDeduper {
  final Set<String> _processedKeys = {};

  bool accept(BillingWebhookEvent event) {
    if (event.idempotencyKey.trim().isEmpty) return false;
    return _processedKeys.add(event.idempotencyKey);
  }

  bool get isEmpty => _processedKeys.isEmpty;
}

class InvoiceMetadata {
  final String invoiceId;
  final String workspaceId;
  final String planId;
  final String currency;
  final int amountMinor;
  final DateTime issuedAt;
  final Map<String, String> customFields;

  const InvoiceMetadata({
    required this.invoiceId,
    required this.workspaceId,
    required this.planId,
    required this.currency,
    required this.amountMinor,
    required this.issuedAt,
    this.customFields = const {},
  });

  Map<String, dynamic> toJson() => {
    'invoiceId': invoiceId,
    'workspaceId': workspaceId,
    'planId': planId,
    'currency': currency,
    'amountMinor': amountMinor,
    'issuedAt': issuedAt.toUtc().toIso8601String(),
    'customFields': customFields,
  };
}
