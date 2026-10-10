import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../../../domain/models/prototype_interaction.dart';

class PrototypeInteractionExecution {
  final String? interactionId;
  final String? sourceNodeId;
  final PrototypeTrigger? trigger;
  final PrototypeAction? action;
  final String? targetFrameId;
  final String? targetNodeId;
  final String? stateId;
  final String? url;
  final PrototypeTransition transition;
  final int durationMs;
  final bool preserveScroll;
  final String? error;

  const PrototypeInteractionExecution({
    this.interactionId,
    this.sourceNodeId,
    this.trigger,
    this.action,
    this.targetFrameId,
    this.targetNodeId,
    this.stateId,
    this.url,
    this.transition = PrototypeTransition.instant,
    this.durationMs = 0,
    this.preserveScroll = false,
    this.error,
  });

  bool get applied => action != null && error == null;

  bool get goBack => applied && action == PrototypeAction.back;

  factory PrototypeInteractionExecution.none({
    String? sourceNodeId,
    PrototypeTrigger? trigger,
    String? error,
  }) => PrototypeInteractionExecution(
    sourceNodeId: sourceNodeId,
    trigger: trigger,
    error: error,
  );
}

class PrototypeInteractionEngine {
  final List<CanvasNode> nodes;
  late final Map<String, CanvasNode> _nodesById = {
    for (final node in nodes) node.id: node,
  };

  PrototypeInteractionEngine(Iterable<CanvasNode> nodes)
    : nodes = List<CanvasNode>.unmodifiable(nodes);

  PrototypeInteractionExecution resolve({
    required String nodeId,
    required PrototypeTrigger trigger,
  }) {
    final node = _nodesById[nodeId];
    if (node == null) {
      return PrototypeInteractionExecution.none(
        sourceNodeId: nodeId,
        trigger: trigger,
        error: 'Prototype source node does not exist.',
      );
    }

    final interaction = node.prototypeInteractions
        .map((candidate) => candidate.normalized())
        .where((candidate) => candidate.enabled && candidate.trigger == trigger)
        .firstOrNull;
    if (interaction == null) {
      return PrototypeInteractionExecution.none(
        sourceNodeId: nodeId,
        trigger: trigger,
      );
    }

    final base = PrototypeInteractionExecution(
      interactionId: interaction.id,
      sourceNodeId: nodeId,
      trigger: trigger,
      action: interaction.action,
      targetFrameId: interaction.targetFrameId,
      targetNodeId: interaction.targetNodeId,
      stateId: interaction.stateId,
      url: interaction.url,
      transition: interaction.transition,
      durationMs: interaction.durationMs,
      preserveScroll: interaction.preserveScroll,
    );

    if (!interaction.isValid) {
      return _withError(
        base,
        'Interaction target is required for this action.',
      );
    }

    switch (interaction.action) {
      case PrototypeAction.navigate:
        if (!_hasFrame(interaction.targetFrameId)) {
          return _withError(base, 'Target frame does not exist.');
        }
      case PrototypeAction.overlay:
        if (!_hasNode(interaction.targetNodeId)) {
          return _withError(base, 'Target overlay node does not exist.');
        }
      case PrototypeAction.setState:
        break;
      case PrototypeAction.openUrl:
        final uri = Uri.tryParse(interaction.url ?? '');
        if (uri == null ||
            !uri.hasScheme ||
            uri.host.isEmpty && uri.scheme != 'mailto') {
          return _withError(base, 'URL must be an absolute deep link.');
        }
      case PrototypeAction.back:
        break;
    }

    return base;
  }

  bool _hasFrame(String? id) =>
      id != null && _nodesById[id]?.type == NodeType.frame;

  bool _hasNode(String? id) => id != null && _nodesById.containsKey(id);

  PrototypeInteractionExecution _withError(
    PrototypeInteractionExecution execution,
    String error,
  ) => PrototypeInteractionExecution(
    interactionId: execution.interactionId,
    sourceNodeId: execution.sourceNodeId,
    trigger: execution.trigger,
    action: execution.action,
    targetFrameId: execution.targetFrameId,
    targetNodeId: execution.targetNodeId,
    stateId: execution.stateId,
    url: execution.url,
    transition: execution.transition,
    durationMs: execution.durationMs,
    preserveScroll: execution.preserveScroll,
    error: error,
  );
}
