import 'dart:convert';
import 'dart:io';

import 'package:varian/features/performance/domain/creative_studio_benchmark.dart';

void main() {
  final results = [
    for (final scenario in CreativeStudioBenchmark.scenarios)
      CreativeStudioBenchmark.run(scenario),
  ];
  final output = [
    for (final result in results)
      {
        'scenario': result.scenario.id,
        'generationMs': result.generationDuration.inMicroseconds / 1000,
        'operationMs': result.operationDuration.inMicroseconds / 1000,
        'passed': result.passed,
      },
  ];
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
  if (results.any((result) => !result.passed)) {
    throw StateError('Creative Studio benchmark smoke failed.');
  }
}
