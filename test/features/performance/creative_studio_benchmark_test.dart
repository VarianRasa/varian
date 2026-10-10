import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/performance/domain/creative_studio_benchmark.dart';

void main() {
  test('benchmark smoke generates a deterministic document', () {
    final scenario = CreativeStudioBenchmark.scenarios.first;
    final first = BenchmarkDocument.generate(scenario);
    final second = BenchmarkDocument.generate(scenario);

    expect(first.nodeIds, second.nodeIds);
    expect(first.nodeIds, hasLength(scenario.nodeCount));
    expect(first.encode(), isNotEmpty);
  });

  test('benchmark smoke reports a passing result for the small scenario', () {
    final result = CreativeStudioBenchmark.run(
      CreativeStudioBenchmark.scenarios.first,
      operationCount: 100,
    );

    expect(result.operationCount, 100);
    expect(result.passed, isTrue);
  });

  test('performance budget covers frame, memory, startup, and sync limits', () {
    const budget = PerformanceBudget(
      frameTime: Duration(milliseconds: 20),
      memoryBytes: 100,
      startup: Duration(seconds: 1),
      syncLatency: Duration(milliseconds: 200),
    );

    expect(
      budget.accepts(
        frameTime: const Duration(milliseconds: 16),
        memoryBytes: 90,
        startup: const Duration(milliseconds: 800),
        syncLatency: const Duration(milliseconds: 150),
      ),
      isTrue,
    );
    expect(
      budget.accepts(
        frameTime: const Duration(milliseconds: 32),
        memoryBytes: 90,
        startup: const Duration(milliseconds: 800),
        syncLatency: const Duration(milliseconds: 150),
      ),
      isFalse,
    );
  });
}
