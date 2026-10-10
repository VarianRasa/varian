import 'dart:convert';

import 'ai_workflow_contract.dart';

class AIEvaluationFixture {
  final String id;
  final String capability;
  final String expectedPrompt;
  final Map<String, dynamic>? expectedMask;
  final int expectedSeed;
  final Set<String> requiredOutputKeys;
  final Duration maxLatency;
  final double maxCost;
  final bool requireSafetyPass;
  final bool requireHumanAcceptance;

  const AIEvaluationFixture({
    required this.id,
    required this.capability,
    required this.expectedPrompt,
    required this.expectedSeed,
    this.expectedMask,
    this.requiredOutputKeys = const {},
    this.maxLatency = const Duration(seconds: 30),
    this.maxCost = 100,
    this.requireSafetyPass = true,
    this.requireHumanAcceptance = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'capability': capability,
    'expectedPrompt': expectedPrompt,
    'expectedMask': expectedMask,
    'expectedSeed': expectedSeed,
    'requiredOutputKeys': requiredOutputKeys.toList(growable: false),
    'maxLatencyMs': maxLatency.inMilliseconds,
    'maxCost': maxCost,
    'requireSafetyPass': requireSafetyPass,
    'requireHumanAcceptance': requireHumanAcceptance,
  };

  factory AIEvaluationFixture.fromJson(Map<String, dynamic> json) =>
      AIEvaluationFixture(
        id: json['id']?.toString() ?? '',
        capability: json['capability']?.toString() ?? '',
        expectedPrompt: json['expectedPrompt']?.toString() ?? '',
        expectedMask: json['expectedMask'] is Map
            ? Map<String, dynamic>.from(json['expectedMask'] as Map)
            : null,
        expectedSeed: (json['expectedSeed'] as num?)?.toInt() ?? -1,
        requiredOutputKeys:
            (json['requiredOutputKeys'] as List<dynamic>? ?? const [])
                .map((value) => value.toString())
                .toSet(),
        maxLatency: Duration(
          milliseconds: (json['maxLatencyMs'] as num?)?.toInt() ?? 30000,
        ),
        maxCost: (json['maxCost'] as num?)?.toDouble() ?? 100,
        requireSafetyPass: json['requireSafetyPass'] as bool? ?? true,
        requireHumanAcceptance:
            json['requireHumanAcceptance'] as bool? ?? false,
      );
}

class AIEvaluationObservation {
  final String fixtureId;
  final String capability;
  final String prompt;
  final Map<String, dynamic>? mask;
  final int seed;
  final Map<String, dynamic> output;
  final Duration latency;
  final double cost;
  final bool safetyPassed;
  final bool humanAccepted;

  const AIEvaluationObservation({
    required this.fixtureId,
    required this.capability,
    required this.prompt,
    required this.seed,
    required this.output,
    required this.latency,
    required this.cost,
    required this.safetyPassed,
    this.mask,
    this.humanAccepted = false,
  });
}

class AIEvaluationCheck {
  final String name;
  final bool passed;
  final String expected;
  final String actual;

  const AIEvaluationCheck({
    required this.name,
    required this.passed,
    required this.expected,
    required this.actual,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'passed': passed,
    'expected': expected,
    'actual': actual,
  };
}

class AIEvaluationResult {
  final String fixtureId;
  final bool passed;
  final List<AIEvaluationCheck> checks;

  const AIEvaluationResult({
    required this.fixtureId,
    required this.passed,
    required this.checks,
  });

  List<AIEvaluationCheck> get failures =>
      checks.where((check) => !check.passed).toList(growable: false);

  Map<String, dynamic> toJson() => {
    'fixtureId': fixtureId,
    'passed': passed,
    'checks': checks.map((check) => check.toJson()).toList(growable: false),
  };
}

class AIEvaluationReport {
  final DateTime evaluatedAt;
  final List<AIEvaluationResult> results;

  const AIEvaluationReport({required this.evaluatedAt, required this.results});

  int get passedCount => results.where((result) => result.passed).length;
  int get failedCount => results.length - passedCount;
  bool get passed => results.every((result) => result.passed);

  Map<String, dynamic> toJson() => {
    'evaluatedAt': evaluatedAt.toUtc().toIso8601String(),
    'passed': passed,
    'passedCount': passedCount,
    'failedCount': failedCount,
    'results': results.map((result) => result.toJson()).toList(growable: false),
  };
}

class AIEvaluationHarness {
  const AIEvaluationHarness();

  AIEvaluationReport evaluate(
    Iterable<AIEvaluationFixture> fixtures,
    Iterable<AIEvaluationObservation> observations, {
    DateTime? evaluatedAt,
  }) {
    final observationsByFixture = <String, AIEvaluationObservation>{};
    for (final observation in observations) {
      observationsByFixture.putIfAbsent(
        observation.fixtureId,
        () => observation,
      );
    }
    final results = [
      for (final fixture in fixtures)
        evaluateFixture(fixture, observationsByFixture[fixture.id]),
    ];
    return AIEvaluationReport(
      evaluatedAt: (evaluatedAt ?? DateTime.now()).toUtc(),
      results: results,
    );
  }

  AIEvaluationResult evaluateFixture(
    AIEvaluationFixture fixture,
    AIEvaluationObservation? observation,
  ) {
    if (observation == null) {
      return AIEvaluationResult(
        fixtureId: fixture.id,
        passed: false,
        checks: [
          const AIEvaluationCheck(
            name: 'observation',
            passed: false,
            expected: 'an observation for the fixture',
            actual: 'missing',
          ),
        ],
      );
    }
    final checks = <AIEvaluationCheck>[
      _check('capability', fixture.capability, observation.capability),
      _check('prompt', fixture.expectedPrompt, observation.prompt),
      _check(
        'seed',
        fixture.expectedSeed.toString(),
        observation.seed.toString(),
      ),
      _check(
        'mask',
        _canonicalJson(fixture.expectedMask),
        _canonicalJson(observation.mask),
      ),
      _checkOutputSchema(fixture, observation.output),
      _check(
        'latency',
        '<= ${fixture.maxLatency.inMilliseconds}ms',
        '${observation.latency.inMilliseconds}ms',
        observation.latency <= fixture.maxLatency,
      ),
      _check(
        'cost',
        '<= ${fixture.maxCost}',
        observation.cost.toString(),
        observation.cost.isFinite && observation.cost <= fixture.maxCost,
      ),
      _check(
        'safety',
        fixture.requireSafetyPass ? 'passed' : 'not required',
        observation.safetyPassed ? 'passed' : 'failed',
        !fixture.requireSafetyPass || observation.safetyPassed,
      ),
      _check(
        'humanAcceptance',
        fixture.requireHumanAcceptance ? 'accepted' : 'not required',
        observation.humanAccepted ? 'accepted' : 'not accepted',
        !fixture.requireHumanAcceptance || observation.humanAccepted,
      ),
    ];
    return AIEvaluationResult(
      fixtureId: fixture.id,
      passed: checks.every((check) => check.passed),
      checks: checks,
    );
  }

  AIEvaluationCheck _check(
    String name,
    String expected,
    String actual, [
    bool? passed,
  ]) => AIEvaluationCheck(
    name: name,
    expected: expected,
    actual: actual,
    passed: passed ?? expected == actual,
  );

  AIEvaluationCheck _checkOutputSchema(
    AIEvaluationFixture fixture,
    Map<String, dynamic> output,
  ) {
    final missing = fixture.requiredOutputKeys
        .where((key) => !output.containsKey(key))
        .toList(growable: false);
    return AIEvaluationCheck(
      name: 'outputSchema',
      passed: missing.isEmpty,
      expected: fixture.requiredOutputKeys.isEmpty
          ? 'any object'
          : fixture.requiredOutputKeys.join(', '),
      actual: missing.isEmpty ? 'valid' : 'missing: ${missing.join(', ')}',
    );
  }
}

String _canonicalJson(Object? value) {
  Object? canonicalize(Object? input) {
    if (input is Map) {
      final entries = input.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return {
        for (final entry in entries)
          entry.key.toString(): canonicalize(entry.value),
      };
    }
    if (input is List) return input.map(canonicalize).toList(growable: false);
    if (input is AIMaskDocument) return canonicalize(input.toJson());
    return input;
  }

  return jsonEncode(canonicalize(value));
}
