import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/painting.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../../mermaid/data/mermaid_renderer.dart';
import '../../mermaid/domain/mermaid_conversion.dart';
import '../../mermaid/domain/mermaid_svg_native_converter.dart';
import '../../mermaid/domain/mermaid_renderer.dart';
import 'document_edges_provider.dart';
import '../../history/history_provider.dart';
import '../commands/editor_commands.dart';
import '../commands/command_replay.dart';
import '../utils/align_engine.dart';
import '../utils/auto_layout_engine.dart';
import '../utils/hit_tester.dart';
import '../utils/transform_engine.dart';
import '../domain/canvas_precision.dart';
import '../domain/canvas_selection.dart';
import '../../collaboration/state/collaboration_provider.dart';
import 'selection_provider.dart';

class HistoryState {
  final List<EditorCommand> undoStack;
  final List<EditorCommand> redoStack;
  final List<CommandReplayEntry> replayEntries;

  const HistoryState({
    this.undoStack = const [],
    this.redoStack = const [],
    this.replayEntries = const [],
  });

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  HistoryState copyWith({
    List<EditorCommand>? undoStack,
    List<EditorCommand>? redoStack,
    List<CommandReplayEntry>? replayEntries,
  }) {
    return HistoryState(
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      replayEntries: replayEntries ?? this.replayEntries,
    );
  }
}

final historyProvider = StateNotifierProvider<HistoryNotifier, HistoryState>((
  ref,
) {
  return HistoryNotifier();
});

class HistoryNotifier extends StateNotifier<HistoryState> {
  HistoryNotifier() : super(const HistoryState());

  void pushCommand(EditorCommand command) {
    final updatedUndo = [...state.undoStack, command];
    if (updatedUndo.length > 100) {
      updatedUndo.removeAt(0);
    }
    state = HistoryState(undoStack: updatedUndo, redoStack: const []);
  }

  void recordReplay({
    required String phase,
    required EditorCommand command,
    required int nodeCountBefore,
    required int nodeCountAfter,
    required int edgeCountBefore,
    required int edgeCountAfter,
  }) {
    final entries = [
      ...state.replayEntries,
      CommandReplayEntry.fromCommand(
        sequence: state.replayEntries.length,
        phase: phase,
        command: command,
        timestamp: DateTime.now(),
        nodeCountBefore: nodeCountBefore,
        nodeCountAfter: nodeCountAfter,
        edgeCountBefore: edgeCountBefore,
        edgeCountAfter: edgeCountAfter,
      ),
    ];
    state = state.copyWith(
      replayEntries: entries.length > 500
          ? entries.sublist(entries.length - 500)
          : entries,
    );
  }

  CommandReplayLog exportReplay(String projectId) => CommandReplayLog(
    projectId: projectId,
    createdAt: DateTime.now(),
    entries: state.replayEntries,
  );

  EditorCommand? popUndo() {
    if (!state.canUndo) return null;
    final command = state.undoStack.last;
    final newUndo = List<EditorCommand>.from(state.undoStack)..removeLast();
    state = HistoryState(
      undoStack: newUndo,
      redoStack: [...state.redoStack, command],
    );
    return command;
  }

  EditorCommand? popRedo() {
    if (!state.canRedo) return null;
    final command = state.redoStack.last;
    final newRedo = List<EditorCommand>.from(state.redoStack)..removeLast();
    state = HistoryState(
      undoStack: [...state.undoStack, command],
      redoStack: newRedo,
    );
    return command;
  }

  void clear() {
    state = const HistoryState();
  }
}

final mermaidConversionInFlightProvider = StateProvider<Set<String>>(
  (ref) => const <String>{},
);

final documentNodesProvider =
    StateNotifierProvider<DocumentNodesNotifier, List<CanvasNode>>((ref) {
      return DocumentNodesNotifier(ref);
    });

class DocumentNodesNotifier extends StateNotifier<List<CanvasNode>> {
  final Ref _ref;
  final MermaidRenderer _mermaidRenderer;
  final Set<String> _mermaidConversionsInFlight = <String>{};
  List<EditorCommand>? _transactionCommands;
  String? _transactionName;
  String? _activePageId;

  DocumentNodesNotifier(
    this._ref, {
    List<CanvasNode> initialNodes = const [],
    MermaidRenderer? mermaidRenderer,
  }) : _mermaidRenderer = mermaidRenderer ?? createPlatformMermaidRenderer(),
       super(List<CanvasNode>.unmodifiable(initialNodes));

  List<CanvasNode> get nodes => state;

  bool get hasActiveTransaction => _transactionCommands != null;

  void setActivePageId(String? pageId) {
    _activePageId = pageId;
  }

  void beginTransaction({required String name}) {
    if (_transactionCommands != null) return;
    _transactionCommands = <EditorCommand>[];
    _transactionName = name;
  }

  void commitTransaction() {
    final commands = _transactionCommands;
    final name = _transactionName;
    _transactionCommands = null;
    _transactionName = null;
    if (commands == null || commands.isEmpty) return;
    _ref
        .read(historyProvider.notifier)
        .pushCommand(
          CompositeEditorCommand(
            label: name ?? 'Canvas transaction',
            commands: commands,
          ),
        );
  }

  void cancelTransaction() {
    final commands = _transactionCommands;
    _transactionCommands = null;
    _transactionName = null;
    if (commands == null || commands.isEmpty) return;
    for (final command in commands.reversed) {
      state = command.undo(state);
      _applyEdgeTransform(command.undoEdges);
    }
  }

  void setNodes(List<CanvasNode> nodes, {bool clearSelection = true}) {
    state = nodes;
    if (clearSelection) {
      _ref.read(selectionProvider.notifier).clear();
    }
  }

  /// Applies live editor input without adding one undo entry per keystroke.
  void updateTransientNode(CanvasNode updated) {
    final index = state.indexWhere((node) => node.id == updated.id);
    if (index < 0) return;
    if (state[index].toJson().toString() == updated.toJson().toString()) {
      return;
    }
    final next = List<CanvasNode>.from(state)..[index] = updated;
    state = List<CanvasNode>.unmodifiable(next);
  }

  void executeCommand(EditorCommand command) {
    final beforeNodes = state.length;
    final beforeEdges = _ref.read(documentEdgesProvider).length;
    state = command.execute(state);
    _applyEdgeTransform(command.executeEdges);
    final afterEdges = _ref.read(documentEdgesProvider).length;
    _ref
        .read(historyProvider.notifier)
        .recordReplay(
          phase: 'execute',
          command: command,
          nodeCountBefore: beforeNodes,
          nodeCountAfter: state.length,
          edgeCountBefore: beforeEdges,
          edgeCountAfter: afterEdges,
        );
    final transaction = _transactionCommands;
    if (transaction != null) {
      transaction.add(command);
    } else {
      _ref.read(historyProvider.notifier).pushCommand(command);
    }
  }

  void undo() {
    final command = _ref.read(historyProvider.notifier).popUndo();
    if (command == null) return;

    final beforeNodes = state.length;
    final beforeEdges = _ref.read(documentEdgesProvider).length;
    state = command.undo(state);
    _applyEdgeTransform(command.undoEdges);
    _ref
        .read(historyProvider.notifier)
        .recordReplay(
          phase: 'undo',
          command: command,
          nodeCountBefore: beforeNodes,
          nodeCountAfter: state.length,
          edgeCountBefore: beforeEdges,
          edgeCountAfter: _ref.read(documentEdgesProvider).length,
        );
  }

  void redo() {
    final command = _ref.read(historyProvider.notifier).popRedo();
    if (command == null) return;

    final beforeNodes = state.length;
    final beforeEdges = _ref.read(documentEdgesProvider).length;
    state = command.execute(state);
    _applyEdgeTransform(command.executeEdges);
    _ref
        .read(historyProvider.notifier)
        .recordReplay(
          phase: 'redo',
          command: command,
          nodeCountBefore: beforeNodes,
          nodeCountAfter: state.length,
          edgeCountBefore: beforeEdges,
          edgeCountAfter: _ref.read(documentEdgesProvider).length,
        );
  }

  void _applyEdgeTransform(
    List<CanvasEdge> Function(List<CanvasEdge>) transform,
  ) {
    final currentEdges = _ref.read(documentEdgesProvider);
    final transformedEdges = transform(currentEdges);
    if (identical(currentEdges, transformedEdges)) return;
    _ref.read(documentEdgesProvider.notifier).setEdges(transformedEdges);
  }

  void updateNode(CanvasNode updated, {CanvasNode? historyFrom}) {
    final oldNode =
        historyFrom ??
        state.firstWhere((n) => n.id == updated.id, orElse: () => updated);
    final mermaidSource = _mermaidSourceForNode(updated.id);
    final additionalOldNodes = <CanvasNode>[];
    final additionalNewNodes = <CanvasNode>[];
    final additionalNodeIndexes = <String, int>{};
    final oldById = <String, CanvasNode>{updated.id: oldNode};
    final newById = <String, CanvasNode>{updated.id: updated};
    final pendingParentIds = <String>[updated.id];

    void setAdditionalNode(CanvasNode oldChild, CanvasNode newChild) {
      final existingIndex = additionalNodeIndexes[oldChild.id];
      if (existingIndex == null) {
        additionalNodeIndexes[oldChild.id] = additionalOldNodes.length;
        additionalOldNodes.add(oldChild);
        additionalNewNodes.add(newChild);
      } else {
        additionalNewNodes[existingIndex] = newChild;
      }
    }

    while (pendingParentIds.isNotEmpty) {
      final parentId = pendingParentIds.removeAt(0);
      final oldParent = oldById[parentId];
      final newParent = newById[parentId];
      if (oldParent == null || newParent == null) continue;

      for (final child in state.where((node) => node.parentId == parentId)) {
        if (child.constraints == null || oldById.containsKey(child.id)) {
          continue;
        }
        final resolved = CanvasConstraintEngine.resolve(
          child,
          oldParent: oldParent.bounds,
          newParent: newParent.bounds,
        );
        if (resolved.toJson().toString() == child.toJson().toString()) continue;
        oldById[child.id] = child;
        newById[child.id] = resolved;
        setAdditionalNode(child, resolved);
        pendingParentIds.add(child.id);
      }
    }

    final rotationDelta = _shortestRotationDelta(
      oldNode.rotation,
      updated.rotation,
    );
    if (oldNode.type == NodeType.frame &&
        updated.type == NodeType.frame &&
        rotationDelta.abs() > 0.0000001) {
      final frameCenter = oldNode.bounds.center;
      for (final descendant in _descendantsOf(updated.id)) {
        final oldDescendant = oldById[descendant.id] ?? descendant;
        final baseDescendant = newById[descendant.id] ?? descendant;
        final rotatedDescendant = CanvasTransformEngine.rotateNodeAround(
          baseDescendant,
          center: frameCenter,
          radians: rotationDelta,
        );
        oldById[descendant.id] = oldDescendant;
        newById[descendant.id] = rotatedDescendant;
        setAdditionalNode(oldDescendant, rotatedDescendant);
      }
    }

    if (mermaidSource != null && mermaidSource.id != updated.id) {
      final payload = mermaidSource.payload;
      if (payload is MermaidPayload &&
          payload.conversionStatus != MermaidConversionStatus.nativeEdited) {
        additionalOldNodes.add(mermaidSource);
        additionalNewNodes.add(
          mermaidSource.copyWith(
            payload: payload.copyWith(
              conversionStatus: MermaidConversionStatus.nativeEdited,
            ),
          ),
        );
      }
    }
    _ref.read(nodeHistoryProvider.notifier).recordSnapshot(oldNode);
    for (final node in additionalOldNodes) {
      _ref.read(nodeHistoryProvider.notifier).recordSnapshot(node);
    }
    executeCommand(
      UpdateNodeCommand(
        oldNode: oldNode,
        newNode: updated,
        additionalOldNodes: additionalOldNodes,
        additionalNewNodes: additionalNewNodes,
      ),
    );
  }

  List<CanvasNode> _descendantsOf(String rootId) {
    final descendants = <CanvasNode>[];
    final pendingParentIds = <String>[rootId];
    final visited = <String>{rootId};

    while (pendingParentIds.isNotEmpty) {
      final parentId = pendingParentIds.removeAt(0);
      for (final node in state) {
        if (node.parentId != parentId || !visited.add(node.id)) continue;
        descendants.add(node);
        pendingParentIds.add(node.id);
      }
    }
    return descendants;
  }

  double _shortestRotationDelta(double from, double to) {
    if (!from.isFinite || !to.isFinite) return 0.0;
    var delta = (to - from) % (2 * math.pi);
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    return delta;
  }

  void updateEdge(CanvasEdge updated) {
    if (!_isValidEdgeGeometry(updated)) return;
    final edges = _ref.read(documentEdgesProvider);
    final oldEdge = edges.where((edge) => edge.id == updated.id).firstOrNull;
    if (oldEdge == null ||
        oldEdge.toJson().toString() == updated.toJson().toString()) {
      return;
    }

    final mermaidSource = _mermaidSourceForEdge(oldEdge.id);
    CanvasNode? oldMermaidSource;
    CanvasNode? newMermaidSource;
    if (mermaidSource != null) {
      final payload = mermaidSource.payload as MermaidPayload;
      if (payload.conversionStatus != MermaidConversionStatus.nativeEdited) {
        oldMermaidSource = mermaidSource;
        newMermaidSource = mermaidSource.copyWith(
          payload: payload.copyWith(
            conversionStatus: MermaidConversionStatus.nativeEdited,
          ),
        );
        _ref.read(nodeHistoryProvider.notifier).recordSnapshot(mermaidSource);
      }
    }

    executeCommand(
      UpdateEdgeCommand(
        oldEdge: oldEdge,
        newEdge: updated,
        oldMermaidSource: oldMermaidSource,
        newMermaidSource: newMermaidSource,
      ),
    );
  }

  bool _isValidEdgeGeometry(CanvasEdge edge) {
    bool validPoint(Offset? point) =>
        point == null || (point.dx.isFinite && point.dy.isFinite);
    return edge.waypoints.length <= CanvasEdge.maxWaypoints &&
        validPoint(edge.sourcePoint) &&
        validPoint(edge.targetPoint) &&
        edge.waypoints.every(validPoint);
  }

  CanvasNode? _mermaidSourceForEdge(String edgeId) {
    for (final node in state) {
      if (node.type != NodeType.mermaid || node.payload is! MermaidPayload) {
        continue;
      }
      final payload = node.payload as MermaidPayload;
      if (payload.renderMode != MermaidRenderMode.native ||
          !payload.nativeEdgeIds.contains(edgeId)) {
        continue;
      }
      final edge = _ref
          .read(documentEdgesProvider)
          .where((candidate) => candidate.id == edgeId)
          .firstOrNull;
      if (edge == null ||
          edge.mermaidSourceId == null ||
          edge.mermaidSourceId == node.id) {
        return node;
      }
    }
    return null;
  }

  /// Updates derived render data without creating an editor undo step.
  ///
  /// Mermaid SVG is a cache artifact, not a user edit. Keeping it out of the
  /// command history prevents every asynchronous render from consuming an
  /// undo slot while still notifying autosave and canvas listeners.
  void updateDerivedNode(CanvasNode updated) {
    final index = state.indexWhere((node) => node.id == updated.id);
    if (index < 0) return;
    if (state[index].toJson().toString() == updated.toJson().toString()) return;

    final next = List<CanvasNode>.from(state)..[index] = updated;
    state = List<CanvasNode>.unmodifiable(next);
  }

  Future<MermaidConversionResult> convertMermaidNodeAsync(String nodeId) =>
      _convertMermaidNodeAsync(nodeId, regenerate: false);

  Future<MermaidConversionResult> regenerateMermaidNodeAsync(String nodeId) =>
      _convertMermaidNodeAsync(nodeId, regenerate: true);

  Future<MermaidConversionResult> _convertMermaidNodeAsync(
    String nodeId, {
    required bool regenerate,
  }) async {
    if (!_mermaidConversionsInFlight.add(nodeId)) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'CONVERSION_IN_PROGRESS',
          message: 'This Mermaid diagram is already being converted.',
          severity: MermaidDiagnosticSeverity.info,
        ),
      );
    }
    _publishMermaidConversionState();

    try {
      final source = _mermaidSourceForNode(nodeId);
      if (source == null || source.id != nodeId) {
        return const MermaidConversionResult.failure(
          MermaidDiagnostic(
            code: 'MERMAID_SOURCE_NOT_FOUND',
            message: 'The selected object is not a Mermaid source node.',
          ),
        );
      }
      final payload = source.payload as MermaidPayload;
      if (regenerate && payload.renderMode != MermaidRenderMode.native) {
        return const MermaidConversionResult.failure(
          MermaidDiagnostic(
            code: 'NOT_NATIVE',
            message: 'Only a native Mermaid graph can be regenerated.',
            severity: MermaidDiagnosticSeverity.info,
          ),
        );
      }
      if (!regenerate && payload.renderMode == MermaidRenderMode.native) {
        return const MermaidConversionResult.failure(
          MermaidDiagnostic(
            code: 'ALREADY_NATIVE',
            message:
                'This Mermaid source is already converted to native objects.',
            severity: MermaidDiagnosticSeverity.info,
          ),
        );
      }

      final revision = payload.sourceRevision;
      final signature = _mermaidSourceSignature(payload);
      final config = MermaidRenderConfig(
        theme: payload.theme,
        direction: payload.direction,
        overrides: payload.config,
      );
      final cachedSvg = _matchingMermaidSvg(payload, config);
      final result = await MermaidNativeConverter(
        renderer: _mermaidRenderer,
      ).convert(source, cachedSvg: cachedSvg);

      final current = state.where((node) => node.id == nodeId).firstOrNull;
      if (current == null || current.payload is! MermaidPayload) {
        return const MermaidConversionResult.failure(
          MermaidDiagnostic(
            code: 'STALE_CONVERSION',
            message: 'The Mermaid source changed before conversion completed.',
          ),
        );
      }
      final currentPayload = current.payload as MermaidPayload;
      if (_mermaidSourceSignature(currentPayload) != signature ||
          currentPayload.sourceRevision != revision ||
          (regenerate &&
              currentPayload.renderMode != MermaidRenderMode.native) ||
          (!regenerate &&
              currentPayload.renderMode == MermaidRenderMode.native)) {
        return const MermaidConversionResult.failure(
          MermaidDiagnostic(
            code: 'STALE_CONVERSION',
            message: 'The Mermaid source changed before conversion completed.',
          ),
        );
      }
      if (!result.isSuccess) return result;
      return _commitMermaidConversion(
        source: current,
        result: result,
        action: regenerate ? 'Regenerate' : 'Convert',
        replaceExisting: regenerate,
      );
    } finally {
      _mermaidConversionsInFlight.remove(nodeId);
      _publishMermaidConversionState();
    }
  }

  void _publishMermaidConversionState() {
    _ref.read(mermaidConversionInFlightProvider.notifier).state =
        Set<String>.unmodifiable(_mermaidConversionsInFlight);
  }

  String? _matchingMermaidSvg(
    MermaidPayload payload,
    MermaidRenderConfig config,
  ) {
    final svg = payload.cachedSvg;
    if (svg == null || svg.isEmpty) return null;
    if (payload.cachedSvgRevision != payload.sourceRevision ||
        payload.cachedSvgConfigKey != config.cacheKey ||
        (_mermaidRenderer.rendererVersion != null &&
            payload.rendererVersion != _mermaidRenderer.rendererVersion)) {
      return null;
    }
    return svg;
  }

  String _mermaidSourceSignature(MermaidPayload payload) => jsonEncode({
    'source': payload.source,
    'revision': payload.sourceRevision,
    'theme': payload.theme.value,
    'direction': payload.direction?.value,
    'config': MermaidRenderConfig(overrides: payload.config).safeOverrides,
  });

  MermaidConversionResult _commitMermaidConversion({
    required CanvasNode source,
    required MermaidConversionResult result,
    required String action,
    required bool replaceExisting,
  }) {
    final oldNodeIds = replaceExisting
        ? _ownedMermaidNodeIds(source)
        : <String>{};
    final oldEdgeIds = replaceExisting
        ? _ownedMermaidEdgeIds(source)
        : <String>{};
    if (_hasMermaidIdConflict(
      result,
      ignoring: {...oldNodeIds, ...oldEdgeIds, source.id},
    )) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'MERMAID_ID_CONFLICT',
          message: 'The generated Mermaid object IDs are already in use.',
        ),
      );
    }

    final payload = source.payload as MermaidPayload;
    final renderedSvg = result.renderedSvg;
    final renderConfig = MermaidRenderConfig(
      theme: payload.theme,
      direction: payload.direction,
      overrides: payload.config,
    );
    final nextSource = source.copyWith(
      visible: false,
      payload: payload.copyWith(
        diagramType: result.diagramType,
        renderMode: MermaidRenderMode.native,
        conversionStatus: MermaidConversionStatus.converted,
        nativeNodeIds: result.nativeNodeIds,
        nativeEdgeIds: result.nativeEdgeIds,
        cachedSvg: renderedSvg ?? payload.cachedSvg,
        cachedSvgRevision: renderedSvg == null
            ? payload.cachedSvgRevision
            : payload.sourceRevision,
        cachedSvgConfigKey: renderedSvg == null
            ? payload.cachedSvgConfigKey
            : renderConfig.cacheKey,
        rendererVersion: renderedSvg == null
            ? payload.rendererVersion
            : _mermaidRenderer.rendererVersion,
        lastError: null,
      ),
    );
    final remainingNodes = replaceExisting
        ? state.where((node) => !oldNodeIds.contains(node.id)).toList()
        : List<CanvasNode>.from(state);
    final remainingEdges = replaceExisting
        ? _ref
              .read(documentEdgesProvider)
              .where(
                (edge) =>
                    !oldEdgeIds.contains(edge.id) &&
                    !oldNodeIds.contains(edge.sourceNodeId) &&
                    !oldNodeIds.contains(edge.targetNodeId),
              )
              .toList()
        : List<CanvasEdge>.from(_ref.read(documentEdgesProvider));
    final generatedNodes = _withMermaidZOrder(result.nodes, remainingNodes);
    final nextNodes = [
      for (final node in remainingNodes)
        node.id == source.id ? nextSource : node,
      ...generatedNodes,
    ];
    _executeMermaidLifecycle(
      action: action,
      source: source,
      afterNodes: nextNodes,
      afterEdges: [...remainingEdges, ...result.edges],
    );
    return result;
  }

  MermaidConversionResult convertMermaidNode(String nodeId) {
    final source = _mermaidSourceForNode(nodeId);
    if (source == null || source.id != nodeId) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'MERMAID_SOURCE_NOT_FOUND',
          message: 'The selected object is not a Mermaid source node.',
        ),
      );
    }
    final payload = source.payload as MermaidPayload;
    if (payload.renderMode == MermaidRenderMode.native) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'ALREADY_NATIVE',
          message:
              'This Mermaid source is already converted to native objects.',
          severity: MermaidDiagnosticSeverity.info,
        ),
      );
    }

    final config = MermaidRenderConfig(
      theme: payload.theme,
      direction: payload.direction,
      overrides: payload.config,
    );
    final cachedSvg = _matchingMermaidSvg(payload, config);
    if (cachedSvg == null) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'ASYNC_CONVERSION_REQUIRED',
          message:
              'Mermaid conversion requires a current rendered preview. Use the async conversion action.',
          severity: MermaidDiagnosticSeverity.info,
        ),
      );
    }
    final result = MermaidSvgNativeConverter.convert(source, cachedSvg);
    if (!result.isSuccess) return result;
    if (_hasMermaidIdConflict(result)) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'MERMAID_ID_CONFLICT',
          message: 'The generated Mermaid object IDs are already in use.',
        ),
      );
    }

    final nextSource = source.copyWith(
      visible: false,
      payload: payload.copyWith(
        diagramType: 'flowchart',
        renderMode: MermaidRenderMode.native,
        conversionStatus: MermaidConversionStatus.converted,
        nativeNodeIds: result.nativeNodeIds,
        nativeEdgeIds: result.nativeEdgeIds,
        lastError: null,
      ),
    );
    final generatedNodes = _withMermaidZOrder(result.nodes, state);
    final nextNodes = [
      for (final node in state) node.id == source.id ? nextSource : node,
      ...generatedNodes,
    ];
    final nextEdges = [..._ref.read(documentEdgesProvider), ...result.edges];
    _executeMermaidLifecycle(
      action: 'Convert',
      source: source,
      afterNodes: nextNodes,
      afterEdges: nextEdges,
    );
    return result;
  }

  MermaidConversionResult regenerateMermaidNode(String nodeId) {
    final source = _mermaidSourceForNode(nodeId);
    if (source == null || source.id != nodeId) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'MERMAID_SOURCE_NOT_FOUND',
          message: 'The Mermaid source node could not be found.',
        ),
      );
    }
    final payload = source.payload as MermaidPayload;
    if (payload.renderMode != MermaidRenderMode.native) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'NOT_NATIVE',
          message: 'Only a native Mermaid graph can be regenerated.',
          severity: MermaidDiagnosticSeverity.info,
        ),
      );
    }

    final config = MermaidRenderConfig(
      theme: payload.theme,
      direction: payload.direction,
      overrides: payload.config,
    );
    final cachedSvg = _matchingMermaidSvg(payload, config);
    if (cachedSvg == null) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'ASYNC_CONVERSION_REQUIRED',
          message:
              'Mermaid regeneration requires a current rendered preview. Use the async regeneration action.',
          severity: MermaidDiagnosticSeverity.info,
        ),
      );
    }
    final result = MermaidSvgNativeConverter.convert(source, cachedSvg);
    if (!result.isSuccess) return result;

    final oldNodeIds = _ownedMermaidNodeIds(source);
    final oldEdgeIds = _ownedMermaidEdgeIds(source);
    if (_hasMermaidIdConflict(
      result,
      ignoring: {...oldNodeIds, ...oldEdgeIds, source.id},
    )) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'MERMAID_ID_CONFLICT',
          message: 'The generated Mermaid object IDs are already in use.',
        ),
      );
    }

    final remainingNodes = state
        .where((node) => !oldNodeIds.contains(node.id))
        .toList();
    final remainingEdges = _ref
        .read(documentEdgesProvider)
        .where(
          (edge) =>
              !oldEdgeIds.contains(edge.id) &&
              !oldNodeIds.contains(edge.sourceNodeId) &&
              !oldNodeIds.contains(edge.targetNodeId),
        )
        .toList();
    final nextSource = source.copyWith(
      visible: false,
      payload: payload.copyWith(
        diagramType: 'flowchart',
        renderMode: MermaidRenderMode.native,
        conversionStatus: MermaidConversionStatus.converted,
        nativeNodeIds: result.nativeNodeIds,
        nativeEdgeIds: result.nativeEdgeIds,
        lastError: null,
      ),
    );
    final generatedNodes = _withMermaidZOrder(result.nodes, remainingNodes);
    final nextNodes = [
      for (final node in remainingNodes)
        node.id == source.id ? nextSource : node,
      ...generatedNodes,
    ];
    final nextEdges = [...remainingEdges, ...result.edges];
    _executeMermaidLifecycle(
      action: 'Regenerate',
      source: source,
      afterNodes: nextNodes,
      afterEdges: nextEdges,
    );
    return result;
  }

  MermaidConversionResult revertMermaidToSource(String nodeId) {
    final source = _mermaidSourceForNode(nodeId);
    if (source == null || source.id != nodeId) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'MERMAID_SOURCE_NOT_FOUND',
          message: 'The Mermaid source node could not be found.',
        ),
      );
    }
    final payload = source.payload as MermaidPayload;
    if (payload.renderMode != MermaidRenderMode.native) {
      return const MermaidConversionResult.failure(
        MermaidDiagnostic(
          code: 'NOT_NATIVE',
          message: 'This Mermaid node is already in source mode.',
          severity: MermaidDiagnosticSeverity.info,
        ),
      );
    }

    final nativeNodeIds = _ownedMermaidNodeIds(source);
    final nativeEdgeIds = _ownedMermaidEdgeIds(source);
    final nextSource = source.copyWith(
      visible: true,
      payload: payload.copyWith(
        renderMode: MermaidRenderMode.sourcePreview,
        conversionStatus: MermaidConversionStatus.notConverted,
        nativeNodeIds: const [],
        nativeEdgeIds: const [],
      ),
    );
    final nextNodes = [
      for (final node in state)
        if (node.id == source.id)
          nextSource
        else if (!nativeNodeIds.contains(node.id))
          node,
    ];
    final nextEdges = _ref
        .read(documentEdgesProvider)
        .where(
          (edge) =>
              !nativeEdgeIds.contains(edge.id) &&
              !nativeNodeIds.contains(edge.sourceNodeId) &&
              !nativeNodeIds.contains(edge.targetNodeId),
        )
        .toList();
    _executeMermaidLifecycle(
      action: 'Revert',
      source: source,
      afterNodes: nextNodes,
      afterEdges: nextEdges,
    );
    return const MermaidConversionResult();
  }

  void updateMermaidSource(String nodeId, MermaidPayload updatedPayload) {
    final source = _mermaidSourceForNode(nodeId);
    if (source == null || source.id != nodeId) return;
    final currentPayload = source.payload as MermaidPayload;
    if (MermaidSourceLimits.validate(updatedPayload.source) != null) return;
    if (currentPayload.renderMode != MermaidRenderMode.native ||
        updatedPayload.renderMode == MermaidRenderMode.native) {
      updateNode(source.copyWith(payload: updatedPayload));
      return;
    }

    final nativeNodeIds = currentPayload.nativeNodeIds.toSet();
    final nativeEdgeIds = currentPayload.nativeEdgeIds.toSet();
    final nextSource = source.copyWith(visible: true, payload: updatedPayload);
    final nextNodes = [
      for (final node in state)
        if (node.id == source.id)
          nextSource
        else if (!nativeNodeIds.contains(node.id))
          node,
    ];
    final nextEdges = _ref
        .read(documentEdgesProvider)
        .where(
          (edge) =>
              !nativeEdgeIds.contains(edge.id) &&
              !nativeNodeIds.contains(edge.sourceNodeId) &&
              !nativeNodeIds.contains(edge.targetNodeId),
        )
        .toList();
    _executeMermaidLifecycle(
      action: 'Edit Source',
      source: source,
      afterNodes: nextNodes,
      afterEdges: nextEdges,
    );
  }

  CanvasNode? _mermaidSourceForNode(String nodeId) {
    for (final node in state) {
      if (node.type != NodeType.mermaid || node.payload is! MermaidPayload) {
        continue;
      }
      if (node.id == nodeId || _ownedMermaidNodeIds(node).contains(nodeId)) {
        return node;
      }
    }
    return null;
  }

  Set<String> _ownedMermaidNodeIds(CanvasNode source) {
    final payload = source.payload as MermaidPayload;
    return payload.nativeNodeIds
        .where(
          (id) => state.any(
            (node) => node.id == id && _isOwnedMermaidNode(node, source.id, id),
          ),
        )
        .toSet();
  }

  Set<String> _ownedMermaidEdgeIds(CanvasNode source) {
    final payload = source.payload as MermaidPayload;
    final edges = _ref.read(documentEdgesProvider);
    return payload.nativeEdgeIds
        .where(
          (id) => edges.any(
            (edge) => edge.id == id && _isOwnedMermaidEdge(edge, source.id, id),
          ),
        )
        .toSet();
  }

  bool _isOwnedMermaidNode(CanvasNode node, String sourceId, String id) {
    final prefix = '${sourceId}__mermaid_node_';
    final generatedId =
        id.startsWith(prefix) &&
        int.tryParse(id.substring(prefix.length)) != null;
    return generatedId &&
        (node.mermaidSourceId == sourceId || node.mermaidSourceId == null);
  }

  bool _isOwnedMermaidEdge(CanvasEdge edge, String sourceId, String id) {
    final prefix = '${sourceId}__mermaid_edge_';
    final generatedId =
        id.startsWith(prefix) &&
        int.tryParse(id.substring(prefix.length)) != null;
    return generatedId &&
        (edge.mermaidSourceId == sourceId || edge.mermaidSourceId == null);
  }

  bool _hasMermaidIdConflict(
    MermaidConversionResult result, {
    Set<String> ignoring = const {},
  }) {
    final usedNodeIds = state.map((node) => node.id).toSet();
    final usedEdgeIds = _ref
        .read(documentEdgesProvider)
        .map((edge) => edge.id)
        .toSet();
    return result.nativeNodeIds.any(
          (id) => usedNodeIds.contains(id) && !ignoring.contains(id),
        ) ||
        result.nativeEdgeIds.any(
          (id) => usedEdgeIds.contains(id) && !ignoring.contains(id),
        );
  }

  List<CanvasNode> _withMermaidZOrder(
    List<CanvasNode> generated,
    List<CanvasNode> existing,
  ) {
    final nextZ = existing.isEmpty
        ? 0
        : existing.map((node) => node.zIndex).reduce(math.max) + 1;
    return [
      for (var index = 0; index < generated.length; index++)
        generated[index].copyWith(zIndex: nextZ + index),
    ];
  }

  void _executeMermaidLifecycle({
    required String action,
    required CanvasNode source,
    required List<CanvasNode> afterNodes,
    required List<CanvasEdge> afterEdges,
  }) {
    _ref.read(nodeHistoryProvider.notifier).recordSnapshot(source);
    executeCommand(
      MermaidLifecycleCommand(
        action: action,
        beforeNodes: List<CanvasNode>.unmodifiable(state),
        afterNodes: List<CanvasNode>.unmodifiable(afterNodes),
        beforeEdges: List<CanvasEdge>.unmodifiable(
          _ref.read(documentEdgesProvider),
        ),
        afterEdges: List<CanvasEdge>.unmodifiable(afterEdges),
      ),
    );
  }

  void addNode(CanvasNode node) {
    final maxZ = state.isEmpty
        ? 0
        : state.map((n) => n.zIndex).reduce(math.max) + 1;
    final nodeWithTopZ = node.copyWith(zIndex: maxZ);
    final pageScopedNode = nodeWithTopZ.pageId == null && _activePageId != null
        ? nodeWithTopZ.copyWith(pageId: _activePageId)
        : nodeWithTopZ;
    final resolved = _resolveContainingParent(pageScopedNode);
    executeCommand(CreateNodeCommand(resolved));
  }

  void reparentNodes() {
    final changedOld = <CanvasNode>[];
    final changedNew = <CanvasNode>[];
    for (final node in state) {
      if (node.type == NodeType.frame) continue;
      final parentId = _containingFrameId(node);
      if (parentId != node.parentId) {
        changedOld.add(node);
        changedNew.add(node.copyWith(parentId: parentId));
      }
    }
    if (changedOld.isNotEmpty) {
      executeCommand(
        ReassignParentCommand(
          childrenWithOldParent: changedOld,
          childrenWithNewParent: changedNew,
        ),
      );
    }

    // Auto-layout reflow for frames
    _reflowAutoLayoutFrames();
  }

  void _reflowAutoLayoutFrames() {
    final replacements = _autoLayoutReplacements(state);
    if (replacements.isEmpty) return;
    executeCommand(
      ReplaceNodesCommand(
        label: 'Reflow nested auto-layout',
        beforeNodes: replacements.map((entry) => entry.$1).toList(),
        afterNodes: replacements.map((entry) => entry.$2).toList(),
        beforeEdges: _ref.read(documentEdgesProvider),
        afterEdges: _ref.read(documentEdgesProvider),
      ),
    );
  }

  void applyAutoLayoutToFrame(String frameId) {
    state.firstWhere(
      (node) => node.id == frameId,
      orElse: () => throw Exception('Frame not found'),
    );
    final nextState = _reflowAutoLayoutState(state);
    final changes = _nodeChanges(state, nextState);
    if (changes.isEmpty) return;
    executeCommand(
      ReplaceNodesCommand(
        label: 'Apply auto-layout',
        beforeNodes: changes.map((change) => change.$1).toList(),
        afterNodes: changes.map((change) => change.$2).toList(),
        beforeEdges: _ref.read(documentEdgesProvider),
        afterEdges: _ref.read(documentEdgesProvider),
      ),
    );
  }

  void updateFrameLayout(String frameId, FramePayload nextPayload) {
    final frame = state.firstWhere(
      (node) => node.id == frameId && node.type == NodeType.frame,
      orElse: () => throw ArgumentError('Frame not found'),
    );
    final nextFrame = frame.copyWith(payload: nextPayload);
    final proposed = state
        .map((node) => node.id == frameId ? nextFrame : node)
        .toList(growable: false);
    final nextState = _reflowAutoLayoutState(proposed);
    final changes = _nodeChanges(state, nextState);
    if (changes.isEmpty) return;
    executeCommand(
      ReplaceNodesCommand(
        label: 'Update auto-layout',
        beforeNodes: changes.map((change) => change.$1).toList(),
        afterNodes: changes.map((change) => change.$2).toList(),
        beforeEdges: _ref.read(documentEdgesProvider),
        afterEdges: _ref.read(documentEdgesProvider),
      ),
    );
  }

  void applyLayoutPreset(String frameId, CanvasLayoutPreset preset) {
    final frame = state.firstWhere(
      (node) => node.id == frameId && node.type == NodeType.frame,
      orElse: () => throw ArgumentError('Frame not found'),
    );
    final payload = frame.payload;
    if (payload is! FramePayload) return;
    final children = state.where((node) => node.parentId == frameId).toList();
    if (children.isEmpty) return;

    final layout = AutoLayoutEngine.applyPreset(
      frameNode: frame,
      children: children,
      preset: preset,
    );
    final positionedById = {
      for (final child in layout.children) child.id: child,
    };
    final proposed = state
        .map(
          (node) => node.id == frameId
              ? frame.copyWith(payload: layout.framePayload)
              : positionedById[node.id] ?? node,
        )
        .toList(growable: false);
    final nextState = _reflowAutoLayoutState(proposed);
    final changes = _nodeChanges(state, nextState);
    if (changes.isEmpty) return;
    executeCommand(
      ReplaceNodesCommand(
        label: 'Apply layout preset',
        beforeNodes: changes.map((change) => change.$1).toList(),
        afterNodes: changes.map((change) => change.$2).toList(),
        beforeEdges: _ref.read(documentEdgesProvider),
        afterEdges: _ref.read(documentEdgesProvider),
      ),
    );
  }

  List<(CanvasNode, CanvasNode)> _autoLayoutReplacements(
    List<CanvasNode> source,
  ) {
    return _nodeChanges(source, _reflowAutoLayoutState(source));
  }

  List<(CanvasNode, CanvasNode)> _nodeChanges(
    Iterable<CanvasNode> before,
    Iterable<CanvasNode> after,
  ) {
    final beforeById = {for (final node in before) node.id: node};
    final changes = <(CanvasNode, CanvasNode)>[];
    for (final node in after) {
      final original = beforeById[node.id];
      if (original == null ||
          original.toJson().toString() == node.toJson().toString()) {
        continue;
      }
      changes.add((original, node));
    }
    return changes;
  }

  List<CanvasNode> _reflowAutoLayoutState(Iterable<CanvasNode> source) {
    final working = <String, CanvasNode>{
      for (final node in source) node.id: node,
    };
    final maxPasses = working.length + 2;
    for (var pass = 0; pass < maxPasses; pass++) {
      final byId = Map<String, CanvasNode>.from(working);
      final frames = working.values.where((node) {
        final payload = node.payload;
        return node.type == NodeType.frame &&
            payload is FramePayload &&
            payload.layoutDirection != AutoLayoutDirection.none;
      }).toList();
      frames.sort(
        (a, b) => CanvasSelectionMath.depthOf(
          a.id,
          byId,
        ).compareTo(CanvasSelectionMath.depthOf(b.id, byId)),
      );
      var changed = false;
      for (final frame in frames) {
        final currentFrame = working[frame.id] ?? frame;
        final children = working.values
            .where((node) => node.parentId == frame.id)
            .toList();
        if (children.isEmpty) continue;
        final (_, updatedChildren) = AutoLayoutEngine.applyLayout(
          frameNode: currentFrame,
          children: children,
        );
        for (final updated in updatedChildren) {
          final original = working[updated.id];
          if (original == null ||
              (original.x == updated.x && original.y == updated.y)) {
            continue;
          }
          working[updated.id] = updated;
          changed = true;
        }
      }
      if (!changed) break;
    }
    return working.values.toList(growable: false);
  }

  CanvasNode _resolveContainingParent(CanvasNode node) {
    if (node.type == NodeType.frame) return node;
    final parentId = _containingFrameId(node);
    if (parentId == null) return node;
    if (node.parentId != null) return node;
    return node.copyWith(parentId: parentId);
  }

  String? _containingFrameId(CanvasNode node) {
    String? closest;
    double closestArea = double.infinity;
    for (final f in state) {
      if (f.type != NodeType.frame || !f.visible) continue;
      final frameRect = Rect.fromLTWH(f.x, f.y, f.width, f.height);
      final center = Offset(node.x + node.width / 2, node.y + node.height / 2);
      if (frameRect.contains(center)) {
        final area = f.width * f.height;
        if (area < closestArea) {
          closestArea = area;
          closest = f.id;
        }
      }
    }
    return closest;
  }

  void deleteNodes(List<String> ids) {
    final deletedIds = CanvasSelectionMath.safeDeleteIds(ids, state);
    if (deletedIds.isEmpty) return;
    for (final node in state) {
      if (!deletedIds.contains(node.id) ||
          node.type != NodeType.mermaid ||
          node.payload is! MermaidPayload) {
        continue;
      }
      deletedIds.addAll(_ownedMermaidNodeIds(node));
    }
    final toDelete = state.where((n) => deletedIds.contains(n.id)).toList();
    if (toDelete.isEmpty) return;

    final currentEdges = _ref.read(documentEdgesProvider);
    final deletedEdges = currentEdges
        .where(
          (edge) =>
              deletedIds.contains(edge.sourceNodeId) ||
              deletedIds.contains(edge.targetNodeId),
        )
        .toList();
    final deletedEdgeIds = deletedEdges.map((edge) => edge.id).toSet();
    final updatedSources = <CanvasNode>[];
    final originalSources = <CanvasNode>[];
    for (final node in state) {
      if (deletedIds.contains(node.id) ||
          node.type != NodeType.mermaid ||
          node.payload is! MermaidPayload) {
        continue;
      }
      final payload = node.payload as MermaidPayload;
      final nativeNodeIds = _ownedMermaidNodeIds(node);
      final nativeEdgeIds = _ownedMermaidEdgeIds(node);
      if (!nativeNodeIds.any(deletedIds.contains) &&
          !nativeEdgeIds.any(deletedEdgeIds.contains)) {
        continue;
      }
      final remainingNodeIds = payload.nativeNodeIds
          .where((id) => nativeNodeIds.contains(id) && !deletedIds.contains(id))
          .toList();
      final remainingEdgeIds = payload.nativeEdgeIds
          .where(
            (id) => nativeEdgeIds.contains(id) && !deletedEdgeIds.contains(id),
          )
          .toList();
      originalSources.add(node);
      updatedSources.add(
        node.copyWith(
          payload: payload.copyWith(
            conversionStatus: remainingNodeIds.isEmpty
                ? MermaidConversionStatus.notConverted
                : MermaidConversionStatus.nativeEdited,
            renderMode: remainingNodeIds.isEmpty
                ? MermaidRenderMode.sourcePreview
                : MermaidRenderMode.native,
            nativeNodeIds: remainingNodeIds,
            nativeEdgeIds: remainingEdgeIds,
          ),
          visible: remainingNodeIds.isEmpty ? true : node.visible,
        ),
      );
    }

    // Keep group child references in sync when a child is deleted independently.
    for (final node in state) {
      if (deletedIds.contains(node.id) || node.payload is! GroupPayload) {
        continue;
      }
      final payload = node.payload as GroupPayload;
      final remaining = payload.childNodeIds
          .where((childId) => !deletedIds.contains(childId))
          .toList(growable: false);
      if (remaining.length == payload.childNodeIds.length) continue;
      originalSources.add(node);
      updatedSources.add(
        node.copyWith(payload: payload.copyWith(childNodeIds: remaining)),
      );
    }
    executeCommand(
      DeleteNodeCommand(
        toDelete,
        deletedEdges: deletedEdges,
        updatedNodes: updatedSources,
        originalUpdatedNodes: originalSources,
      ),
    );
    _ref
        .read(commentsProvider.notifier)
        .deleteForNodes(toDelete.map((node) => node.id).toList());
  }

  void deleteEdges(List<String> ids) {
    final deletedIds = ids.toSet();
    final toDelete = _ref
        .read(documentEdgesProvider)
        .where((edge) => deletedIds.contains(edge.id))
        .toList();
    if (toDelete.isEmpty) return;

    final updatedSources = <CanvasNode>[];
    final originalSources = <CanvasNode>[];
    for (final node in state) {
      if (node.type != NodeType.mermaid || node.payload is! MermaidPayload) {
        continue;
      }
      final payload = node.payload as MermaidPayload;
      final nativeEdgeIds = _ownedMermaidEdgeIds(node);
      if (payload.renderMode != MermaidRenderMode.native ||
          !nativeEdgeIds.any(deletedIds.contains)) {
        continue;
      }
      originalSources.add(node);
      updatedSources.add(
        node.copyWith(
          payload: payload.copyWith(
            conversionStatus: MermaidConversionStatus.nativeEdited,
            nativeEdgeIds: payload.nativeEdgeIds
                .where(
                  (id) =>
                      nativeEdgeIds.contains(id) && !deletedIds.contains(id),
                )
                .toList(),
          ),
        ),
      );
    }
    executeCommand(
      DeleteEdgesCommand(
        toDelete,
        updatedNodes: updatedSources,
        originalUpdatedNodes: originalSources,
      ),
    );
  }

  void moveNodes(List<String> ids, double dx, double dy) {
    if (dx == 0 && dy == 0) return;
    final idsWithChildren = _expandWithDescendants(ids);
    executeCommand(MoveNodeCommand(nodeIds: idsWithChildren, dx: dx, dy: dy));
  }

  void nudgeNodes(
    List<String> ids, {
    double dx = 0,
    double dy = 0,
    double step = 1,
  }) {
    if (dx == 0 && dy == 0) return;
    moveNodes(ids, dx * step, dy * step);
  }

  void resizeNodeFromHandle(
    String id, {
    required ResizeHandle handle,
    required Offset delta,
    bool lockAspect = false,
    bool fromCenter = false,
  }) {
    final node = state.where((candidate) => candidate.id == id).firstOrNull;
    if (node == null || node.locked) return;
    final rect = CanvasTransformEngine.resizeRect(
      original: node.bounds,
      handle: handle,
      delta: delta,
      lockAspect: lockAspect,
      fromCenter: fromCenter,
    );
    final resized = CanvasTransformEngine.scaleNodeContent(
      node,
      width: rect.width,
      height: rect.height,
    ).copyWith(x: rect.left, y: rect.top);
    applyNodeTransforms({id: resized}, historyName: 'Resize selection');
  }

  void rotateNodes(
    List<String> ids,
    double radians, {
    bool snapToQuarterTurns = false,
  }) {
    final targets = state
        .where((node) => ids.contains(node.id) && !node.locked)
        .toList(growable: false);
    if (targets.isEmpty || radians == 0) return;
    final rotated = CanvasTransformEngine.rotateSelection(
      targets,
      radians,
      snapToQuarterTurns: snapToQuarterTurns,
    );
    applyNodeTransforms(
      Map.fromIterables(targets.map((node) => node.id), rotated),
      historyName: 'Rotate selection',
    );
  }

  void applyNodeTransforms(
    Map<String, CanvasNode> replacements, {
    String historyName = 'Transform selection',
  }) {
    if (replacements.isEmpty) return;
    final before = <CanvasNode>[];
    final after = <CanvasNode>[];
    for (final entry in replacements.entries) {
      final current = state.where((node) => node.id == entry.key).firstOrNull;
      if (current == null || current.locked) continue;
      if (current.toJson().toString() == entry.value.toJson().toString()) {
        continue;
      }
      before.add(current);
      after.add(entry.value);
    }
    if (before.isEmpty) return;
    executeCommand(
      ReplaceNodesCommand(
        label: historyName,
        beforeNodes: before,
        afterNodes: after,
        beforeEdges: _ref.read(documentEdgesProvider),
        afterEdges: _ref.read(documentEdgesProvider),
      ),
    );
  }

  void renameNodes(Map<String, String> names) {
    final before = <CanvasNode>[];
    final after = <CanvasNode>[];
    for (final entry in names.entries) {
      final current = state.where((node) => node.id == entry.key).firstOrNull;
      final name = entry.value.trim();
      if (current == null || current.locked || name.isEmpty) continue;
      if (current.name == name) continue;
      before.add(current);
      after.add(current.copyWith(name: name));
    }
    if (before.isEmpty) return;
    executeCommand(
      ReplaceNodesCommand(
        label: 'Batch rename layers',
        beforeNodes: before,
        afterNodes: after,
        beforeEdges: _ref.read(documentEdgesProvider),
        afterEdges: _ref.read(documentEdgesProvider),
      ),
    );
  }

  void setLayerColor(Iterable<String> ids, int? color) {
    final before = <CanvasNode>[];
    final after = <CanvasNode>[];
    for (final node in state) {
      if (!ids.contains(node.id) || node.locked || node.layerColor == color) {
        continue;
      }
      before.add(node);
      after.add(node.copyWith(layerColor: color));
    }
    if (before.isEmpty) return;
    executeCommand(
      ReplaceNodesCommand(
        label: 'Set layer color',
        beforeNodes: before,
        afterNodes: after,
        beforeEdges: _ref.read(documentEdgesProvider),
        afterEdges: _ref.read(documentEdgesProvider),
      ),
    );
  }

  void updateNodes(
    Iterable<CanvasNode> replacements, {
    String historyName = 'Update selection',
    bool skipLocked = false,
  }) {
    final replacementById = {for (final node in replacements) node.id: node};
    if (replacementById.isEmpty) return;

    final before = <CanvasNode>[];
    final after = <CanvasNode>[];
    for (final node in state) {
      final replacement = replacementById[node.id];
      if (replacement == null || (skipLocked && node.locked)) continue;
      if (node.toJson().toString() == replacement.toJson().toString()) continue;
      before.add(node);
      after.add(replacement);
    }
    if (before.isEmpty) return;
    executeCommand(
      ReplaceNodesCommand(
        label: historyName,
        beforeNodes: before,
        afterNodes: after,
        beforeEdges: _ref.read(documentEdgesProvider),
        afterEdges: _ref.read(documentEdgesProvider),
      ),
    );
  }

  void setLocked(Iterable<String> ids, bool locked) {
    final idSet = ids.toSet();
    updateNodes(
      state
          .where((node) => idSet.contains(node.id))
          .map((node) => node.copyWith(locked: locked)),
      historyName: locked ? 'Lock selection' : 'Unlock selection',
    );
  }

  void setVisible(Iterable<String> ids, bool visible) {
    final idSet = ids.toSet();
    updateNodes(
      state
          .where((node) => idSet.contains(node.id))
          .map((node) => node.copyWith(visible: visible)),
      historyName: visible ? 'Show selection' : 'Hide selection',
    );
  }

  List<String> _expandWithDescendants(List<String> rootIds) {
    final all = state;
    final result = <String>{...rootIds};
    final byParent = <String, List<CanvasNode>>{};
    for (final n in all) {
      final p = n.parentId;
      if (p == null) continue;
      byParent.putIfAbsent(p, () => []).add(n);
    }
    var frontier = rootIds.toList();
    while (frontier.isNotEmpty) {
      final next = <String>[];
      for (final id in frontier) {
        for (final child in byParent[id] ?? const <CanvasNode>[]) {
          if (result.add(child.id)) {
            next.add(child.id);
          }
        }
      }
      frontier = next;
    }
    return result.toList();
  }

  void alignNodes(List<String> ids, AlignmentType alignment) {
    final targets = state.where((n) => ids.contains(n.id)).toList();
    if (targets.length <= 1) return;

    final aligned = AlignEngine.align(targets, alignment);
    executeCommand(
      AlignNodesCommand(previousNodes: targets, alignedNodes: aligned),
    );
  }

  void distributeNodes(List<String> ids, DistributionType type) {
    final targets = state.where((n) => ids.contains(n.id)).toList();
    if (targets.length <= 2) return;

    final distributed = AlignEngine.distribute(targets, type);
    executeCommand(
      AlignNodesCommand(previousNodes: targets, alignedNodes: distributed),
    );
  }

  String? groupNodes(List<String> ids) {
    final targets = state.where((n) => ids.contains(n.id)).toList();
    if (targets.length <= 1) return null;

    final bounds = AlignEngine.getSelectionBounds(targets);
    final groupId = const Uuid().v4();

    final groupNode = CanvasNode(
      id: groupId,
      type: NodeType.group,
      x: bounds.left,
      y: bounds.top,
      width: bounds.width,
      height: bounds.height,
      payload: GroupPayload(
        name: 'Group ${groupId.substring(0, 4)}',
        childNodeIds: targets.map((e) => e.id).toList(),
      ),
    );

    final updatedChildren = targets
        .map((c) => c.copyWith(parentId: groupId))
        .toList();

    executeCommand(
      GroupNodesCommand(
        groupNode: groupNode,
        originalChildren: targets,
        updatedChildren: updatedChildren,
      ),
    );

    return groupId;
  }

  void ungroupNodes(String groupId) {
    final groupNode = state.firstWhere(
      (n) => n.id == groupId && n.type == NodeType.group,
      orElse: () => throw ArgumentError('Group node not found'),
    );

    final children = state.where((n) => n.parentId == groupId).toList();
    final updatedChildren = children
        .map((c) => c.copyWith(parentId: null))
        .toList();

    executeCommand(
      UngroupNodesCommand(
        groupNode: groupNode,
        childrenWithParent: children,
        childrenWithoutParent: updatedChildren,
      ),
    );
  }

  List<String> duplicateNodes(List<String> ids) =>
      duplicateNodesWithMap(ids).values.toList(growable: false);

  Map<String, String> duplicateNodesWithMap(List<String> ids) {
    final targets = state.where((node) => ids.contains(node.id)).toList();
    if (targets.isEmpty) return const {};

    final targetIds = targets.map((node) => node.id).toSet();
    final idMap = <String, String>{};
    for (final node in targets) {
      idMap[node.id] = const Uuid().v4();
    }

    final baseZ = state.isEmpty
        ? 0
        : state.map((node) => node.zIndex).reduce(math.max) + 1;
    final newNodes = <CanvasNode>[];
    for (var index = 0; index < targets.length; index++) {
      final node = targets[index];
      var payload = node.payload.clone();
      if (payload is GroupPayload) {
        payload = payload.copyWith(
          childNodeIds: payload.childNodeIds
              .map((childId) => idMap[childId] ?? childId)
              .toList(growable: false),
        );
      }
      newNodes.add(
        node.copyWith(
          id: idMap[node.id],
          x: node.x + 20,
          y: node.y + 20,
          zIndex: baseZ + index,
          parentId: node.parentId == null
              ? null
              : idMap[node.parentId] ?? node.parentId,
          payload: payload,
        ),
      );
    }

    final newEdges = <CanvasEdge>[];
    final currentEdges = _ref.read(documentEdgesProvider);
    for (final edge in currentEdges) {
      if (!targetIds.contains(edge.sourceNodeId) ||
          !targetIds.contains(edge.targetNodeId)) {
        continue;
      }
      newEdges.add(
        edge.copyWith(
          id: const Uuid().v4(),
          sourceNodeId: idMap[edge.sourceNodeId],
          targetNodeId: idMap[edge.targetNodeId],
          parentId: edge.parentId == null
              ? null
              : idMap[edge.parentId] ?? edge.parentId,
          waypoints: edge.waypoints
              .map((point) => point + const Offset(20, 20))
              .toList(growable: false),
        ),
      );
    }

    executeCommand(CreateNodesCommand(nodes: newNodes, edges: newEdges));
    return Map<String, String>.unmodifiable(idMap);
  }

  void reorderRootNodes(int oldIndex, int newIndex) {
    // In Object Tree, index 0 represents the topmost visible layer (highest zIndex).
    // Get all root nodes in their current Object Tree display order:
    final byId = {for (final n in state) n.id: n};
    final roots =
        state
            .where((n) => n.parentId == null || !byId.containsKey(n.parentId))
            .toList()
          ..sort((a, b) => b.zIndex.compareTo(a.zIndex));

    if (oldIndex < 0 || oldIndex >= roots.length) return;
    if (newIndex < 0 || newIndex >= roots.length) return;
    if (oldIndex == newIndex) return;

    final moved = roots.removeAt(oldIndex);
    roots.insert(newIndex, moved);

    // Reassign zIndex so that index 0 gets highest zIndex, index N gets lowest zIndex
    final count = roots.length;
    final updatedRoots = <String, int>{};
    for (int i = 0; i < roots.length; i++) {
      updatedRoots[roots[i].id] = count - 1 - i;
    }

    final newNodes = state.map((n) {
      if (updatedRoots.containsKey(n.id)) {
        return n.copyWith(zIndex: updatedRoots[n.id]!);
      }
      return n;
    }).toList();

    executeCommand(
      ReorderNodeCommand(previousOrder: state, newOrder: newNodes),
    );
  }

  List<CanvasNode> _nodesByZIndex() {
    return List<CanvasNode>.from(state)
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
  }

  void _executeZOrder(List<CanvasNode> orderedNodes) {
    final newNodes = [
      for (int i = 0; i < orderedNodes.length; i++)
        orderedNodes[i].copyWith(zIndex: i),
    ];
    executeCommand(
      ReorderNodeCommand(previousOrder: state, newOrder: newNodes),
    );
  }

  void bringForward(String id) {
    final ordered = _nodesByZIndex();
    final index = ordered.indexWhere((n) => n.id == id);
    if (index < 0 || index >= ordered.length - 1) return;

    final item = ordered.removeAt(index);
    ordered.insert(index + 1, item);
    _executeZOrder(ordered);
  }

  void sendBackward(String id) {
    final ordered = _nodesByZIndex();
    final index = ordered.indexWhere((n) => n.id == id);
    if (index <= 0) return;

    final item = ordered.removeAt(index);
    ordered.insert(index - 1, item);
    _executeZOrder(ordered);
  }

  void bringToFront(String id) {
    final ordered = _nodesByZIndex();
    final index = ordered.indexWhere((n) => n.id == id);
    if (index < 0 || index == ordered.length - 1) return;

    final item = ordered.removeAt(index);
    ordered.add(item);
    _executeZOrder(ordered);
  }

  void sendToBack(String id) {
    final ordered = _nodesByZIndex();
    final index = ordered.indexWhere((n) => n.id == id);
    if (index <= 0) return;

    final item = ordered.removeAt(index);
    ordered.insert(0, item);
    _executeZOrder(ordered);
  }

  void toggleLock(List<String> ids) {
    final targets = state.where((n) => ids.contains(n.id)).toList();
    if (targets.isEmpty) return;
    setLocked(ids, targets.any((node) => !node.locked));
  }

  void toggleVisibility(List<String> ids) {
    final targets = state.where((n) => ids.contains(n.id)).toList();
    if (targets.isEmpty) return;
    setVisible(ids, targets.any((node) => !node.visible));
  }
}
