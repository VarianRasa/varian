import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/local_storage_service.dart';
import '../../../domain/models/ai_job.dart';
import '../../../domain/models/document_asset.dart';
import '../../../domain/models/durable_asset_reference.dart';
import '../../../domain/models/model3d_payload.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../../../features/assets/data/asset_service.dart';
import '../../../features/canvas/commands/editor_commands.dart';
import '../../../features/canvas/domain/document_asset_registry.dart';
import '../../../features/canvas/state/document_assets_provider.dart';
import '../../canvas/state/document_edges_provider.dart';
import '../../canvas/state/document_nodes_provider.dart';
import '../data/ai_canvas_actions.dart';
import '../data/ai_service.dart';
import '../domain/ai_canvas_transaction.dart';

final aiCanvasTransactionProvider =
    StateNotifierProvider.family<
      AICanvasTransactionNotifier,
      AICanvasTransactionState,
      String
    >((ref, projectId) {
      return AICanvasTransactionNotifier(ref, projectId);
    });

class AICanvasTransactionNotifier
    extends StateNotifier<AICanvasTransactionState> {
  final Ref _ref;
  final LocalStorageService _storage;
  final String projectId;
  final Set<String> _cancelRequested = <String>{};
  final Map<String, void Function(CanvasNode node)> _nodeCallbacks = {};
  final Map<String, Uint8List> _transientGeneratedBytes = {};
  final Map<String, DocumentAsset> _preparedGeneratedAssets = {};
  late final Future<void> ready;

  AICanvasTransactionNotifier(
    this._ref,
    this.projectId, {
    LocalStorageService? storage,
  }) : _storage = storage ?? LocalStorageService(),
       super(const AICanvasTransactionState()) {
    ready = load();
  }

  Future<void> load() async {
    try {
      final entries = await _storage.loadAICanvasTransactions(projectId);
      if (mounted) {
        state = AICanvasTransactionState(isLoading: false, entries: entries);
      }
    } catch (error) {
      if (mounted) {
        state = AICanvasTransactionState(
          isLoading: false,
          error: error.toString(),
        );
      }
    }
  }

  Future<AICanvasTransactionEntry?> previewAction(
    AICanvasAction action, {
    String? transactionId,
  }) async {
    await ready;
    final executor = _executor(action: action);
    final preview = await executor.preview(action);
    final now = DateTime.now();
    final entry = AICanvasTransactionEntry(
      id: transactionId ?? const Uuid().v4(),
      projectId: projectId,
      action: action,
      preview: preview,
      phase: preview.isValid
          ? AICanvasTransactionPhase.preview
          : AICanvasTransactionPhase.rejected,
      resultStatus: preview.isValid ? null : preview.status,
      message: preview.message,
      text: preview.text,
      suggestedTitle: preview.suggestedTitle,
      affectedNodeIds: preview.affectedNodeIds,
      createdAt: now,
      updatedAt: now,
    );
    _replaceEntry(entry);
    await _persist();
    return entry;
  }

  Future<AICanvasTransactionEntry?> stageAssistantAction(
    AIAssistantAction proposal,
  ) async {
    try {
      final action = AICanvasAction.fromAssistant(proposal);
      return await previewAction(action);
    } on AICanvasActionValidationException {
      return null;
    }
  }

  Future<AICanvasTransactionEntry?> stageGeneratedJob(
    AIJob job, {
    Offset? position,
    String? description,
    void Function(CanvasNode node)? onNodeCreated,
  }) =>
      previewAction(
        AICanvasAction.placeGeneratedOutput(
          job: job,
          position: position ?? const Offset(200, 200),
          description: description,
        ),
        transactionId: 'ai-output-${job.id}',
      ).then((entry) {
        if (entry != null && onNodeCreated != null) {
          _nodeCallbacks[entry.id] = onNodeCreated;
        }
        return entry;
      });

  Future<AICanvasActionResult?> apply(
    String transactionId, {
    AICanvasTransactionOperation operation = AICanvasTransactionOperation.apply,
    bool Function()? canEditCanvas,
  }) async {
    final entry = _find(transactionId);
    if (entry == null || !entry.canApply || state.isExecuting) return null;
    return _run(entry, operation: operation, canEditCanvas: canEditCanvas);
  }

  Future<AICanvasActionResult?> insert(
    String transactionId, {
    bool Function()? canEditCanvas,
  }) => apply(
    transactionId,
    operation: AICanvasTransactionOperation.insert,
    canEditCanvas: canEditCanvas,
  );

  Future<AICanvasActionResult?> replace(
    String transactionId, {
    bool Function()? canEditCanvas,
  }) => apply(
    transactionId,
    operation: AICanvasTransactionOperation.replace,
    canEditCanvas: canEditCanvas,
  );

  Future<AICanvasActionResult?> retry(String transactionId) async {
    final entry = _find(transactionId);
    if (entry == null || !entry.phase.canRetry || state.isExecuting) {
      return null;
    }
    return _run(
      entry,
      operation: AICanvasTransactionOperation.retry,
      attempts: entry.attempts + 1,
    );
  }

  Future<void> reject(String transactionId) async {
    final entry = _find(transactionId);
    if (entry == null || entry.phase.isTerminal) return;
    await _finishWithoutExecution(
      entry,
      phase: AICanvasTransactionPhase.rejected,
      operation: AICanvasTransactionOperation.reject,
      message: 'Action rejected by the user.',
    );
  }

  Future<void> cancel(String transactionId) async {
    final entry = _find(transactionId);
    if (entry == null || entry.phase.isTerminal) return;
    if (state.isExecuting && entry.phase != AICanvasTransactionPhase.preview) {
      _cancelRequested.add(transactionId);
    }
    await _finishWithoutExecution(
      entry,
      phase: AICanvasTransactionPhase.canceled,
      operation: AICanvasTransactionOperation.cancel,
      message: 'Action canceled by the user.',
    );
  }

  Future<bool> undo(String transactionId) async {
    final entry = _find(transactionId);
    final currentUndoDepth = _ref.read(historyProvider).undoStack.length;
    if (entry == null ||
        !entry.phase.canUndo ||
        entry.undoDepth == null ||
        entry.undoDepth != currentUndoDepth) {
      return false;
    }
    _ref.read(documentNodesProvider.notifier).undo();
    final updated = entry.copyWith(
      phase: AICanvasTransactionPhase.undone,
      operation: AICanvasTransactionOperation.undo,
      undoDepth: null,
      message: 'Canvas transaction undone.',
      updatedAt: DateTime.now(),
    );
    _replaceEntry(updated);
    await _persist();
    return true;
  }

  Future<void> clearHistory() async {
    state = state.copyWith(entries: const [], error: null);
    await _storage.clearAICanvasTransactions(projectId);
  }

  Future<AICanvasActionResult?> _run(
    AICanvasTransactionEntry entry, {
    required AICanvasTransactionOperation operation,
    int? attempts,
    bool Function()? canEditCanvas,
  }) async {
    var working = entry.copyWith(
      phase: operation == AICanvasTransactionOperation.retry
          ? AICanvasTransactionPhase.retrying
          : AICanvasTransactionPhase.applying,
      operation: operation,
      attempts: attempts,
      updatedAt: DateTime.now(),
      message: null,
    );
    _replaceEntry(working);
    state = state.copyWith(isExecuting: true, error: null);
    await _persist();

    final executor = _executor(
      action: working.action,
      canEditCanvas: canEditCanvas,
    );
    var preview = working.preview;
    if (preview == null) {
      preview = await executor.preview(working.action);
      working = working.copyWith(
        preview: preview,
        affectedNodeIds: preview.affectedNodeIds,
        text: preview.text,
        suggestedTitle: preview.suggestedTitle,
        updatedAt: DateTime.now(),
      );
      _replaceEntry(working);
    }

    if (_cancelRequested.remove(entry.id)) {
      state = state.copyWith(isExecuting: false);
      await _persist();
      return null;
    }

    final historyDepthBefore = _ref.read(historyProvider).undoStack.length;
    final result = await executor.executePreview(
      preview,
      confirmed: true,
      generatedOutputMode: _generatedOutputMode(operation),
    );
    final canceled = _cancelRequested.remove(entry.id);
    final historyDepthAfter = _ref.read(historyProvider).undoStack.length;
    final phase = _phaseForResult(result, operation, canceled);
    final updated = working.copyWith(
      phase: phase,
      resultStatus: result.status,
      resultId: result.id,
      message: canceled && !result.didMutate
          ? 'Action canceled by the user.'
          : result.message,
      text: result.text ?? working.text,
      suggestedTitle: result.suggestedTitle ?? working.suggestedTitle,
      affectedNodeIds: result.affectedNodeIds.isEmpty
          ? working.affectedNodeIds
          : result.affectedNodeIds,
      undoDepth: result.isSuccess && historyDepthAfter > historyDepthBefore
          ? historyDepthAfter
          : null,
      updatedAt: DateTime.now(),
    );
    _replaceEntry(updated);
    final callback = result.isSuccess ? _nodeCallbacks.remove(entry.id) : null;
    if (callback != null) {
      for (final node in result.createdNodes) {
        callback(node);
      }
    }
    state = state.copyWith(isExecuting: false);
    await _persist();
    return result;
  }

  AICanvasTransactionPhase _phaseForResult(
    AICanvasActionResult result,
    AICanvasTransactionOperation operation,
    bool canceled,
  ) {
    if (canceled && !result.didMutate) return AICanvasTransactionPhase.canceled;
    if (result.status == AICanvasActionStatus.rejected ||
        result.status == AICanvasActionStatus.confirmationRequired) {
      return AICanvasTransactionPhase.rejected;
    }
    if (result.status != AICanvasActionStatus.completed) {
      return AICanvasTransactionPhase.failed;
    }
    switch (operation) {
      case AICanvasTransactionOperation.insert:
        return AICanvasTransactionPhase.inserted;
      case AICanvasTransactionOperation.replace:
        return AICanvasTransactionPhase.replaced;
      default:
        if (result.action.type == AICanvasActionType.placeGeneratedOutput) {
          return result.action.generatedJob?.outputMode == AIOutputMode.replace
              ? AICanvasTransactionPhase.replaced
              : AICanvasTransactionPhase.inserted;
        }
        return AICanvasTransactionPhase.applied;
    }
  }

  Future<void> _finishWithoutExecution(
    AICanvasTransactionEntry entry, {
    required AICanvasTransactionPhase phase,
    required AICanvasTransactionOperation operation,
    required String message,
  }) async {
    final updated = entry.copyWith(
      phase: phase,
      operation: operation,
      message: message,
      updatedAt: DateTime.now(),
    );
    _replaceEntry(updated);
    if (phase == AICanvasTransactionPhase.canceled ||
        phase == AICanvasTransactionPhase.rejected) {
      _nodeCallbacks.remove(entry.id);
    }
    await _persist();
  }

  AICanvasTransactionEntry? _find(String id) {
    for (final entry in state.entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  void _replaceEntry(AICanvasTransactionEntry entry) {
    final entries = [
      entry,
      ...state.entries.where((item) => item.id != entry.id),
    ];
    state = state.copyWith(
      entries: entries.length > 50 ? entries.sublist(0, 50) : entries,
      error: null,
    );
  }

  AICanvasActionExecutor _executor({
    AICanvasAction? action,
    bool Function()? canEditCanvas,
  }) => AICanvasActionExecutor(
    nodesNotifier: _ref.read(documentNodesProvider.notifier),
    edgesNotifier: _ref.read(documentEdgesProvider.notifier),
    aiService:
        action?.type == AICanvasActionType.summarizeNotes ||
            action?.type == AICanvasActionType.placeGeneratedOutput
        ? _ref.read(aiServiceProvider)
        : null,
    prepareGeneratedNode:
        action?.type == AICanvasActionType.placeGeneratedOutput
        ? _prepareGeneratedNode
        : null,
    publishPreparedGeneratedNode:
        action?.type == AICanvasActionType.placeGeneratedOutput
        ? _publishPreparedGeneratedNode
        : null,
    projectId: projectId,
    canEditCanvas: canEditCanvas,
  );

  Future<CanvasNode> _prepareGeneratedNode(CanvasNode node) async {
    // Generated artifacts are materialized before they reach the canvas. Keep
    // the runtime handle opaque and register the same stable ID in the manifest
    // before the node becomes durable.
    final payload = node.payload;
    final manifest = _ref.read(documentAssetsProvider);
    final nodes = _ref.read(documentNodesProvider);
    final (kind, reference, name, mimeType, sizeBytes) = switch (payload) {
      ImagePayload payload => (
        DocumentAssetKind.image,
        validImageArtifactReference(payload.imageArtifactReference),
        node.name?.trim().isNotEmpty == true ? node.name! : 'Generated image',
        _generatedImageMimeType(payload),
        _generatedImageSizeBytes(payload),
      ),
      VideoPayload payload => (
        DocumentAssetKind.video,
        validVideoArtifactReference(payload.videoArtifactReference),
        payload.title.trim().isNotEmpty ? payload.title : 'Generated video',
        'video/mp4',
        null,
      ),
      Model3DPayload payload => (
        DocumentAssetKind.model3d,
        validModel3DArtifactReference(payload.artifactReference),
        payload.fileName.trim().isNotEmpty
            ? payload.fileName
            : 'generated-model.glb',
        inferAssetMimeType(payload.fileName, fallback: 'model/gltf-binary'),
        null,
      ),
      _ => (null, null, null, null, null),
    };
    if (kind == null || reference == null || mimeType == null) return node;

    final candidate = switch (payload) {
      ImagePayload payload => payload.assetId,
      VideoPayload payload => payload.assetId,
      Model3DPayload payload => payload.assetId,
      _ => null,
    };
    final assetId = stableDocumentAssetId(
      candidate: candidate,
      manifest: manifest,
      nodes: nodes,
      ownerNodeId: node.id,
      fallback: node.id,
    );
    final bytes = payload is ImagePayload
        ? await _readGeneratedImageBytes(reference)
        : null;
    if (bytes != null && bytes.isNotEmpty) {
      _transientGeneratedBytes[node.id] = Uint8List.fromList(bytes);
    }
    final asset = buildDocumentAsset(
      id: assetId,
      kind: kind,
      name: name!,
      mimeType: mimeType,
      artifactReference: reference,
      storagePath: null,
      declaredSize: sizeBytes,
      bytes: bytes,
      existing: manifest[assetId],
    );
    if (asset == null) return node;
    _preparedGeneratedAssets[node.id] = asset;
    final nextPayload = switch (payload) {
      ImagePayload payload => payload.copyWith(
        assetId: assetId,
        imageArtifactReference: reference,
      ),
      VideoPayload payload => payload.copyWith(
        assetId: assetId,
        videoArtifactReference: reference,
      ),
      Model3DPayload payload => payload.copyWith(
        assetId: assetId,
        artifactReference: reference,
      ),
      _ => payload,
    };
    return node.copyWith(payload: nextPayload);
  }

  Future<Uint8List?> _readGeneratedImageBytes(String reference) async {
    try {
      final store = _ref.read(imageArtifactStoreProvider);
      final hydrated = await store.hydrate(reference);
      if (hydrated == null) return null;
      return hydrated.bytes ?? await store.read(hydrated);
    } catch (_) {
      // A manifest can retain a durable reference after its runtime store is
      // unavailable. Metadata remains usable; checksum enrichment is optional.
      return null;
    }
  }

  String _generatedImageMimeType(ImagePayload payload) {
    final mime = payload.mimeType?.trim().toLowerCase();
    if (mime != null && mime.startsWith('image/')) return mime;
    final assetId = payload.assetId;
    if (assetId != null) {
      final existing = _ref.read(documentAssetsProvider)[assetId];
      final existingMime = existing?.mimeType.trim().toLowerCase();
      if (existingMime != null && existingMime.startsWith('image/')) {
        return existingMime;
      }
    }
    return 'image/png';
  }

  int? _generatedImageSizeBytes(ImagePayload payload) {
    if (payload.byteLength case final value? when value > 0) return value;
    final assetId = payload.assetId;
    if (assetId == null) return null;
    return _ref.read(documentAssetsProvider)[assetId]?.sizeBytes;
  }

  Future<void> _publishPreparedGeneratedNode({
    CanvasNode? originalNode,
    required CanvasNode preparedNode,
  }) async {
    final originalManifest = _ref.read(documentAssetsProvider);
    final assetId = switch (preparedNode.payload) {
      ImagePayload payload => payload.assetId,
      VideoPayload payload => payload.assetId,
      Model3DPayload payload => payload.assetId,
      _ => null,
    };
    if (assetId == null) {
      throw StateError('Prepared generated node has no asset identity.');
    }
    final transientBytes = _transientGeneratedBytes.remove(preparedNode.id);
    var asset =
        _preparedGeneratedAssets.remove(preparedNode.id) ??
        _ref.read(documentAssetsProvider)[assetId];
    if (asset != null && transientBytes != null) {
      final refreshed = buildDocumentAsset(
        id: asset.id,
        kind: asset.kind,
        name: asset.name,
        mimeType: asset.mimeType,
        artifactReference: asset.durableReference,
        storagePath: null,
        declaredSize: asset.sizeBytes,
        bytes: transientBytes,
        existing: asset,
        metadata: asset.metadata,
      );
      if (refreshed != null) asset = refreshed;
    }
    if (asset != null && originalNode == null) {
      final committedManifest = originalManifest.upsert(asset);
      publishDocumentAssetAndNode(
        originalManifest: originalManifest,
        committedManifest: committedManifest,
        setManifest: (next) =>
            _ref.read(documentAssetsProvider.notifier).setManifest(next),
        publishNode: () {
          _ref
              .read(documentNodesProvider.notifier)
              .executeCommand(CreateNodesCommand(nodes: [preparedNode]));
        },
      );
      return;
    }
    if (asset == null) {
      throw StateError(
        'Prepared generated asset is missing from the manifest.',
      );
    }
    final committedManifest = originalManifest.upsert(asset);
    publishDocumentAssetAndNode(
      originalManifest: originalManifest,
      committedManifest: committedManifest,
      setManifest: (next) =>
          _ref.read(documentAssetsProvider.notifier).setManifest(next),
      publishNode: () {
        if (originalNode == null) {
          _ref
              .read(documentNodesProvider.notifier)
              .executeCommand(CreateNodesCommand(nodes: [preparedNode]));
        } else {
          _ref.read(documentNodesProvider.notifier).updateNode(preparedNode);
        }
      },
    );
  }

  String? _generatedOutputMode(AICanvasTransactionOperation operation) {
    switch (operation) {
      case AICanvasTransactionOperation.insert:
        return 'insert';
      case AICanvasTransactionOperation.replace:
        return 'replace';
      default:
        return null;
    }
  }

  Future<void> _persist() async {
    try {
      await _storage.saveAICanvasTransactions(projectId, state.entries);
    } catch (error) {
      if (mounted) state = state.copyWith(error: error.toString());
    }
  }
}
