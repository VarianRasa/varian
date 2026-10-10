import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/ai/domain/ai_evaluation.dart';

void main() {
  test(
    'passes deterministic prompt, mask, seed, schema, latency, cost, safety, and acceptance checks',
    () {
      const fixture = AIEvaluationFixture(
        id: 'fixture-1',
        capability: 'inpainting',
        expectedPrompt: 'remove the chair',
        expectedMask: {'width': 100, 'height': 80, 'operation': 'removeObject'},
        expectedSeed: 42,
        requiredOutputKeys: {'artifactUrl', 'provider'},
        maxLatency: Duration(seconds: 2),
        maxCost: 3,
        requireHumanAcceptance: true,
      );
      const observation = AIEvaluationObservation(
        fixtureId: 'fixture-1',
        capability: 'inpainting',
        prompt: 'remove the chair',
        mask: {'operation': 'removeObject', 'height': 80, 'width': 100},
        seed: 42,
        output: {
          'artifactUrl': 'https://example.test/a.png',
          'provider': 'test',
        },
        latency: Duration(milliseconds: 900),
        cost: 2,
        safetyPassed: true,
        humanAccepted: true,
      );

      final report = const AIEvaluationHarness().evaluate(
        [fixture],
        [observation],
        evaluatedAt: DateTime.utc(2026, 9, 13),
      );

      expect(report.passed, isTrue);
      expect(report.passedCount, 1);
      expect(report.failedCount, 0);
      expect(report.results.single.failures, isEmpty);
    },
  );

  test('reports deterministic failures instead of throwing', () {
    const fixture = AIEvaluationFixture(
      id: 'fixture-2',
      capability: 'textToImage',
      expectedPrompt: 'approved prompt',
      expectedSeed: 7,
      requiredOutputKeys: {'artifactUrl'},
      maxLatency: Duration(seconds: 1),
      maxCost: 1,
    );
    const observation = AIEvaluationObservation(
      fixtureId: 'fixture-2',
      capability: 'textToImage',
      prompt: 'changed prompt',
      seed: 8,
      output: {},
      latency: Duration(seconds: 2),
      cost: 2,
      safetyPassed: false,
    );

    final result = const AIEvaluationHarness().evaluateFixture(
      fixture,
      observation,
    );

    expect(result.passed, isFalse);
    expect(
      result.failures.map((check) => check.name),
      containsAll([
        'prompt',
        'seed',
        'outputSchema',
        'latency',
        'cost',
        'safety',
      ]),
    );
  });

  test(
    'keeps the first observation for a fixture to avoid nondeterministic overwrite',
    () {
      const fixture = AIEvaluationFixture(
        id: 'fixture-3',
        capability: 'textToImage',
        expectedPrompt: 'first',
        expectedSeed: 1,
      );
      const first = AIEvaluationObservation(
        fixtureId: 'fixture-3',
        capability: 'textToImage',
        prompt: 'first',
        seed: 1,
        output: {},
        latency: Duration.zero,
        cost: 0,
        safetyPassed: true,
      );
      const second = AIEvaluationObservation(
        fixtureId: 'fixture-3',
        capability: 'textToImage',
        prompt: 'second',
        seed: 2,
        output: {},
        latency: Duration(seconds: 99),
        cost: 99,
        safetyPassed: false,
      );

      final result = const AIEvaluationHarness()
          .evaluate([fixture], [first, second])
          .results
          .single;

      expect(result.passed, isTrue);
    },
  );
}
