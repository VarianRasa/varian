import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/ai/domain/ai_provider_health.dart';
import 'package:varian/features/ai/domain/ai_workflow_contract.dart';

void main() {
  test('provider health gates unavailable providers', () {
    final checkedAt = DateTime.utc(2026, 9, 11);
    final registry = const AIProviderHealthRegistry().update(
      AIProviderHealth(
        provider: 'local',
        status: AIProviderStatus.healthy,
        checkedAt: checkedAt,
      ),
    );

    expect(registry.canStart('local'), isTrue);
    expect(registry.canStart('missing'), isFalse);
  });

  test('quota ledger records only allowed spend', () {
    const ledger = AIQuotaLedger(
      snapshots: {
        'workspace': AIQuotaSnapshot(
          scope: 'workspace',
          used: 2,
          limit: 5,
          unit: 'credits',
        ),
      },
    );

    expect(ledger.canSpend('workspace', 3), isTrue);
    expect(ledger.recordSpend('workspace', 3)['workspace']?.used, 5);
    expect(ledger.recordSpend('workspace', 4), same(ledger));
  });
}
