import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/features/ai/data/ai_service.dart';
import 'package:varian/features/ai/domain/ai_governance.dart';
import 'package:varian/features/ai/domain/ai_provider_executor.dart';
import 'package:varian/features/ai/domain/ai_provider_health.dart';
import 'package:varian/features/ai/domain/ai_workflow_contract.dart';
import 'package:varian/data/remote/backend_config.dart';

AIJob _job({String id = 'job-governance-1', String prompt = 'private prompt'}) {
  final now = DateTime.utc(2026, 9, 13);
  return AIJob(
    id: id,
    projectId: 'project-1',
    capability: AICapability.textToImage,
    prompt: prompt,
    creativeParams: const AICreativeParams(
      sourceImageBase64: 'data:image/png;base64,secret-image',
      maskImageBase64: 'data:image/png;base64,secret-mask',
      sourceImageUrl: 'https://example.test/source.png',
      extraConfig: {'apiToken': 'secret-token'},
    ),
    provider: 'primary',
    model: 'safe-model',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('allows an allowlisted model and raises a budget alert', () {
    final runtime = AIGovernanceRuntime(
      policy: const AIGovernancePolicy(
        allowUnknownProviders: false,
        providers: {
          'primary': AIProviderPolicy(
            provider: 'primary',
            allowedModels: {'safe-model'},
          ),
        },
        quotaCredits: 10,
        budgetAlertThreshold: 0.8,
      ),
    );

    final decision = runtime.authorize(
      jobId: 'job-governance-1',
      provider: 'primary',
      model: 'safe-model',
      estimatedCredits: 8,
      now: DateTime.utc(2026, 9, 13),
    );

    expect(decision.status, AIAuthorizationStatus.allowed);
    expect(decision.budgetAlert, isTrue);
    expect(runtime.quota['workspace']?.used, 8);
  });

  test('denies a model outside the provider allowlist', () {
    final runtime = AIGovernanceRuntime(
      policy: const AIGovernancePolicy(
        allowUnknownProviders: false,
        providers: {
          'primary': AIProviderPolicy(
            provider: 'primary',
            allowedModels: {'safe-model'},
          ),
        },
      ),
    );

    final decision = runtime.authorize(
      jobId: 'job-governance-2',
      provider: 'primary',
      model: 'unapproved-model',
      estimatedCredits: 1,
    );

    expect(decision.status, AIAuthorizationStatus.denied);
    expect(decision.message, contains('provider'));
  });

  test('uses a healthy fallback provider when primary is unavailable', () {
    final health = const AIProviderHealthRegistry().update(
      AIProviderHealth(
        provider: 'primary',
        status: AIProviderStatus.unavailable,
        checkedAt: DateTime.utc(2026, 9, 13),
      ),
    );
    final runtime = AIGovernanceRuntime(
      health: health,
      policy: const AIGovernancePolicy(
        allowUnknownProviders: false,
        providers: {
          'primary': AIProviderPolicy(
            provider: 'primary',
            allowedModels: {'safe-model'},
          ),
          'backup': AIProviderPolicy(
            provider: 'backup',
            allowedModels: {'safe-model'},
          ),
        },
        fallbackProviders: ['backup'],
      ),
    );

    final decision = runtime.authorize(
      jobId: 'job-governance-3',
      provider: 'primary',
      model: 'safe-model',
      estimatedCredits: 1,
    );

    expect(decision.status, AIAuthorizationStatus.allowed);
    expect(decision.provider, 'backup');
    expect(decision.usedFallback, isTrue);
  });

  test('prevents duplicate authorization and enforces rate limits', () {
    final runtime = AIGovernanceRuntime(
      policy: const AIGovernancePolicy(
        rateLimitCount: 1,
        rateLimitWindow: Duration(minutes: 1),
      ),
    );
    final start = DateTime.utc(2026, 9, 13);

    final first = runtime.authorize(
      jobId: 'job-governance-4',
      provider: 'primary',
      estimatedCredits: 1,
      now: start,
    );
    final duplicate = runtime.authorize(
      jobId: 'job-governance-4',
      provider: 'primary',
      estimatedCredits: 1,
      now: start,
    );
    final limited = runtime.authorize(
      jobId: 'job-governance-5',
      provider: 'primary',
      estimatedCredits: 1,
      now: start,
    );

    expect(first.status, AIAuthorizationStatus.allowed);
    expect(duplicate.status, AIAuthorizationStatus.duplicate);
    expect(limited.status, AIAuthorizationStatus.denied);
    expect(limited.retryAfter, isNotNull);
  });

  test('redacts sensitive input data and supports provenance export', () {
    final runtime = AIGovernanceRuntime(
      policy: const AIGovernancePolicy(
        retention: AIDataRetentionPolicy(
          retainPrompt: false,
          retainInputArtifacts: false,
          allowProvenanceExport: true,
        ),
      ),
    );
    final job = _job();
    final redacted = redactAIJobJson(job);
    final params = redacted['creativeParams'] as Map<String, dynamic>;

    expect(redacted['prompt'], 'private prompt');
    expect(params.containsKey('sourceImageBase64'), isFalse);
    expect(params.containsKey('maskImageBase64'), isFalse);
    expect(params.containsKey('sourceImageUrl'), isFalse);
    expect(params['extraConfig'], isA<Map>());
    expect(
      (params['extraConfig'] as Map<String, dynamic>).containsKey('apiToken'),
      isFalse,
    );

    final export = runtime.exportProvenance(job);
    expect(export['schemaVersion'], 1);
    expect(
      (export['job'] as Map<String, dynamic>)['prompt'],
      '[redacted by workspace policy]',
    );
  });

  test('round-trips policy and ledgers without sensitive values', () {
    const policy = AIGovernancePolicy(
      allowGeneration: false,
      allowUnknownProviders: false,
      providers: {
        'primary': AIProviderPolicy(
          provider: 'primary',
          enabled: true,
          allowedModels: {'safe-model'},
        ),
      },
      fallbackProviders: ['backup'],
      quotaCredits: 42,
      maxCreditsPerJob: 7,
      rateLimitCount: 3,
      rateLimitWindow: Duration(seconds: 15),
    );
    final restored = AIGovernancePolicy.fromJson(policy.toJson());
    const ledger = AIQuotaLedger(
      snapshots: {
        'workspace': AIQuotaSnapshot(
          scope: 'workspace',
          used: 2,
          limit: 42,
          unit: 'credits',
        ),
      },
    );
    final restoredLedger = AIQuotaLedger.fromJson(ledger.toJson());

    expect(restored.allowGeneration, isFalse);
    expect(restored.providers['primary']?.allowedModels, {'safe-model'});
    expect(restored.rateLimitWindow, const Duration(seconds: 15));
    expect(restoredLedger['workspace']?.used, 2);
  });

  test('validates provider policy invariants before persistence', () {
    const policy = AIGovernancePolicy(
      quotaCredits: -1,
      budgetAlertThreshold: 1.5,
      maxCreditsPerJob: 0,
      rateLimitCount: 0,
      rateLimitWindow: Duration.zero,
      providers: {
        'primary': AIProviderPolicy(provider: 'backup', maxCreditsPerJob: 0),
      },
      fallbackProviders: ['backup', 'backup'],
    );

    final errors = policy.validate();

    expect(errors, isNotEmpty);
    expect(errors.join(' '), contains('quota'));
    expect(errors.join(' '), contains('Fallback providers'));
  });

  test('executes the provider selected by the fallback policy', () async {
    var executedProvider = '';
    final governance = AIGovernanceRuntime(
      policy: const AIGovernancePolicy(
        allowUnknownProviders: false,
        providers: {
          'primary': AIProviderPolicy(provider: 'primary', enabled: false),
          'backup': AIProviderPolicy(provider: 'backup'),
        },
        fallbackProviders: ['backup'],
      ),
    );
    final service = AIService(
      const BackendConfig(),
      null,
      false,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      governance,
      {
        'backup': CallbackAIProviderExecutor(
          provider: 'backup',
          callback: (job, _) async {
            executedProvider = job.provider ?? '';
            return job.copyWith(
              status: AIJobStatus.completed,
              resultText: 'handled by backup',
            );
          },
        ),
      },
    );
    final job = _job(id: 'job-fallback-executor');

    final result = await service.executeJob(job, const []);

    expect(result.status, AIJobStatus.completed);
    expect(result.provider, 'backup');
    expect(result.resultText, 'handled by backup');
    expect(executedProvider, 'backup');
  });
}
