import '../../../domain/models/ai_job.dart';
import '../../../domain/models/node.dart';

abstract interface class AIProviderExecutor {
  String get provider;

  Future<AIJob> execute({
    required AIJob job,
    required List<CanvasNode> currentNodes,
  });
}

class CallbackAIProviderExecutor implements AIProviderExecutor {
  @override
  final String provider;
  final Future<AIJob> Function(AIJob job, List<CanvasNode> currentNodes)
  callback;

  CallbackAIProviderExecutor({required this.provider, required this.callback});

  @override
  Future<AIJob> execute({
    required AIJob job,
    required List<CanvasNode> currentNodes,
  }) => callback(job, currentNodes);
}
