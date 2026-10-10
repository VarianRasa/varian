import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/ai_job.dart';
import '../../../domain/models/ai_artifact.dart';
import '../../../domain/models/durable_asset_reference.dart';
import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../../../domain/models/model3d_payload.dart';
import '../../canvas/commands/editor_commands.dart';
import '../../canvas/state/document_edges_provider.dart';
import '../../canvas/state/document_nodes_provider.dart';
import '../../canvas/utils/align_engine.dart';
import '../data/ai_service.dart';
import '../domain/ai_governance.dart';

/// The only canvas operations an assistant may request through this API.
///
/// The enum is deliberately smaller than [AICapability]. AI capabilities can
/// produce text or media, while these operations are the bounded local canvas
/// surface that is safe to expose to an assistant.
enum AICanvasActionType {
  summarizeNotes,
  generateDiagram,
  groupNodes,
  tidyNodes,
  suggestTitle,
  placeGeneratedOutput,
}

extension AICanvasActionTypeWireName on AICanvasActionType {
  String get wireName {
    switch (this) {
      case AICanvasActionType.summarizeNotes:
        return 'summarizeNotes';
      case AICanvasActionType.generateDiagram:
        return 'generateDiagram';
      case AICanvasActionType.groupNodes:
        return 'groupNodes';
      case AICanvasActionType.tidyNodes:
        return 'tidyNodes';
      case AICanvasActionType.suggestTitle:
        return 'suggestTitle';
      case AICanvasActionType.placeGeneratedOutput:
        return 'placeGeneratedOutput';
    }
  }

  bool get isMutation {
    switch (this) {
      case AICanvasActionType.summarizeNotes:
      case AICanvasActionType.suggestTitle:
        return false;
      case AICanvasActionType.generateDiagram:
      case AICanvasActionType.groupNodes:
      case AICanvasActionType.tidyNodes:
        return true;
      case AICanvasActionType.placeGeneratedOutput:
        return true;
    }
  }
}

/// A small, typed diagram request accepted by [AICanvasAction].
class AICanvasDiagramSpec {
  final String title;
  final Offset origin;

  AICanvasDiagramSpec({this.title = 'Flow', this.origin = Offset.zero}) {
    _validateTitle(title);
    _validateOffset(origin, field: 'origin');
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'origin': {'x': origin.dx, 'y': origin.dy},
  };
}

/// Bounded layout options accepted by the tidy action.
class AICanvasLayoutSpec {
  static const allowedStrategies = <String>{
    'smart_grid',
    'grid',
    'horizontal',
    'vertical',
    'align_left',
    'align_top',
  };

  final String strategy;
  final double gap;

  AICanvasLayoutSpec({this.strategy = 'smart_grid', this.gap = 40}) {
    if (!allowedStrategies.contains(strategy)) {
      throw AICanvasActionValidationException(
        'Unsupported canvas layout strategy: $strategy.',
      );
    }
    if (!gap.isFinite || gap < 0 || gap > 500) {
      throw const AICanvasActionValidationException(
        'Layout gap must be between 0 and 500.',
      );
    }
  }

  Map<String, dynamic> toJson() => {'strategy': strategy, 'gap': gap};
}

/// Typed representation of an allow-listed assistant action.
class AICanvasAction {
  final AICanvasActionType type;
  final List<String> selectionIds;
  final AICanvasDiagramSpec? diagram;
  final AICanvasLayoutSpec? layout;
  final AIJob? generatedJob;
  final Offset? outputPosition;
  final String? description;

  const AICanvasAction._({
    required this.type,
    this.selectionIds = const [],
    this.diagram,
    this.layout,
    this.generatedJob,
    this.outputPosition,
    this.description,
  });

  factory AICanvasAction.summarizeNotes({
    Iterable<String> selectionIds = const [],
    String? description,
  }) {
    return AICanvasAction._(
      type: AICanvasActionType.summarizeNotes,
      selectionIds: _normalizeIds(selectionIds),
      description: description,
    );
  }

  factory AICanvasAction.generateDiagram({
    String title = 'Flow',
    Offset origin = Offset.zero,
    String? description,
  }) {
    return AICanvasAction._(
      type: AICanvasActionType.generateDiagram,
      diagram: AICanvasDiagramSpec(title: title, origin: origin),
      description: description,
    );
  }

  factory AICanvasAction.groupNodes({
    required Iterable<String> selectionIds,
    String? description,
  }) {
    return AICanvasAction._(
      type: AICanvasActionType.groupNodes,
      selectionIds: _normalizeIds(selectionIds),
      description: description,
    );
  }

  /// Alias that mirrors the product language used by the canvas toolbar.
  factory AICanvasAction.groupSelectedNodes({
    required Iterable<String> selectionIds,
    String? description,
  }) => AICanvasAction.groupNodes(
    selectionIds: selectionIds,
    description: description,
  );

  factory AICanvasAction.tidyNodes({
    required Iterable<String> selectionIds,
    String strategy = 'smart_grid',
    double gap = 40,
    String? description,
  }) {
    return AICanvasAction._(
      type: AICanvasActionType.tidyNodes,
      selectionIds: _normalizeIds(selectionIds),
      layout: AICanvasLayoutSpec(strategy: strategy, gap: gap),
      description: description,
    );
  }

  /// Alias that mirrors the product language used by the canvas toolbar.
  factory AICanvasAction.tidySelectedNodes({
    required Iterable<String> selectionIds,
    String strategy = 'smart_grid',
    double gap = 40,
    String? description,
  }) => AICanvasAction.tidyNodes(
    selectionIds: selectionIds,
    strategy: strategy,
    gap: gap,
    description: description,
  );

  factory AICanvasAction.suggestTitle({
    Iterable<String> selectionIds = const [],
    String? description,
  }) {
    return AICanvasAction._(
      type: AICanvasActionType.suggestTitle,
      selectionIds: _normalizeIds(selectionIds),
      description: description,
    );
  }

  factory AICanvasAction.placeGeneratedOutput({
    required AIJob job,
    Offset position = const Offset(200, 200),
    String? description,
  }) {
    _validateOffset(position, field: 'position');
    return AICanvasAction._(
      type: AICanvasActionType.placeGeneratedOutput,
      selectionIds: _normalizeIds(job.sourceNodeIds),
      generatedJob: job,
      outputPosition: position,
      description: description,
    );
  }

  bool get isMutation => type.isMutation;

  /// Every operation that changes the document, plus title suggestions that
  /// may be applied by a caller, must cross a caller-owned confirmation
  /// boundary. The executor never treats an assistant proposal as implicit
  /// approval.
  bool get requiresConfirmation =>
      isMutation || type == AICanvasActionType.suggestTitle;

  /// Canonical action names plus the names emitted by existing AI jobs.
  static const allowedActionTypes = <String>{
    'summarizeNotes',
    'summarize_notes',
    'generateDiagram',
    'generate_diagram',
    'promptToDiagram',
    'prompt_to_diagram',
    'groupNodes',
    'groupSelection',
    'group_selected_nodes',
    'tidyNodes',
    'tidySelection',
    'tidy_selected_nodes',
    'suggestTitle',
    'suggest_title',
    'placeGeneratedOutput',
    'place_generated_output',
    'generatedOutput',
    'generated_output',
  };

  static bool isAllowedActionType(String raw) =>
      allowedActionTypes.contains(raw.trim());

  /// Parses an existing, untrusted assistant proposal into a typed action.
  factory AICanvasAction.fromAssistant(AIAssistantAction proposal) {
    final type = _typeFromWire(proposal.actionType);
    final payload = Map<String, dynamic>.from(proposal.payload);
    return _fromPayload(type, payload, description: proposal.description);
  }

  /// Parses a persisted/remote action object and rejects unknown shape data.
  factory AICanvasAction.fromJson(Map<String, dynamic> json) {
    final rawType = json['actionType'];
    if (rawType is! String || rawType.trim().isEmpty) {
      throw const AICanvasActionValidationException(
        'Canvas actionType must be a non-empty string.',
      );
    }
    final rawPayload = json['payload'];
    if (rawPayload != null && rawPayload is! Map) {
      throw const AICanvasActionValidationException(
        'Canvas action payload must be an object.',
      );
    }

    final payload = rawPayload == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(rawPayload as Map);
    final description = json['description'];
    if (description != null && description is! String) {
      throw const AICanvasActionValidationException(
        'Canvas action description must be text.',
      );
    }
    return _fromPayload(
      _typeFromWire(rawType),
      payload,
      description: description as String?,
    );
  }

  static AICanvasAction? tryParse(Map<String, dynamic> json) {
    try {
      return AICanvasAction.fromJson(json);
    } on AICanvasActionValidationException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{};
    if (selectionIds.isNotEmpty) payload['selectionIds'] = selectionIds;
    if (diagram != null) {
      payload.addAll(diagram!.toJson());
    }
    if (layout != null) payload.addAll(layout!.toJson());
    if (generatedJob != null) {
      payload['job'] = redactAIJobJson(generatedJob!);
      final position = outputPosition ?? const Offset(200, 200);
      payload['position'] = {'x': position.dx, 'y': position.dy};
    }
    return {
      'actionType': type.wireName,
      'payload': payload,
      if (description != null && description!.trim().isNotEmpty)
        'description': description,
    };
  }

  /// Validates references against the current local document before mutation.
  String? validateAgainstNodes(List<CanvasNode> nodes) {
    final byId = {for (final node in nodes) node.id: node};
    final unknown = selectionIds.where((id) => !byId.containsKey(id)).toList();
    if (unknown.isNotEmpty) {
      return 'Selection contains unknown node IDs.';
    }

    switch (type) {
      case AICanvasActionType.summarizeNotes:
        final targets = selectionIds.isEmpty
            ? nodes.where((node) => node.type == NodeType.stickyNote)
            : selectionIds.map((id) => byId[id]!);
        if (targets.any((node) => node.type != NodeType.stickyNote)) {
          return 'Summarize notes requires sticky-note selection.';
        }
        return null;
      case AICanvasActionType.generateDiagram:
        return diagram == null ? 'Diagram details are missing.' : null;
      case AICanvasActionType.groupNodes:
        if (selectionIds.length < 2) {
          return 'Select at least two nodes to group.';
        }
        return null;
      case AICanvasActionType.tidyNodes:
        if (selectionIds.length < 2) {
          return 'Select at least two nodes to tidy.';
        }
        return layout == null ? 'Layout details are missing.' : null;
      case AICanvasActionType.suggestTitle:
        return null;
      case AICanvasActionType.placeGeneratedOutput:
        final job = generatedJob;
        if (job == null) return 'Generated output details are missing.';
        if (job.status != AIJobStatus.completed) {
          return 'Generated output is not complete.';
        }
        if (!_hasGeneratedOutput(job)) {
          return 'Generated output does not contain a usable artifact.';
        }
        if (job.outputMode == AIOutputMode.replace && selectionIds.isEmpty) {
          return 'Replace output requires a source node.';
        }
        if (job.outputMode == AIOutputMode.replace &&
            !_canReplaceGeneratedOutput(byId[selectionIds.first]!, job)) {
          return 'This output cannot replace the selected node type.';
        }
        return null;
    }
  }

  static AICanvasAction _fromPayload(
    AICanvasActionType type,
    Map<String, dynamic> payload, {
    String? description,
  }) {
    switch (type) {
      case AICanvasActionType.summarizeNotes:
        _ensureKeys(payload, const {'selectionIds', 'nodeIds'});
        return AICanvasAction.summarizeNotes(
          selectionIds: _selectionIds(payload),
          description: description,
        );
      case AICanvasActionType.generateDiagram:
        _ensureKeys(payload, const {'title', 'prompt', 'origin', 'x', 'y'});
        final rawTitle = payload['title'] ?? payload['prompt'] ?? 'Flow';
        if (rawTitle is! String) {
          throw const AICanvasActionValidationException(
            'Diagram title must be text.',
          );
        }
        final origin = _offset(payload);
        return AICanvasAction.generateDiagram(
          title: rawTitle,
          origin: origin,
          description: description,
        );
      case AICanvasActionType.groupNodes:
        _ensureKeys(payload, const {'selectionIds', 'nodeIds'});
        return AICanvasAction.groupNodes(
          selectionIds: _selectionIds(payload),
          description: description,
        );
      case AICanvasActionType.tidyNodes:
        _ensureKeys(payload, const {
          'selectionIds',
          'nodeIds',
          'strategy',
          'layout',
          'align',
          'gap',
        });
        final rawStrategy =
            payload['strategy'] ?? payload['layout'] ?? payload['align'];
        if (rawStrategy != null && rawStrategy is! String) {
          throw const AICanvasActionValidationException(
            'Layout strategy must be text.',
          );
        }
        final strategy = _canonicalStrategy(rawStrategy as String?);
        final rawGap = payload['gap'];
        if (rawGap != null && rawGap is! num) {
          throw const AICanvasActionValidationException(
            'Layout gap must be numeric.',
          );
        }
        return AICanvasAction.tidyNodes(
          selectionIds: _selectionIds(payload),
          strategy: strategy,
          gap: (rawGap as num?)?.toDouble() ?? 40,
          description: description,
        );
      case AICanvasActionType.suggestTitle:
        _ensureKeys(payload, const {'selectionIds', 'nodeIds'});
        return AICanvasAction.suggestTitle(
          selectionIds: _selectionIds(payload),
          description: description,
        );
      case AICanvasActionType.placeGeneratedOutput:
        _ensureKeys(payload, const {'job', 'position', 'x', 'y'});
        final rawJob = payload['job'];
        if (rawJob is! Map) {
          throw const AICanvasActionValidationException(
            'Generated output job must be an object.',
          );
        }
        return AICanvasAction.placeGeneratedOutput(
          job: AIJob.fromJson(Map<String, dynamic>.from(rawJob)),
          position: _outputPosition(payload),
          description: description,
        );
    }
  }

  static AICanvasActionType _typeFromWire(String raw) {
    switch (raw.trim()) {
      case 'summarizeNotes':
      case 'summarize_notes':
        return AICanvasActionType.summarizeNotes;
      case 'generateDiagram':
      case 'generate_diagram':
      case 'promptToDiagram':
      case 'prompt_to_diagram':
        return AICanvasActionType.generateDiagram;
      case 'groupNodes':
      case 'groupSelection':
      case 'group_selected_nodes':
        return AICanvasActionType.groupNodes;
      case 'tidyNodes':
      case 'tidySelection':
      case 'tidy_selected_nodes':
        return AICanvasActionType.tidyNodes;
      case 'suggestTitle':
      case 'suggest_title':
        return AICanvasActionType.suggestTitle;
      case 'placeGeneratedOutput':
      case 'place_generated_output':
      case 'generatedOutput':
      case 'generated_output':
        return AICanvasActionType.placeGeneratedOutput;
      default:
        throw AICanvasActionValidationException(
          'Canvas action is not allow-listed: ${raw.trim()}.',
        );
    }
  }
}

class AICanvasActionValidationException implements Exception {
  final String message;

  const AICanvasActionValidationException(this.message);

  @override
  String toString() => message;
}

/// Result of an action request. A rejected result never changes document state.
class AICanvasActionResult {
  final String id;
  final AICanvasAction action;
  final AICanvasActionStatus status;
  final String? message;
  final String? text;
  final String? suggestedTitle;
  final AIJob? job;
  final List<CanvasNode> createdNodes;
  final List<CanvasEdge> createdEdges;
  final List<String> affectedNodeIds;

  AICanvasActionResult({
    required this.id,
    required this.action,
    required this.status,
    this.message,
    this.text,
    this.suggestedTitle,
    this.job,
    List<CanvasNode> createdNodes = const [],
    List<CanvasEdge> createdEdges = const [],
    List<String> affectedNodeIds = const [],
  }) : createdNodes = List.unmodifiable(createdNodes),
       createdEdges = List.unmodifiable(createdEdges),
       affectedNodeIds = List.unmodifiable(affectedNodeIds);

  bool get isSuccess => status == AICanvasActionStatus.completed;
  bool get didMutate =>
      createdNodes.isNotEmpty ||
      createdEdges.isNotEmpty ||
      affectedNodeIds.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'action': action.toJson(),
    'status': status.name,
    'message': message,
    'text': text,
    'suggestedTitle': suggestedTitle,
    'job': job?.toPersistenceJson(),
    'createdNodeIds': createdNodes.map((node) => node.id).toList(),
    'createdEdgeIds': createdEdges.map((edge) => edge.id).toList(),
    'affectedNodeIds': affectedNodeIds,
  };
}

class AICanvasActionPreview {
  final AICanvasAction action;
  final AICanvasActionStatus status;
  final String? message;
  final String? text;
  final String? suggestedTitle;
  final List<CanvasNode> plannedNodes;
  final List<CanvasEdge> plannedEdges;
  final List<String> affectedNodeIds;
  final String documentFingerprint;

  AICanvasActionPreview({
    required this.action,
    required this.status,
    this.message,
    this.text,
    this.suggestedTitle,
    List<CanvasNode> plannedNodes = const [],
    List<CanvasEdge> plannedEdges = const [],
    List<String> affectedNodeIds = const [],
    required this.documentFingerprint,
  }) : plannedNodes = List.unmodifiable(plannedNodes),
       plannedEdges = List.unmodifiable(plannedEdges),
       affectedNodeIds = List.unmodifiable(affectedNodeIds);

  bool get isValid => status != AICanvasActionStatus.rejected;
  bool get requiresConfirmation =>
      status == AICanvasActionStatus.confirmationRequired;
}

enum AICanvasActionStatus { completed, rejected, confirmationRequired, failed }

/// Executes typed actions against the existing document notifiers.
///
/// The executor is intentionally UI-independent. Callers decide when an
/// assistant proposal has been approved and pass [confirmed] only after that
/// explicit user boundary.
class AICanvasActionExecutor {
  final DocumentNodesNotifier nodesNotifier;
  final DocumentEdgesNotifier edgesNotifier;
  final AIService? aiService;
  final Future<CanvasNode> Function(CanvasNode node)? prepareGeneratedNode;
  final Future<void> Function({
    CanvasNode? originalNode,
    required CanvasNode preparedNode,
  })?
  publishPreparedGeneratedNode;
  final String projectId;
  final bool readOnly;
  final bool Function()? canEditCanvas;

  bool get _isReadOnly {
    if (readOnly) return true;
    final canEdit = canEditCanvas;
    if (canEdit == null) return false;
    try {
      return !canEdit();
    } catch (_) {
      return true;
    }
  }

  AICanvasActionExecutor({
    required this.nodesNotifier,
    required this.edgesNotifier,
    this.aiService,
    this.prepareGeneratedNode,
    this.publishPreparedGeneratedNode,
    this.projectId = 'local-canvas',
    this.readOnly = false,
    this.canEditCanvas,
  });

  Future<AICanvasActionResult> execute(
    AICanvasAction action, {
    bool confirmed = false,
    String? generatedOutputMode,
  }) async {
    final validation = action.validateAgainstNodes(nodesNotifier.nodes);
    if (validation != null) {
      return _result(
        action,
        AICanvasActionStatus.rejected,
        message: validation,
      );
    }
    if (_isReadOnly && action.isMutation) {
      return _result(
        action,
        AICanvasActionStatus.rejected,
        message: 'Canvas mutations are disabled in read-only mode.',
      );
    }
    if (action.requiresConfirmation && !confirmed) {
      return _result(
        action,
        AICanvasActionStatus.confirmationRequired,
        message:
            'Explicit confirmation is required before changing the canvas.',
      );
    }

    try {
      switch (action.type) {
        case AICanvasActionType.summarizeNotes:
          return await _summarizeNotes(action);
        case AICanvasActionType.generateDiagram:
          return _generateDiagram(action);
        case AICanvasActionType.groupNodes:
          return _groupNodes(action);
        case AICanvasActionType.tidyNodes:
          return _tidyNodes(action);
        case AICanvasActionType.suggestTitle:
          return _suggestTitle(action);
        case AICanvasActionType.placeGeneratedOutput:
          return await _placeGeneratedOutput(
            action,
            generatedOutputMode: generatedOutputMode,
          );
      }
    } on AICanvasActionValidationException catch (error) {
      return _result(
        action,
        AICanvasActionStatus.rejected,
        message: error.message,
      );
    } catch (error) {
      return _result(
        action,
        AICanvasActionStatus.failed,
        message: 'Canvas action failed: $error',
      );
    }
  }

  String get documentFingerprint => _fingerprint(nodesNotifier.nodes);

  Future<AICanvasActionPreview> preview(AICanvasAction action) async {
    final fingerprint = documentFingerprint;
    final validation = action.validateAgainstNodes(nodesNotifier.nodes);
    if (validation != null) {
      return AICanvasActionPreview(
        action: action,
        status: AICanvasActionStatus.rejected,
        message: validation,
        documentFingerprint: fingerprint,
      );
    }
    if (_isReadOnly && action.isMutation) {
      return AICanvasActionPreview(
        action: action,
        status: AICanvasActionStatus.rejected,
        message: 'Canvas mutations are disabled in read-only mode.',
        documentFingerprint: fingerprint,
      );
    }

    try {
      switch (action.type) {
        case AICanvasActionType.summarizeNotes:
          return _previewSummarizeNotes(action, fingerprint);
        case AICanvasActionType.generateDiagram:
          return _previewGenerateDiagram(action, fingerprint);
        case AICanvasActionType.groupNodes:
          return _previewGroupNodes(action, fingerprint);
        case AICanvasActionType.tidyNodes:
          return _previewTidyNodes(action, fingerprint);
        case AICanvasActionType.suggestTitle:
          return _previewSuggestTitle(action, fingerprint);
        case AICanvasActionType.placeGeneratedOutput:
          return _previewGeneratedOutput(action, fingerprint);
      }
    } on AICanvasActionValidationException catch (error) {
      return AICanvasActionPreview(
        action: action,
        status: AICanvasActionStatus.rejected,
        message: error.message,
        documentFingerprint: fingerprint,
      );
    } catch (error) {
      return AICanvasActionPreview(
        action: action,
        status: AICanvasActionStatus.failed,
        message: 'Canvas action preview failed: $error',
        documentFingerprint: fingerprint,
      );
    }
  }

  Future<AICanvasActionResult> executePreview(
    AICanvasActionPreview preview, {
    bool confirmed = false,
    String? generatedOutputMode,
  }) async {
    if (!preview.isValid) {
      return _result(
        preview.action,
        AICanvasActionStatus.rejected,
        message: preview.message ?? 'Canvas action preview is invalid.',
      );
    }
    if (_isReadOnly && preview.action.isMutation) {
      return _result(
        preview.action,
        AICanvasActionStatus.rejected,
        message: 'Canvas mutations are disabled in read-only mode.',
      );
    }
    if (preview.requiresConfirmation && !confirmed) {
      return _result(
        preview.action,
        AICanvasActionStatus.confirmationRequired,
        message:
            'Explicit confirmation is required before changing the canvas.',
      );
    }
    if (preview.documentFingerprint != documentFingerprint) {
      return _result(
        preview.action,
        AICanvasActionStatus.rejected,
        message: 'Canvas changed since this preview. Retry the action.',
      );
    }
    return execute(
      preview.action,
      confirmed: confirmed,
      generatedOutputMode: generatedOutputMode,
    );
  }

  Future<AICanvasActionResult> _placeGeneratedOutput(
    AICanvasAction action, {
    String? generatedOutputMode,
  }) async {
    final job = action.generatedJob!;
    final mode = switch (generatedOutputMode) {
      'insert' => AIOutputMode.insert,
      'replace' => AIOutputMode.replace,
      _ => job.outputMode,
    };
    final sourceId = action.selectionIds.firstOrNull;

    if (mode == AIOutputMode.replace) {
      final source = sourceId == null
          ? null
          : nodesNotifier.nodes
                .where((node) => node.id == sourceId)
                .firstOrNull;
      if (source == null) {
        return _result(
          action,
          AICanvasActionStatus.rejected,
          message: 'Replace output requires an existing source node.',
        );
      }
      if (!_canReplaceGeneratedOutput(source, job)) {
        return _result(
          action,
          AICanvasActionStatus.rejected,
          message: 'This output cannot replace the selected node type.',
        );
      }
      final generated = await _generatedNode(
        job,
        position: Offset(source.x, source.y),
        variantOfNodeId: source.variantOfNodeId,
      );
      if (generated == null) {
        return _result(
          action,
          AICanvasActionStatus.rejected,
          message: 'This output cannot replace the selected node type.',
        );
      }
      final replacementPayload = switch ((source.payload, generated.payload)) {
        (ImagePayload sourcePayload, ImagePayload generatedPayload) =>
          generatedPayload.copyWith(assetId: sourcePayload.assetId),
        (VideoPayload sourcePayload, VideoPayload generatedPayload) =>
          generatedPayload.copyWith(assetId: sourcePayload.assetId),
        (Model3DPayload sourcePayload, Model3DPayload generatedPayload) =>
          generatedPayload.copyWith(assetId: sourcePayload.assetId),
        _ => generated.payload,
      };
      final replacement = source.copyWith(
        name: generated.name,
        payload: replacementPayload,
      );
      final prepared = await _prepareGeneratedNode(replacement);
      if (_isReadOnly) {
        return _result(
          action,
          AICanvasActionStatus.rejected,
          message: 'Canvas mutations are disabled in read-only mode.',
        );
      }
      await _publishPreparedGeneratedNode(
        originalNode: source,
        preparedNode: prepared,
      );
      return _result(
        action,
        AICanvasActionStatus.completed,
        text: 'Replaced the selected node with generated output.',
        createdNodes: [prepared],
        affectedNodeIds: [source.id],
      );
    }

    final node = await _generatedNode(
      job,
      position: action.outputPosition ?? const Offset(200, 200),
      variantOfNodeId: sourceId,
    );
    if (node == null) {
      return _result(
        action,
        AICanvasActionStatus.rejected,
        message: 'Generated output does not contain a usable artifact.',
      );
    }
    final prepared = await _prepareGeneratedNode(node);
    if (_isReadOnly) {
      return _result(
        action,
        AICanvasActionStatus.rejected,
        message: 'Canvas mutations are disabled in read-only mode.',
      );
    }
    await _publishPreparedGeneratedNode(
      originalNode: null,
      preparedNode: prepared,
    );
    return _result(
      action,
      AICanvasActionStatus.completed,
      text: 'Inserted generated output into the canvas.',
      createdNodes: [prepared],
      affectedNodeIds: [prepared.id],
    );
  }

  Future<CanvasNode?> _generatedNode(
    AIJob job, {
    required Offset position,
    String? variantOfNodeId,
  }) async {
    final service = aiService;
    if (service == null) return null;
    if (job.resultArtifact?.kind == AIArtifactKind.model3d) {
      return service.spawnModel3DNodeFromJob(
        job,
        projectId: projectId,
        position: position,
        variantOfNodeId: variantOfNodeId,
      );
    }
    if (job.category == AICreativeCategory.videoAI) {
      return service.spawnVideoNodeFromJob(
        job,
        position: position,
        variantOfNodeId: variantOfNodeId,
      );
    }
    if (job.resultArtifact?.kind == AIArtifactKind.image &&
        validImageArtifactReference(job.resultArtifact?.reference) != null) {
      return service.spawnImageNodeFromJob(
        job,
        position: position,
        variantOfNodeId: variantOfNodeId,
      );
    }
    return null;
  }

  Future<CanvasNode> _prepareGeneratedNode(CanvasNode node) =>
      prepareGeneratedNode?.call(node) ?? Future<CanvasNode>.value(node);

  Future<void> _publishPreparedGeneratedNode({
    CanvasNode? originalNode,
    required CanvasNode preparedNode,
  }) async {
    final publisher = publishPreparedGeneratedNode;
    if (publisher != null) {
      await publisher(originalNode: originalNode, preparedNode: preparedNode);
      return;
    }
    if (originalNode == null) {
      nodesNotifier.executeCommand(CreateNodesCommand(nodes: [preparedNode]));
    } else {
      nodesNotifier.updateNode(preparedNode);
    }
  }

  Future<AICanvasActionResult> _summarizeNotes(AICanvasAction action) async {
    final byId = {for (final node in nodesNotifier.nodes) node.id: node};
    final notes = action.selectionIds.isEmpty
        ? nodesNotifier.nodes.where((node) => node.type == NodeType.stickyNote)
        : action.selectionIds.map((id) => byId[id]!);
    final noteTexts = notes
        .where((node) => node.payload is StickyNotePayload)
        .map((node) => (node.payload as StickyNotePayload).text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    final localSummary = noteTexts.isEmpty
        ? 'No sticky notes found on the selected nodes.'
        : noteTexts.join('\n');

    final processingJob = AIJob(
      id: const Uuid().v4(),
      projectId: projectId,
      capability: AICapability.summarizeNotes,
      prompt: _boundedPrompt(noteTexts),
      status: AIJobStatus.processing,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final service = aiService;
    if (service == null || noteTexts.isEmpty) {
      final completedJob = processingJob.copyWith(
        status: AIJobStatus.completed,
        isSimulated: true,
        resultText: localSummary,
        updatedAt: DateTime.now(),
      );
      return _result(
        action,
        AICanvasActionStatus.completed,
        text: localSummary,
        job: completedJob,
      );
    }

    final completedJob = await service.executeJob(
      processingJob,
      notes.toList(growable: false),
    );
    if (completedJob.status == AIJobStatus.failed) {
      return _result(
        action,
        AICanvasActionStatus.failed,
        message: completedJob.errorMessage ?? 'Could not summarize the notes.',
        job: completedJob,
      );
    }

    // Simulation mode intentionally returns the useful local summary instead
    // of the generic simulation string; configured providers may return prose.
    final resultText = completedJob.isSimulated
        ? localSummary
        : (completedJob.resultText?.trim().isNotEmpty == true
              ? completedJob.resultText!.trim()
              : localSummary);
    return _result(
      action,
      AICanvasActionStatus.completed,
      text: resultText,
      job: completedJob,
    );
  }

  AICanvasActionResult _generateDiagram(AICanvasAction action) {
    final diagram = action.diagram!;
    final (diagramNodes, diagramEdges) = AIService.buildGeneratedDiagram(
      diagram.title,
      diagram.origin,
    );
    final ids = diagramNodes.map((node) => node.id).toSet();
    if (diagramNodes.length != 3 ||
        diagramEdges.length != 2 ||
        diagramEdges.any(
          (edge) =>
              !ids.contains(edge.sourceNodeId) ||
              !ids.contains(edge.targetNodeId),
        )) {
      throw const AICanvasActionValidationException(
        'Generated diagram failed local edge validation.',
      );
    }

    nodesNotifier.executeCommand(
      CreateNodesCommand(nodes: diagramNodes, edges: diagramEdges),
    );
    return _result(
      action,
      AICanvasActionStatus.completed,
      text: 'Generated a connected three-node diagram.',
      createdNodes: diagramNodes,
      createdEdges: diagramEdges,
      affectedNodeIds: diagramNodes.map((node) => node.id).toList(),
    );
  }

  AICanvasActionResult _groupNodes(AICanvasAction action) {
    final groupId = nodesNotifier.groupNodes(action.selectionIds);
    if (groupId == null) {
      return _result(
        action,
        AICanvasActionStatus.rejected,
        message: 'Select at least two nodes to group.',
      );
    }
    return _result(
      action,
      AICanvasActionStatus.completed,
      text: 'Grouped ${action.selectionIds.length} nodes.',
      affectedNodeIds: [...action.selectionIds, groupId],
    );
  }

  AICanvasActionResult _tidyNodes(AICanvasAction action) {
    final byId = {for (final node in nodesNotifier.nodes) node.id: node};
    final selected = action.selectionIds.map((id) => byId[id]!).toList();
    final layout = _layout(selected, action.layout!);
    final changed = layout.any((node) {
      final previous = byId[node.id]!;
      return previous.x != node.x || previous.y != node.y;
    });
    if (changed) {
      nodesNotifier.executeCommand(
        AlignNodesCommand(previousNodes: selected, alignedNodes: layout),
      );
    }
    return _result(
      action,
      AICanvasActionStatus.completed,
      text: changed
          ? 'Tidied the selected nodes.'
          : 'Selection is already tidy.',
      affectedNodeIds: action.selectionIds,
    );
  }

  AICanvasActionResult _suggestTitle(AICanvasAction action) {
    final byId = {for (final node in nodesNotifier.nodes) node.id: node};
    final selected = action.selectionIds.isEmpty
        ? nodesNotifier.nodes
        : action.selectionIds.map((id) => byId[id]!);
    final labels = selected
        .map(_nodeLabel)
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toSet()
        .take(3)
        .toList();
    final title = labels.isEmpty
        ? 'Untitled Canvas'
        : labels.length == 1
        ? labels.first
        : labels.join(' · ');
    return _result(
      action,
      AICanvasActionStatus.completed,
      text: title,
      suggestedTitle: title,
    );
  }

  List<CanvasNode> _layout(List<CanvasNode> selected, AICanvasLayoutSpec spec) {
    final strategy = spec.strategy == 'grid' ? 'smart_grid' : spec.strategy;
    final bounds = AlignEngine.getSelectionBounds(selected);
    switch (strategy) {
      case 'align_left':
        return AlignEngine.align(selected, AlignmentType.left);
      case 'align_top':
        return AlignEngine.align(selected, AlignmentType.top);
      case 'horizontal':
        final sorted = List<CanvasNode>.from(
          selected,
        )..sort((a, b) => a.x == b.x ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
        final maxHeight = sorted.fold<double>(
          0,
          (max, node) => math.max(max, node.height),
        );
        var x = bounds.left;
        final arranged = <CanvasNode>[];
        for (final node in sorted) {
          arranged.add(
            node.copyWith(x: x, y: bounds.top + (maxHeight - node.height) / 2),
          );
          x += node.width + spec.gap;
        }
        return arranged;
      case 'vertical':
        final sorted = List<CanvasNode>.from(
          selected,
        )..sort((a, b) => a.y == b.y ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
        final maxWidth = sorted.fold<double>(
          0,
          (max, node) => math.max(max, node.width),
        );
        var y = bounds.top;
        final arranged = <CanvasNode>[];
        for (final node in sorted) {
          arranged.add(
            node.copyWith(x: bounds.left + (maxWidth - node.width) / 2, y: y),
          );
          y += node.height + spec.gap;
        }
        return arranged;
      case 'smart_grid':
        final sorted = List<CanvasNode>.from(
          selected,
        )..sort((a, b) => a.y == b.y ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
        final columns = math.max(1, math.sqrt(sorted.length).ceil());
        final maxWidth = sorted.fold<double>(
          0,
          (max, node) => math.max(max, node.width),
        );
        final maxHeight = sorted.fold<double>(
          0,
          (max, node) => math.max(max, node.height),
        );
        return [
          for (var index = 0; index < sorted.length; index++)
            sorted[index].copyWith(
              x: bounds.left + (index % columns) * (maxWidth + spec.gap),
              y: bounds.top + (index ~/ columns) * (maxHeight + spec.gap),
            ),
        ];
      default:
        throw AICanvasActionValidationException(
          'Unsupported canvas layout strategy: ${spec.strategy}.',
        );
    }
  }

  String _nodeLabel(CanvasNode node) {
    if (node.name?.trim().isNotEmpty == true) return node.name!.trim();
    if (node.payload is StickyNotePayload) {
      final text = (node.payload as StickyNotePayload).text.trim();
      if (text.isNotEmpty) return text.split('\n').first;
    }
    return node.type.name;
  }

  String _boundedPrompt(List<String> noteTexts) {
    final joined = noteTexts
        .map((text) => text.length > 1000 ? text.substring(0, 1000) : text)
        .join('\n');
    final prompt = 'Summarize the following selected sticky notes:\n$joined';
    return prompt.length > 10000 ? prompt.substring(0, 10000) : prompt;
  }

  AICanvasActionResult _result(
    AICanvasAction action,
    AICanvasActionStatus status, {
    String? message,
    String? text,
    String? suggestedTitle,
    AIJob? job,
    List<CanvasNode> createdNodes = const [],
    List<CanvasEdge> createdEdges = const [],
    List<String> affectedNodeIds = const [],
  }) => AICanvasActionResult(
    id: const Uuid().v4(),
    action: action,
    status: status,
    message: message,
    text: text,
    suggestedTitle: suggestedTitle,
    job: job,
    createdNodes: createdNodes,
    createdEdges: createdEdges,
    affectedNodeIds: affectedNodeIds,
  );

  AICanvasActionPreview _previewSummarizeNotes(
    AICanvasAction action,
    String fingerprint,
  ) {
    final byId = {for (final node in nodesNotifier.nodes) node.id: node};
    final notes = action.selectionIds.isEmpty
        ? nodesNotifier.nodes.where((node) => node.type == NodeType.stickyNote)
        : action.selectionIds.map((id) => byId[id]!);
    final noteTexts = notes
        .where((node) => node.payload is StickyNotePayload)
        .map((node) => (node.payload as StickyNotePayload).text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    final text = noteTexts.isEmpty
        ? 'No sticky notes found on the selected nodes.'
        : noteTexts.join('\n');
    return AICanvasActionPreview(
      action: action,
      status: AICanvasActionStatus.confirmationRequired,
      text: text,
      affectedNodeIds: notes.map((node) => node.id).toList(),
      documentFingerprint: fingerprint,
    );
  }

  AICanvasActionPreview _previewGenerateDiagram(
    AICanvasAction action,
    String fingerprint,
  ) {
    final diagram = action.diagram!;
    final (nodes, edges) = AIService.buildGeneratedDiagram(
      diagram.title,
      diagram.origin,
    );
    return AICanvasActionPreview(
      action: action,
      status: AICanvasActionStatus.confirmationRequired,
      text: 'Insert a connected three-node diagram.',
      plannedNodes: nodes,
      plannedEdges: edges,
      affectedNodeIds: nodes.map((node) => node.id).toList(),
      documentFingerprint: fingerprint,
    );
  }

  AICanvasActionPreview _previewGroupNodes(
    AICanvasAction action,
    String fingerprint,
  ) {
    final byId = {for (final node in nodesNotifier.nodes) node.id: node};
    final selected = action.selectionIds.map((id) => byId[id]!).toList();
    final bounds = AlignEngine.getSelectionBounds(selected);
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
        childNodeIds: selected.map((node) => node.id).toList(),
      ),
    );
    final updatedChildren = selected
        .map((node) => node.copyWith(parentId: groupId))
        .toList();
    return AICanvasActionPreview(
      action: action,
      status: AICanvasActionStatus.confirmationRequired,
      text: 'Group ${selected.length} selected nodes.',
      plannedNodes: [...updatedChildren, groupNode],
      affectedNodeIds: [...action.selectionIds, groupId],
      documentFingerprint: fingerprint,
    );
  }

  AICanvasActionPreview _previewTidyNodes(
    AICanvasAction action,
    String fingerprint,
  ) {
    final byId = {for (final node in nodesNotifier.nodes) node.id: node};
    final selected = action.selectionIds.map((id) => byId[id]!).toList();
    final layout = _layout(selected, action.layout!);
    return AICanvasActionPreview(
      action: action,
      status: AICanvasActionStatus.confirmationRequired,
      text: 'Tidy ${selected.length} selected nodes.',
      plannedNodes: layout,
      affectedNodeIds: action.selectionIds,
      documentFingerprint: fingerprint,
    );
  }

  AICanvasActionPreview _previewSuggestTitle(
    AICanvasAction action,
    String fingerprint,
  ) {
    final result = _suggestTitle(action);
    return AICanvasActionPreview(
      action: action,
      status: AICanvasActionStatus.confirmationRequired,
      text: result.text,
      suggestedTitle: result.suggestedTitle,
      affectedNodeIds: action.selectionIds,
      documentFingerprint: fingerprint,
    );
  }

  AICanvasActionPreview _previewGeneratedOutput(
    AICanvasAction action,
    String fingerprint,
  ) {
    final job = action.generatedJob!;
    final sourceId = action.selectionIds.firstOrNull;
    final source = sourceId == null
        ? null
        : nodesNotifier.nodes.where((node) => node.id == sourceId).firstOrNull;
    if (job.outputMode == AIOutputMode.replace && source == null) {
      return AICanvasActionPreview(
        action: action,
        status: AICanvasActionStatus.rejected,
        message: 'Replace output requires an existing source node.',
        documentFingerprint: fingerprint,
      );
    }
    if (source != null &&
        job.outputMode == AIOutputMode.replace &&
        !_canReplaceGeneratedOutput(source, job)) {
      return AICanvasActionPreview(
        action: action,
        status: AICanvasActionStatus.rejected,
        message: 'This output cannot replace the selected node type.',
        documentFingerprint: fingerprint,
      );
    }

    final position = source == null
        ? action.outputPosition ?? const Offset(200, 200)
        : Offset(source.x, source.y);
    final planned = _previewGeneratedNode(
      job,
      position: position,
      variantOfNodeId: source?.variantOfNodeId,
    );
    if (planned == null) {
      return AICanvasActionPreview(
        action: action,
        status: AICanvasActionStatus.rejected,
        message: 'This output cannot replace the selected node type.',
        documentFingerprint: fingerprint,
      );
    }

    final replacement = source == null
        ? planned
        : source.copyWith(name: planned.name, payload: planned.payload);
    final isReplace = job.outputMode == AIOutputMode.replace;
    return AICanvasActionPreview(
      action: action,
      status: AICanvasActionStatus.confirmationRequired,
      text: isReplace
          ? 'Replace the selected node with generated output.'
          : 'Insert generated output into the canvas.',
      plannedNodes: [replacement],
      affectedNodeIds: [replacement.id],
      documentFingerprint: fingerprint,
    );
  }

  CanvasNode? _previewGeneratedNode(
    AIJob job, {
    required Offset position,
    String? variantOfNodeId,
  }) {
    final artifact = job.resultArtifact;
    if (artifact?.kind == AIArtifactKind.model3d) {
      final reference = validModel3DArtifactReference(artifact?.reference);
      if (reference == null) return null;
      return CanvasNode(
        id: const Uuid().v4(),
        type: NodeType.model3d,
        x: position.dx,
        y: position.dy,
        width: 320,
        height: 240,
        name:
            'AI 3D: ${job.prompt.isNotEmpty ? job.prompt : 'Generated Model'}',
        variantOfNodeId: variantOfNodeId,
        payload: Model3DPayload(
          fileName: artifact?.fileName?.trim().isNotEmpty == true
              ? artifact!.fileName!.trim()
              : 'generated-model.glb',
          fileSizeText: _formatArtifactSize(artifact?.byteLength),
          modelUrl: null,
          artifactReference: reference,
        ),
      );
    }
    if (job.category == AICreativeCategory.videoAI) {
      final reference = validVideoArtifactReference(
        job.resultArtifact?.kind == AIArtifactKind.video
            ? job.resultArtifact?.reference
            : job.resultVideoReference,
      );
      if (reference == null) return null;
      return CanvasNode(
        id: const Uuid().v4(),
        type: NodeType.videoCard,
        x: position.dx,
        y: position.dy,
        width: 540,
        height: 320,
        name:
            'AI Video: ${job.prompt.isNotEmpty ? job.prompt : job.capability.name}',
        variantOfNodeId: variantOfNodeId,
        payload: VideoPayload(
          title: job.prompt.isNotEmpty ? job.prompt : 'AI Generated Video',
          videoPath: null,
          videoUrl: null,
          videoArtifactReference: reference,
          isPlaying: false,
        ),
      );
    }
    final reference = validImageArtifactReference(
      job.resultArtifact?.kind == AIArtifactKind.image
          ? job.resultArtifact?.reference
          : null,
    );
    if (reference == null) return null;
    return CanvasNode(
      id: const Uuid().v4(),
      type: NodeType.image,
      x: position.dx,
      y: position.dy,
      width: 480,
      height: 360,
      name: 'AI: ${job.prompt.isNotEmpty ? job.prompt : job.capability.name}',
      variantOfNodeId: variantOfNodeId,
      payload: ImagePayload(imageArtifactReference: reference),
    );
  }

  String _fingerprint(List<CanvasNode> nodes) => nodes
      .map(
        (node) =>
            '${node.id}|${node.x}|${node.y}|${node.width}|${node.height}|${node.parentId}|${node.zIndex}',
      )
      .join('||');
}

class AICanvasActionState {
  final bool isExecuting;
  final AICanvasActionResult? lastResult;
  final List<AICanvasActionResult> history;

  const AICanvasActionState({
    this.isExecuting = false,
    this.lastResult,
    this.history = const [],
  });

  AICanvasActionState copyWith({
    bool? isExecuting,
    AICanvasActionResult? lastResult,
    List<AICanvasActionResult>? history,
  }) => AICanvasActionState(
    isExecuting: isExecuting ?? this.isExecuting,
    lastResult: lastResult ?? this.lastResult,
    history: history ?? this.history,
  );
}

/// Riverpod entry point used by UI integrations. UI code submits typed actions
/// here instead of mutating document providers directly.
class AICanvasActionsNotifier extends StateNotifier<AICanvasActionState> {
  final Ref _ref;

  AICanvasActionsNotifier(this._ref) : super(const AICanvasActionState());

  Future<AICanvasActionResult> execute(
    AICanvasAction action, {
    String projectId = 'local-canvas',
    bool confirmed = false,
    bool readOnly = false,
  }) async {
    state = state.copyWith(isExecuting: true);
    final executor = AICanvasActionExecutor(
      nodesNotifier: _ref.read(documentNodesProvider.notifier),
      edgesNotifier: _ref.read(documentEdgesProvider.notifier),
      aiService: _ref.read(aiServiceProvider),
      projectId: projectId,
      readOnly: readOnly,
    );
    final result = await executor.execute(action, confirmed: confirmed);
    final history = [result, ...state.history];
    state = state.copyWith(
      isExecuting: false,
      lastResult: result,
      history: history.length > 20 ? history.sublist(0, 20) : history,
    );
    return result;
  }

  Future<AICanvasActionResult> executeAssistantAction(
    AIAssistantAction proposal, {
    String projectId = 'local-canvas',
    bool confirmed = false,
    bool readOnly = false,
  }) async {
    try {
      final action = AICanvasAction.fromAssistant(proposal);
      return await execute(
        action,
        projectId: projectId,
        confirmed: confirmed,
        readOnly: readOnly,
      );
    } on AICanvasActionValidationException catch (error) {
      final action = AICanvasAction.suggestTitle(
        description: proposal.description,
      );
      final result = AICanvasActionResult(
        id: const Uuid().v4(),
        action: action,
        status: AICanvasActionStatus.rejected,
        message: error.message,
      );
      state = state.copyWith(
        lastResult: result,
        history: [result, ...state.history].take(20).toList(),
      );
      return result;
    }
  }
}

final aiCanvasActionsProvider =
    StateNotifierProvider<AICanvasActionsNotifier, AICanvasActionState>((ref) {
      return AICanvasActionsNotifier(ref);
    });

String _canonicalStrategy(String? raw) {
  final strategy = raw?.trim().isEmpty == true ? null : raw?.trim();
  switch (strategy) {
    case null:
      return 'smart_grid';
    case 'smart-grid':
    case 'smartGrid':
      return 'smart_grid';
    case 'alignLeft':
      return 'align_left';
    case 'alignTop':
      return 'align_top';
    case 'smart_grid':
    case 'grid':
    case 'horizontal':
    case 'vertical':
    case 'align_left':
    case 'align_top':
      return strategy;
    default:
      throw AICanvasActionValidationException(
        'Unsupported canvas layout strategy: $strategy.',
      );
  }
}

List<String> _selectionIds(Map<String, dynamic> payload) {
  final raw = payload['selectionIds'] ?? payload['nodeIds'];
  if (raw == null) return const [];
  if (raw is! List) {
    throw const AICanvasActionValidationException(
      'Selection IDs must be an array of strings.',
    );
  }
  return _normalizeIds(raw);
}

List<String> _normalizeIds(Iterable<dynamic> ids) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in ids) {
    if (raw is! String) {
      throw const AICanvasActionValidationException(
        'Selection IDs must be strings.',
      );
    }
    final id = raw.trim();
    if (id.isEmpty || id.length > 200) {
      throw const AICanvasActionValidationException(
        'Selection IDs must be non-empty and at most 200 characters.',
      );
    }
    if (!seen.add(id)) {
      throw const AICanvasActionValidationException(
        'Selection IDs must not contain duplicates.',
      );
    }
    result.add(id);
    if (result.length > 100) {
      throw const AICanvasActionValidationException(
        'An AI canvas action may target at most 100 nodes.',
      );
    }
  }
  return List.unmodifiable(result);
}

void _ensureKeys(Map<String, dynamic> payload, Set<String> allowed) {
  final unknown = payload.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw AICanvasActionValidationException(
      'Canvas action payload contains unsupported fields: ${unknown.join(', ')}.',
    );
  }
}

Offset _offset(Map<String, dynamic> payload) {
  final rawOrigin = payload['origin'];
  if (rawOrigin != null && rawOrigin is! Map) {
    throw const AICanvasActionValidationException(
      'Diagram origin must be an object.',
    );
  }
  final origin = rawOrigin == null
      ? const <String, dynamic>{}
      : Map<String, dynamic>.from(rawOrigin as Map);
  final rawX = payload['x'] ?? origin['x'] ?? 0;
  final rawY = payload['y'] ?? origin['y'] ?? 0;
  if (rawX is! num || rawY is! num) {
    throw const AICanvasActionValidationException(
      'Diagram origin coordinates must be numeric.',
    );
  }
  final result = Offset(rawX.toDouble(), rawY.toDouble());
  _validateOffset(result, field: 'origin');
  return result;
}

void _validateTitle(String value) {
  final title = value.trim();
  if (title.isEmpty || title.length > 120) {
    throw const AICanvasActionValidationException(
      'Canvas action title must be between 1 and 120 characters.',
    );
  }
}

void _validateOffset(Offset value, {required String field}) {
  if (!value.dx.isFinite ||
      !value.dy.isFinite ||
      value.dx.abs() > 1000000 ||
      value.dy.abs() > 1000000) {
    throw AICanvasActionValidationException(
      'Canvas action $field coordinates are out of range.',
    );
  }
}

bool _hasGeneratedOutput(AIJob job) {
  final artifact = job.resultArtifact;
  if (artifact?.kind == AIArtifactKind.model3d) {
    return validModel3DArtifactReference(artifact?.reference) != null;
  }
  if (job.category == AICreativeCategory.videoAI) {
    return validVideoArtifactReference(
          artifact?.kind == AIArtifactKind.video
              ? artifact?.reference
              : job.resultVideoReference,
        ) !=
        null;
  }
  return job.resultArtifact?.kind == AIArtifactKind.image &&
      validImageArtifactReference(job.resultArtifact?.reference) != null;
}

bool _canReplaceGeneratedOutput(CanvasNode source, AIJob job) {
  if (job.resultArtifact?.kind == AIArtifactKind.model3d) {
    return source.type == NodeType.model3d;
  }
  if (job.category == AICreativeCategory.videoAI) {
    return source.type == NodeType.videoCard;
  }
  return source.type == NodeType.image;
}

Offset _outputPosition(Map<String, dynamic> payload) {
  final rawPosition = payload['position'];
  if (rawPosition != null && rawPosition is! Map) {
    throw const AICanvasActionValidationException(
      'Generated output position must be an object.',
    );
  }
  final position = rawPosition == null
      ? const <String, dynamic>{}
      : Map<String, dynamic>.from(rawPosition as Map);
  final rawX = payload['x'] ?? position['x'] ?? 200;
  final rawY = payload['y'] ?? position['y'] ?? 200;
  if (rawX is! num || rawY is! num) {
    throw const AICanvasActionValidationException(
      'Generated output position coordinates must be numeric.',
    );
  }
  final result = Offset(rawX.toDouble(), rawY.toDouble());
  _validateOffset(result, field: 'position');
  return result;
}

String _formatArtifactSize(int? byteLength) {
  if (byteLength == null || byteLength < 1) return '0 B';
  if (byteLength < 1024) return '$byteLength B';
  if (byteLength < 1024 * 1024) {
    return '${(byteLength / 1024).toStringAsFixed(1)} KB';
  }
  if (byteLength < 1024 * 1024 * 1024) {
    return '${(byteLength / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(byteLength / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
