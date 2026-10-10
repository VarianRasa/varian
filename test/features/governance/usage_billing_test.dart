import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/governance/domain/usage_billing.dart';

void main() {
  final now = DateTime.utc(2026, 9, 13);

  test('usage ledger is idempotent and totals corrections', () {
    final ledger = UsageLedger();
    final entry = UsageLedgerEntry(
      id: 'usage-1',
      workspaceId: 'workspace-1',
      metric: UsageMetric.aiCredits,
      delta: 5,
      idempotencyKey: 'job-1',
      recordedAt: now,
    );

    expect(ledger.record(entry).inserted, isTrue);
    expect(ledger.record(entry).inserted, isFalse);
    expect(
      ledger
          .record(
            UsageLedgerEntry(
              id: 'usage-2',
              workspaceId: 'workspace-1',
              metric: UsageMetric.aiCredits,
              delta: -1,
              idempotencyKey: 'correction-1',
              recordedAt: now,
            ),
          )
          .inserted,
      isTrue,
    );
    expect(ledger.total('workspace-1', UsageMetric.aiCredits), 4);
  });

  test('usage gate enforces block, grace, and allow policies', () {
    EntitlementSnapshot snapshot(
      OveragePolicy policy, {
      DateTime? graceUntil,
    }) => EntitlementSnapshot(
      planId: 'team',
      revision: 1,
      limits: const {UsageMetric.renderSeconds: 10},
      overagePolicy: policy,
      fetchedAt: now,
      graceUntil: graceUntil,
    );

    expect(
      UsageGate.evaluate(
        entitlement: snapshot(OveragePolicy.block),
        metric: UsageMetric.renderSeconds,
        currentUsage: 9,
        requestedDelta: 2,
        now: now,
      ).allowed,
      isFalse,
    );
    expect(
      UsageGate.evaluate(
        entitlement: snapshot(
          OveragePolicy.grace,
          graceUntil: now.add(const Duration(hours: 1)),
        ),
        metric: UsageMetric.renderSeconds,
        currentUsage: 9,
        requestedDelta: 2,
        now: now,
      ).allowed,
      isTrue,
    );
    expect(
      UsageGate.evaluate(
        entitlement: snapshot(OveragePolicy.allow),
        metric: UsageMetric.renderSeconds,
        currentUsage: 9,
        requestedDelta: 2,
        now: now,
      ).overage,
      isTrue,
    );
  });

  test(
    'entitlement cache rejects stale revisions and persists offline value',
    () {
      final cache = EntitlementCache(maxStale: const Duration(hours: 2));
      cache.update(
        EntitlementSnapshot(
          planId: 'team',
          revision: 2,
          limits: const {UsageMetric.seats: 5},
          overagePolicy: OveragePolicy.block,
          fetchedAt: now,
        ),
      );
      cache.update(
        EntitlementSnapshot(
          planId: 'old',
          revision: 1,
          limits: const {UsageMetric.seats: 1},
          overagePolicy: OveragePolicy.block,
          fetchedAt: now,
        ),
      );
      final restored = EntitlementCache.fromJson(cache.toJson());

      expect(restored.snapshot!.planId, 'team');
      expect(restored.snapshot!.limitFor(UsageMetric.seats), 5);
      expect(restored.isUsableAt(now.add(const Duration(hours: 1))), isTrue);
      expect(restored.isUsableAt(now.add(const Duration(hours: 3))), isFalse);
    },
  );

  test(
    'entitlement snapshot preserves provider status and external billing IDs',
    () {
      final snapshot = EntitlementSnapshot.fromJson({
        'planId': 'pro',
        'revision': 4,
        'limits': {'seats': 3},
        'overagePolicy': 'grace',
        'status': 'past_due',
        'provider': 'stripe',
        'externalCustomerId': 'cus_1',
        'externalSubscriptionId': 'sub_1',
        'updatedAt': '2026-09-14T00:00:00Z',
      });

      expect(snapshot.status, EntitlementStatus.pastDue);
      expect(snapshot.provider, 'stripe');
      expect(snapshot.externalCustomerId, 'cus_1');
      expect(snapshot.externalSubscriptionId, 'sub_1');
      expect(snapshot.fetchedAt, DateTime.utc(2026, 9, 14));
      expect(snapshot.toJson()['status'], 'past_due');
    },
  );

  test('billing webhook deduper accepts each idempotency key once', () {
    final deduper = BillingWebhookDeduper();
    final event = BillingWebhookEvent(
      eventId: 'evt-1',
      type: 'invoice.paid',
      idempotencyKey: 'invoice-1',
      receivedAt: now,
    );

    expect(deduper.accept(event), isTrue);
    expect(deduper.accept(event), isFalse);
    expect(
      deduper.accept(
        BillingWebhookEvent(
          eventId: 'evt-empty',
          type: 'invoice.paid',
          idempotencyKey: '',
          receivedAt: now,
        ),
      ),
      isFalse,
    );
  });
}
