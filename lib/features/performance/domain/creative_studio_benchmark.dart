import 'dart:convert';

enum BenchmarkAssetKind { node, image, rasterStroke, video, glb }

class PerformanceBudget {
  final Duration frameTime;
  final int memoryBytes;
  final Duration startup;
  final Duration syncLatency;

  const PerformanceBudget({
    this.frameTime = const Duration(milliseconds: 16),
    this.memoryBytes = 512 * 1024 * 1024,
    this.startup = const Duration(seconds: 2),
    this.syncLatency = const Duration(milliseconds: 500),
  });

  bool accepts({
    required Duration frameTime,
    required int memoryBytes,
    required Duration startup,
    required Duration syncLatency,
  }) =>
      frameTime <= this.frameTime &&
      memoryBytes <= this.memoryBytes &&
      startup <= this.startup &&
      syncLatency <= this.syncLatency;

  Map<String, dynamic> toJson() => {
    'frameTimeMs': frameTime.inMilliseconds,
    'memoryBytes': memoryBytes,
    'startupMs': startup.inMilliseconds,
    'syncLatencyMs': syncLatency.inMilliseconds,
  };
}

class BenchmarkScenario {
  final String id;
  final String name;
  final int nodeCount;
  final int imageCount;
  final int rasterStrokeCount;
  final int videoCount;
  final int glbCount;
  final Duration startupBudget;
  final Duration operationBudget;
  final PerformanceBudget performanceBudget;

  const BenchmarkScenario({
    required this.id,
    required this.name,
    required this.nodeCount,
    this.imageCount = 0,
    this.rasterStrokeCount = 0,
    this.videoCount = 0,
    this.glbCount = 0,
    this.startupBudget = const Duration(milliseconds: 1500),
    this.operationBudget = const Duration(milliseconds: 16),
    this.performanceBudget = const PerformanceBudget(),
  });

  int countFor(BenchmarkAssetKind kind) => switch (kind) {
    BenchmarkAssetKind.node => nodeCount,
    BenchmarkAssetKind.image => imageCount,
    BenchmarkAssetKind.rasterStroke => rasterStrokeCount,
    BenchmarkAssetKind.video => videoCount,
    BenchmarkAssetKind.glb => glbCount,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'nodeCount': nodeCount,
    'imageCount': imageCount,
    'rasterStrokeCount': rasterStrokeCount,
    'videoCount': videoCount,
    'glbCount': glbCount,
    'startupBudgetMs': startupBudget.inMilliseconds,
    'operationBudgetMs': operationBudget.inMilliseconds,
    'performanceBudget': performanceBudget.toJson(),
  };
}

class BenchmarkDocument {
  final BenchmarkScenario scenario;
  final List<String> nodeIds;

  const BenchmarkDocument({required this.scenario, required this.nodeIds});

  factory BenchmarkDocument.generate(BenchmarkScenario scenario) {
    return BenchmarkDocument(
      scenario: scenario,
      nodeIds: List<String>.generate(
        scenario.nodeCount,
        (index) => '${scenario.id}-node-$index',
        growable: false,
      ),
    );
  }

  String encode() =>
      jsonEncode({'scenario': scenario.toJson(), 'nodeIds': nodeIds});
}

class BenchmarkRunResult {
  final BenchmarkScenario scenario;
  final Duration generationDuration;
  final Duration operationDuration;
  final int operationCount;

  const BenchmarkRunResult({
    required this.scenario,
    required this.generationDuration,
    required this.operationDuration,
    required this.operationCount,
  });

  bool get startupWithinBudget => generationDuration <= scenario.startupBudget;

  bool get operationWithinBudget =>
      operationDuration <= scenario.operationBudget;

  bool get passed => startupWithinBudget && operationWithinBudget;
}

class CreativeStudioBenchmark {
  const CreativeStudioBenchmark._();

  static const scenarios = <BenchmarkScenario>[
    BenchmarkScenario(
      id: 'smoke',
      name: 'Smoke',
      nodeCount: 250,
      imageCount: 8,
      rasterStrokeCount: 2,
      videoCount: 1,
      glbCount: 1,
    ),
    BenchmarkScenario(
      id: 'large-canvas',
      name: 'Large Canvas',
      nodeCount: 5000,
      imageCount: 80,
      rasterStrokeCount: 12,
      videoCount: 4,
      glbCount: 2,
      startupBudget: Duration(seconds: 4),
      operationBudget: Duration(milliseconds: 32),
    ),
  ];

  static BenchmarkRunResult run(
    BenchmarkScenario scenario, {
    int operationCount = 1000,
  }) {
    final generationStopwatch = Stopwatch()..start();
    final document = BenchmarkDocument.generate(scenario);
    generationStopwatch.stop();

    final operationStopwatch = Stopwatch()..start();
    var checksum = 0;
    for (var index = 0; index < operationCount; index++) {
      checksum ^= document.nodeIds[index % document.nodeIds.length].hashCode;
    }
    operationStopwatch.stop();
    if (checksum == -1) {
      throw StateError('Benchmark checksum could not be computed.');
    }

    return BenchmarkRunResult(
      scenario: scenario,
      generationDuration: generationStopwatch.elapsed,
      operationDuration: operationStopwatch.elapsed,
      operationCount: operationCount,
    );
  }
}
