import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:characters/characters.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/collaboration.dart';
import '../../../domain/models/connector_edge.dart';
import '../../../domain/models/document.dart';
import '../../../domain/models/document_asset.dart';
import '../../../domain/models/design_tokens.dart';
import '../../../domain/models/drawing_paper_payload.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../../drawing_paper/domain/models/raster_edit_operation.dart';
import 'crdt_primitives.dart';
import 'crdt_text_sequence.dart';

export 'crdt_primitives.dart';

const _maxEmbeddedBase64Characters = 64 * 1024;

enum _CrdtHandlerDisposition { applied, buffered, rejected }

class _RasterOperationRecord {
  final String pageId;
  final Map<String, dynamic> operation;
  final CrdtDot? dot;

  const _RasterOperationRecord({
    required this.pageId,
    required this.operation,
    required this.dot,
  });
}

Map<String, dynamic> _collaborationNodeJson(Map<String, dynamic> nodeJson) {
  return _sanitizeCrdtMap(nodeJson);
}

Map<String, dynamic> _sanitizeCrdtMap(Map raw) {
  final sanitized = <String, dynamic>{};
  for (final entry in raw.entries) {
    final key = entry.key.toString();
    sanitized[key] = _sanitizeCrdtValue(entry.value, key: key);
  }
  return sanitized;
}

Object? _sanitizeCrdtValue(Object? value, {String? key}) {
  if (value is String) {
    final normalizedKey = key?.toLowerCase() ?? '';
    if (value.trimLeft().startsWith('data:') ||
        (normalizedKey.contains('base64') &&
            value.length > _maxEmbeddedBase64Characters)) {
      return null;
    }
    return value;
  }
  if (value is Map) return _sanitizeCrdtMap(value);
  if (value is List) {
    return value
        .map((entry) => _sanitizeCrdtValue(entry))
        .toList(growable: false);
  }
  return value;
}

/// In-memory operation-based CRDT for one canvas document.
///
/// The engine owns merge semantics. Riverpod and Supabase adapters only move
/// materialized documents and validated operations across the seam.
class CrdtDocumentSession {
  final String projectId;
  final String actorId;
  final Map<String, CanvasNode> _nodes;
  final Map<String, CanvasEdge> _edges;
  final Map<String, CanvasComment> _comments = {};
  final Map<String, DocumentAsset> _assets;
  final Map<String, DesignToken> _tokens;
  final Map<String, CrdtTextSequence> _text = {};
  final Set<String> _seededText = {};
  final Map<String, CrdtRegisterValue> _fieldRegisters = {};
  final Map<String, CrdtDot> _nodeDots = {};
  final Map<String, CrdtDot> _nodeGenerationDots = {};
  final Map<String, CrdtDot> _edgeDots = {};
  final Map<String, CrdtDot> _nodeTombstones = {};
  final Map<String, CrdtDot> _edgeTombstones = {};
  final Map<String, CrdtDot> _commentDots = {};
  final Map<String, CrdtDot> _commentTombstones = {};
  final Map<String, CrdtDot> _commentReplyDots = {};
  final Map<String, CrdtDot> _commentReplyTombstones = {};
  final Map<String, CrdtRegisterValue> _commentReactionRegisters = {};
  final Map<String, CrdtRegisterValue> _commentResolveRegisters = {};
  final Map<String, CrdtDot> _strokeDots = {};
  final Map<String, DrawingStroke> _strokeRegisters = {};
  final Map<String, CrdtDot> _strokeTombstones = {};
  final Map<String, Map<String, CrdtDot>> _strokeRevisionDots = {};
  final Map<String, CrdtDot> _assetDots = {};
  final Map<String, CrdtDot> _assetTombstones = {};
  final Map<String, CrdtDot> _tokenDots = {};
  final Map<String, CrdtDot> _tokenTombstones = {};
  int _tokenSetVersion;
  List<String> _tokenModes;
  final Set<String> _seen = {};
  final List<CrdtOperation> _outbound = [];
  final List<CrdtOperation> _causalBuffer = [];
  final Map<String, List<Map<String, dynamic>>> _rasterOperations = {};
  final Map<String, Map<String, Map<String, Map<String, dynamic>>>>
  _rasterOperationValues = {};
  final Map<String, Map<String, Map<String, CrdtDot>>> _rasterOperationDots =
      {};
  final Map<String, Map<String, CrdtDot>> _rasterResetDots = {};

  CrdtVersionVector _clock = CrdtVersionVector();
  CanvasDocument _baseDocument;

  CrdtDocumentSession._({
    required CanvasDocument document,
    required this.actorId,
  }) : projectId = document.projectId,
       _baseDocument = document,
       _nodes = {for (final node in document.nodes) node.id: node},
       _edges = {for (final edge in document.edges) edge.id: edge},
       _assets = {...document.assets.entries},
       _tokens = {...document.tokens.entries},
       _tokenSetVersion = document.tokens.version,
       _tokenModes = List<String>.from(document.tokens.modes);

  factory CrdtDocumentSession.fromDocument(
    CanvasDocument document, {
    required String actorId,
  }) {
    document.assets.validateIdentity();
    final session = CrdtDocumentSession._(document: document, actorId: actorId);
    session._seedRasterOperationsForCurrentNodes();
    session._seedTextForDocument(document);
    return session;
  }

  factory CrdtDocumentSession.fromSnapshot({
    required CanvasDocument document,
    required String actorId,
    required CrdtVersionVector version,
    Map<String, dynamic> state = const {},
    Iterable<CanvasComment> comments = const [],
  }) {
    document.assets.validateIdentity();
    final session = CrdtDocumentSession._(document: document, actorId: actorId);
    session._clock = version;
    session._restoreState(state);
    session.seedComments(comments);
    if (session._text.isEmpty) session._seedTextForDocument(document);
    return session;
  }

  CanvasDocument get document => _materializeDocument();

  CrdtVersionVector get version => _clock;

  int get pendingOperationCount => _outbound.length;

  bool get hasCausalBuffer => _causalBuffer.isNotEmpty;

  List<CrdtOperation> drainOutbound() {
    final operations = List<CrdtOperation>.unmodifiable(_outbound);
    _outbound.clear();
    return operations;
  }

  CrdtOperation upsertNode(CanvasNode node) => _emit(
    kind: CrdtOperationKind.nodeUpsert,
    targetId: node.id,
    value: {'node': _collaborationNodeJson(node.toPersistenceJson())},
  );

  CrdtOperation deleteNode(String nodeId) =>
      _emit(kind: CrdtOperationKind.nodeDelete, targetId: nodeId);

  CrdtOperation upsertEdge(CanvasEdge edge) => _emit(
    kind: CrdtOperationKind.edgeUpsert,
    targetId: edge.id,
    value: {'edge': edge.toPersistenceJson()},
  );

  CrdtOperation deleteEdge(String edgeId) =>
      _emit(kind: CrdtOperationKind.edgeDelete, targetId: edgeId);

  CrdtOperation upsertStroke({
    required String nodeId,
    required String pageId,
    required String layerId,
    required DrawingStroke stroke,
  }) => _emit(
    kind: CrdtOperationKind.strokeUpsert,
    targetId: nodeId,
    value: {
      'pageId': pageId,
      'layerId': layerId,
      'strokeId': stroke.id,
      'stroke': stroke.toJson(),
    },
  );

  CrdtOperation deleteStroke({
    required String nodeId,
    required String pageId,
    required String layerId,
    required String strokeId,
  }) => _emit(
    kind: CrdtOperationKind.strokeDelete,
    targetId: nodeId,
    value: {'pageId': pageId, 'layerId': layerId, 'strokeId': strokeId},
  );

  CrdtOperation upsertAsset(DocumentAsset asset) => _emit(
    kind: CrdtOperationKind.assetUpsert,
    targetId: asset.id,
    value: {'asset': asset.toPersistenceJson()},
  );

  CrdtOperation deleteAsset(String assetId) =>
      _emit(kind: CrdtOperationKind.assetDelete, targetId: assetId);

  CrdtOperation upsertToken(
    DesignToken token, {
    List<String>? modes,
    int? version,
  }) => _emit(
    kind: CrdtOperationKind.tokenUpsert,
    targetId: token.id,
    value: {'token': token.toJson(), 'modes': ?modes, 'version': ?version},
  );

  CrdtOperation deleteToken(String tokenId) =>
      _emit(kind: CrdtOperationKind.tokenDelete, targetId: tokenId);

  CrdtOperation setNodeField({
    required String nodeId,
    required String field,
    required Object? value,
  }) => _emit(
    kind: CrdtOperationKind.nodeFieldSet,
    targetId: nodeId,
    field: field,
    value: {'value': value},
  );

  /// Replaces a text value as a minimal sequence diff.
  ///
  /// Each inserted grapheme is an independent RGA atom. This is deliberately
  /// less clever than a diff library, but handles typing, paste, and deletion
  /// while keeping concurrent inserts mergeable and deterministic.
  List<CrdtOperation> replaceText({
    required String nodeId,
    required String field,
    required String value,
  }) {
    final sequence = _textSequenceFor(nodeId, field);
    final current = sequence.visibleText;
    final oldCharacters = current.characters.toList(growable: false);
    final newCharacters = value.characters.toList(growable: false);

    var prefix = 0;
    while (prefix < oldCharacters.length &&
        prefix < newCharacters.length &&
        oldCharacters[prefix] == newCharacters[prefix]) {
      prefix++;
    }

    var suffix = 0;
    while (suffix < oldCharacters.length - prefix &&
        suffix < newCharacters.length - prefix &&
        oldCharacters[oldCharacters.length - suffix - 1] ==
            newCharacters[newCharacters.length - suffix - 1]) {
      suffix++;
    }

    final operations = <CrdtOperation>[];
    final removed = sequence.atomsForRange(
      prefix,
      oldCharacters.length - suffix,
    );
    for (final atom in removed) {
      operations.add(
        _emit(
          kind: CrdtOperationKind.textDelete,
          targetId: nodeId,
          field: field,
          value: {'target': atom.id.toJson()},
        ),
      );
    }

    var after = sequence.visibleIdBefore(prefix);
    final inserted = newCharacters.sublist(
      prefix,
      newCharacters.length - suffix,
    );
    for (final character in inserted) {
      final operation = _emit(
        kind: CrdtOperationKind.textInsert,
        targetId: nodeId,
        field: field,
        value: {'after': after?.toJson(), 'text': character},
      );
      operations.add(operation);
      after = operation.dot;
    }
    return operations;
  }

  CrdtOperation formatText({
    required String nodeId,
    required String field,
    required int start,
    required int end,
    required String format,
    required Object? value,
  }) {
    final sequence = _textSequenceFor(nodeId, field);
    final atoms = sequence.atomsForRange(start, end);
    return _emit(
      kind: CrdtOperationKind.textFormat,
      targetId: nodeId,
      field: field,
      value: {
        'targets': atoms.map((atom) => atom.id.toJson()).toList(),
        'format': format,
        'value': value,
      },
    );
  }

  CrdtOperation upsertComment(CanvasComment comment) => _emit(
    kind: CrdtOperationKind.commentUpsert,
    targetId: comment.id,
    value: {'comment': comment.toJson()},
  );

  CrdtOperation deleteComment(String commentId) =>
      _emit(kind: CrdtOperationKind.commentDelete, targetId: commentId);

  CrdtOperation insertCommentReply({
    required String commentId,
    required CommentReply reply,
  }) => _emit(
    kind: CrdtOperationKind.commentReplyInsert,
    targetId: commentId,
    value: {'reply': reply.toJson()},
  );

  CrdtOperation upsertCommentReply({
    required String commentId,
    required CommentReply reply,
  }) => _emit(
    kind: CrdtOperationKind.commentReplyUpsert,
    targetId: commentId,
    value: {'reply': reply.toJson()},
  );

  CrdtOperation deleteCommentReply({
    required String commentId,
    required String replyId,
  }) => _emit(
    kind: CrdtOperationKind.commentReplyDelete,
    targetId: commentId,
    value: {'replyId': replyId},
  );

  CrdtOperation setCommentReaction({
    required String commentId,
    required String userId,
    required String emoji,
    required bool active,
  }) => _emit(
    kind: CrdtOperationKind.commentReactionSet,
    targetId: commentId,
    value: {'userId': userId, 'emoji': emoji, 'active': active},
  );

  bool isCommentReactionActive({
    required String commentId,
    required String userId,
    required String emoji,
  }) => _commentReactionRegisters['$commentId|$userId|$emoji']?.value == true;

  CrdtOperation setCommentResolved({
    required String commentId,
    required bool resolved,
  }) => _emit(
    kind: CrdtOperationKind.commentResolveSet,
    targetId: commentId,
    value: {'resolved': resolved},
  );

  CrdtOperation addRasterOperation({
    required String nodeId,
    required Map<String, dynamic> operation,
    String pageId = 'root-page',
  }) => _emit(
    kind: CrdtOperationKind.rasterOperation,
    targetId: nodeId,
    value: {'pageId': pageId, 'operation': operation},
  );

  CrdtOperation resetRasterOperations({
    required String nodeId,
    String pageId = 'root-page',
  }) => _emit(
    kind: CrdtOperationKind.rasterReset,
    targetId: nodeId,
    value: {'pageId': pageId},
  );

  CrdtOperation reissueOperation(
    CrdtOperation operation, {
    Map<String, dynamic>? value,
  }) => _emit(
    kind: operation.kind,
    targetId: operation.targetId,
    field: operation.field,
    value: value ?? operation.value,
  );

  CrdtApplyStatus applyRemote(CrdtOperation operation) {
    if (operation.projectId != projectId) return CrdtApplyStatus.rejected;
    if (_seen.contains(operation.opId) ||
        _clock[operation.dot.actorId] >= operation.dot.counter) {
      return CrdtApplyStatus.duplicate;
    }
    if (!_clock.satisfies(operation.dependencies)) {
      if (!_causalBuffer.any((item) => item.opId == operation.opId)) {
        _causalBuffer.add(operation);
      }
      return CrdtApplyStatus.buffered;
    }

    final status = _applyReady(operation);
    if (status == CrdtApplyStatus.buffered &&
        !_causalBuffer.any((item) => item.opId == operation.opId)) {
      _causalBuffer.add(operation);
    }
    if (status != CrdtApplyStatus.applied) return status;
    _drainCausalBuffer();
    return CrdtApplyStatus.applied;
  }

  void seedComments(Iterable<CanvasComment> comments) {
    for (final comment in comments) {
      _comments[comment.id] = comment;
    }
  }

  List<Map<String, dynamic>> rasterOperationsFor(String nodeId) =>
      List.unmodifiable(_rasterOperations[nodeId] ?? const []);

  CrdtOperation _emit({
    required CrdtOperationKind kind,
    required String targetId,
    String? field,
    Map<String, dynamic> value = const {},
  }) {
    final dot = CrdtDot(actorId: actorId, counter: _clock.nextCounter);
    final operation = CrdtOperation.create(
      projectId: projectId,
      dot: dot,
      dependencies: _clock,
      kind: kind,
      targetId: targetId,
      field: field,
      value: value,
    );
    if (operation.encode().length > CrdtOperation.maxEncodedBytes) {
      throw const FormatException('CRDT operation is too large');
    }
    final status = _applyReady(operation);
    if (status != CrdtApplyStatus.applied) {
      throw StateError('Local CRDT operation was not applied: $status');
    }
    _outbound.add(operation);
    _drainCausalBuffer();
    return operation;
  }

  CrdtApplyStatus _applyReady(CrdtOperation operation) {
    if (_seen.contains(operation.opId)) return CrdtApplyStatus.duplicate;
    if (!_clock.satisfies(operation.dependencies)) {
      return CrdtApplyStatus.buffered;
    }

    final disposition = switch (operation.kind) {
      CrdtOperationKind.nodeUpsert => _validateNodeUpsert(operation),
      CrdtOperationKind.assetUpsert => _validateAssetUpsert(operation),
      CrdtOperationKind.strokeUpsert => _applyStrokeUpsert(operation),
      CrdtOperationKind.strokeDelete => _applyStrokeDelete(operation),
      CrdtOperationKind.rasterOperation => _applyRasterOperation(operation),
      CrdtOperationKind.rasterReset => _applyRasterReset(operation),
      CrdtOperationKind.nodeFieldSet => _applyNodeField(operation),
      _ => _CrdtHandlerDisposition.applied,
    };
    if (disposition == _CrdtHandlerDisposition.buffered) {
      return CrdtApplyStatus.buffered;
    }
    if (disposition == _CrdtHandlerDisposition.rejected) {
      return CrdtApplyStatus.rejected;
    }

    switch (operation.kind) {
      case CrdtOperationKind.nodeUpsert:
        _applyNodeUpsert(operation);
        _materializeRasterOperations(operation.targetId);
        _materializeAllStrokeRevisions(operation.targetId);
      case CrdtOperationKind.nodeDelete:
        _applyNodeDelete(operation);
      case CrdtOperationKind.edgeUpsert:
        _applyEdgeUpsert(operation);
      case CrdtOperationKind.edgeDelete:
        _applyEdgeDelete(operation);
      case CrdtOperationKind.nodeFieldSet:
        break;
      case CrdtOperationKind.textInsert:
        _applyTextInsert(operation);
      case CrdtOperationKind.textDelete:
        _applyTextDelete(operation);
      case CrdtOperationKind.textFormat:
        _applyTextFormat(operation);
      case CrdtOperationKind.strokeUpsert || CrdtOperationKind.strokeDelete:
        break;
      case CrdtOperationKind.rasterOperation || CrdtOperationKind.rasterReset:
        break;
      case CrdtOperationKind.assetUpsert:
        _applyAssetUpsert(operation);
      case CrdtOperationKind.assetDelete:
        _applyAssetDelete(operation);
      case CrdtOperationKind.tokenUpsert:
        _applyTokenUpsert(operation);
      case CrdtOperationKind.tokenDelete:
        _applyTokenDelete(operation);
      case CrdtOperationKind.commentUpsert:
        _applyCommentUpsert(operation);
      case CrdtOperationKind.commentDelete:
        _applyCommentDelete(operation);
      case CrdtOperationKind.commentReplyInsert:
      case CrdtOperationKind.commentReplyUpsert:
        _applyCommentReplyUpsert(operation);
      case CrdtOperationKind.commentReplyDelete:
        _applyCommentReplyDelete(operation);
      case CrdtOperationKind.commentReactionSet:
        _applyCommentReactionSet(operation);
      case CrdtOperationKind.commentResolveSet:
        _applyCommentResolveSet(operation);
    }

    _seen.add(operation.opId);
    _clock = _clock.advance(operation.dot);
    return CrdtApplyStatus.applied;
  }

  void _drainCausalBuffer() {
    var changed = true;
    while (changed) {
      changed = false;
      for (final operation in List<CrdtOperation>.from(_causalBuffer)) {
        if (!_clock.satisfies(operation.dependencies)) continue;
        final status = _applyReady(operation);
        if (status == CrdtApplyStatus.buffered) continue;
        _causalBuffer.remove(operation);
        changed = true;
      }
    }
  }

  _CrdtHandlerDisposition _validateNodeUpsert(CrdtOperation operation) {
    final rawNode = operation.value['node'];
    if (rawNode is! Map) return _CrdtHandlerDisposition.rejected;
    try {
      CanvasNode.fromJson(Map<String, dynamic>.from(rawNode));
    } catch (_) {
      return _CrdtHandlerDisposition.rejected;
    }
    return _CrdtHandlerDisposition.applied;
  }

  _CrdtHandlerDisposition _validateAssetUpsert(CrdtOperation operation) {
    final rawAsset = operation.value['asset'];
    if (rawAsset is! Map) return _CrdtHandlerDisposition.rejected;
    try {
      final asset = DocumentAsset.fromJson(Map<String, dynamic>.from(rawAsset));
      return asset.id == operation.targetId
          ? _CrdtHandlerDisposition.applied
          : _CrdtHandlerDisposition.rejected;
    } catch (_) {
      return _CrdtHandlerDisposition.rejected;
    }
  }

  bool _dotBlocksOperation(CrdtDot existing, CrdtOperation operation) {
    final causallyAfter = operation.dependencies.satisfies(
      CrdtVersionVector({existing.actorId: existing.counter}),
    );
    if (causallyAfter) return false;
    return existing.compareTimestampTo(operation.dot) >= 0;
  }

  void _applyNodeUpsert(CrdtOperation operation) {
    final rawNode = operation.value['node'];
    if (rawNode is! Map) return;
    final node = CanvasNode.fromJson(Map<String, dynamic>.from(rawNode));
    final tombstone = _nodeTombstones[node.id];
    if (tombstone != null && _dotBlocksOperation(tombstone, operation)) {
      return;
    }
    final previous = _nodeDots[node.id];
    if (previous != null && _dotBlocksOperation(previous, operation)) {
      return;
    }
    final startsFreshGeneration = tombstone != null;
    _nodeTombstones.remove(node.id);
    _nodeDots[node.id] = operation.dot;
    _nodeGenerationDots[node.id] = startsFreshGeneration
        ? operation.dot
        : (_nodeGenerationDots[node.id] ?? operation.dot);
    if (startsFreshGeneration) {
      _fieldRegisters.removeWhere((key, _) => key.startsWith('${node.id}|'));
      _text.removeWhere((key, _) => key.startsWith('${node.id}|'));
      _seededText.removeWhere((key) => key.startsWith('${node.id}|'));
    }
    if (startsFreshGeneration) {
      _clearNodeDrawingState(node.id);
    }
    _nodes[node.id] = startsFreshGeneration
        ? node
        : _mergeDrawingStrokeState(node, previousNode: _nodes[node.id]);
    _seedRasterOperationsForNode(_nodes[node.id]!);
    _seedTextForNode(_nodes[node.id]!);
    _reapplyNodeFields(node.id);
  }

  CanvasNode _mergeDrawingStrokeState(
    CanvasNode incoming, {
    required CanvasNode? previousNode,
  }) {
    final incomingPayload = incoming.payload;
    if (incomingPayload is! DrawingPaperPayload) return incoming;

    var merged = _reapplyStrokeRegistersToPayload(incoming.id, incomingPayload);
    final previousPayload = previousNode?.payload;
    if (previousPayload is DrawingPaperPayload) {
      merged = _mergeExistingStrokeState(
        nodeId: incoming.id,
        incoming: merged,
        previous: previousPayload,
      );
    }
    return identical(merged, incomingPayload)
        ? incoming
        : incoming.copyWith(payload: merged);
  }

  DrawingPaperPayload _mergeExistingStrokeState({
    required String nodeId,
    required DrawingPaperPayload incoming,
    required DrawingPaperPayload previous,
    String pageId = 'root-page',
  }) {
    var next = _mergePageLayers(
      nodeId: nodeId,
      pageId: pageId,
      incoming: incoming,
      previous: previous,
    );
    final previousPages = {
      for (final page in previous.studioPages) page.id: page,
    };
    final pages = <DrawingPaperPage>[];
    var pagesChanged = false;
    for (final page in next.studioPages) {
      final oldPage = previousPages[page.id];
      if (oldPage == null) {
        pages.add(page);
        continue;
      }
      final mergedPage = _mergeExistingStrokeState(
        nodeId: nodeId,
        pageId: page.id,
        incoming: page.payload,
        previous: oldPage.payload,
      );
      pages.add(page.copyWith(payload: mergedPage));
      pagesChanged = pagesChanged || !identical(mergedPage, page.payload);
    }
    if (pagesChanged) next = next.copyWith(studioPages: pages);
    return next;
  }

  DrawingPaperPayload _mergePageLayers({
    required String nodeId,
    required String pageId,
    required DrawingPaperPayload incoming,
    required DrawingPaperPayload previous,
  }) {
    final previousLayers = {
      for (final layer in previous.layers) layer.id: layer,
    };
    final nextLayers = <DrawingLayer>[];
    var layersChanged = false;
    for (final incomingLayer in incoming.layers) {
      final previousLayer = previousLayers[incomingLayer.id];
      if (previousLayer == null) {
        nextLayers.add(incomingLayer);
        continue;
      }
      final strokes = _mergeLayerStrokes(
        nodeId: nodeId,
        pageId: pageId,
        layerId: incomingLayer.id,
        incoming: incomingLayer.strokes,
        previous: previousLayer.strokes,
      );
      nextLayers.add(incomingLayer.copyWith(strokes: strokes));
      layersChanged =
          layersChanged ||
          strokes.length != incomingLayer.strokes.length ||
          _strokeListsDiffer(strokes, incomingLayer.strokes);
    }
    if (!layersChanged) return incoming;
    return incoming.copyWith(layers: nextLayers);
  }

  List<DrawingStroke> _mergeLayerStrokes({
    required String nodeId,
    required String pageId,
    required String layerId,
    required List<DrawingStroke> incoming,
    required List<DrawingStroke> previous,
  }) {
    final merged = <String, DrawingStroke>{
      for (final stroke in incoming) stroke.id: stroke,
    };
    for (final stroke in previous) {
      final key = _strokeKey(
        nodeId: nodeId,
        pageId: pageId,
        layerId: layerId,
        strokeId: stroke.id,
      );
      final dot = _strokeDots[key];
      final tombstone = _strokeTombstones[key];
      if (tombstone != null &&
          (dot == null || tombstone.compareTimestampTo(dot) >= 0)) {
        merged.remove(stroke.id);
        continue;
      }
      final registered = _strokeRegisters[key];
      if (registered != null && dot != null) {
        merged[stroke.id] = registered;
      } else {
        merged.putIfAbsent(stroke.id, () => stroke);
      }
    }
    for (final entry in _strokeRegisters.entries) {
      final parts = entry.key.split('|');
      if (parts.length != 4 ||
          parts[0] != nodeId ||
          parts[1] != pageId ||
          parts[2] != layerId) {
        continue;
      }
      final dot = _strokeDots[entry.key];
      final tombstone = _strokeTombstones[entry.key];
      if (dot != null &&
          (tombstone == null || tombstone.compareTimestampTo(dot) < 0)) {
        merged[parts[3]] = entry.value;
      }
    }
    final result = merged.values.toList();
    result.sort(
      (left, right) => _compareStrokeOrder(
        nodeId: nodeId,
        pageId: pageId,
        layerId: layerId,
        left: left,
        right: right,
      ),
    );
    return result;
  }

  bool _strokeListsDiffer(
    List<DrawingStroke> first,
    List<DrawingStroke> second,
  ) {
    if (first.length != second.length) return true;
    for (var index = 0; index < first.length; index++) {
      if (jsonEncode(first[index].toJson()) !=
          jsonEncode(second[index].toJson())) {
        return true;
      }
    }
    return false;
  }

  int _compareStrokeOrder({
    required String nodeId,
    required String pageId,
    required String layerId,
    required DrawingStroke left,
    required DrawingStroke right,
  }) {
    final leftDot =
        _strokeDots[_strokeKey(
          nodeId: nodeId,
          pageId: pageId,
          layerId: layerId,
          strokeId: left.id,
        )];
    final rightDot =
        _strokeDots[_strokeKey(
          nodeId: nodeId,
          pageId: pageId,
          layerId: layerId,
          strokeId: right.id,
        )];
    if (leftDot == null && rightDot == null) return left.id.compareTo(right.id);
    if (leftDot == null) return -1;
    if (rightDot == null) return 1;
    return leftDot.compareTo(rightDot);
  }

  void _clearNodeDrawingState(String nodeId) {
    _rasterOperations.remove(nodeId);
    _rasterOperationValues.remove(nodeId);
    _rasterOperationDots.remove(nodeId);
    _rasterResetDots.remove(nodeId);
    _strokeDots.removeWhere((key, _) => key.startsWith('$nodeId|'));
    _strokeRegisters.removeWhere((key, _) => key.startsWith('$nodeId|'));
    _strokeTombstones.removeWhere((key, _) => key.startsWith('$nodeId|'));
    _strokeRevisionDots.remove(nodeId);
  }

  void _seedRasterOperationsForCurrentNodes() {
    for (final node in _nodes.values) {
      _seedRasterOperationsForNode(node);
    }
  }

  void _seedRasterOperationsForNode(CanvasNode node) {
    final payload = node.payload;
    if (payload is! DrawingPaperPayload) return;
    _seedRasterOperationsForPayload(node.id, payload);
    _rebuildRasterOperationCache(node.id);
  }

  void _seedRasterOperationsForPayload(
    String nodeId,
    DrawingPaperPayload payload,
  ) {
    final nodeValues = _rasterOperationValues.putIfAbsent(nodeId, () => {});

    void seedPage(String pageId, DrawingPaperPayload pagePayload) {
      final resetDot = _rasterResetDots[nodeId]?[pageId];
      final pageValues = nodeValues.putIfAbsent(pageId, () => {});
      if (resetDot != null) return;
      for (final operation in pagePayload.rasterOperations) {
        final raw = operation.toJson();
        final alreadySeeded = pageValues.values.any(
          (value) => jsonEncode(value) == jsonEncode(raw),
        );
        if (alreadySeeded) continue;
        var key = operation.id;
        var suffix = 1;
        while (pageValues.containsKey(key)) {
          key = 'legacy:${operation.id}:$suffix';
          suffix++;
        }
        pageValues[key] = raw;
      }
      for (final page in pagePayload.studioPages) {
        seedPage(page.id, page.payload);
      }
    }

    seedPage('root-page', payload);
  }

  DrawingPaperPayload _reapplyStrokeRegistersToPayload(
    String nodeId,
    DrawingPaperPayload payload,
  ) {
    var next = payload;
    final keys = <String>{
      ..._strokeRegisters.keys,
      ..._strokeTombstones.keys,
    }.toList()..sort();
    for (final key in keys) {
      final parts = key.split('|');
      if (parts.length != 4 || parts[0] != nodeId) continue;
      final pageId = parts[1];
      final layerId = parts[2];
      final strokeId = parts[3];
      final stroke = _strokeRegisters[key];
      final strokeDot = _strokeDots[key];
      final tombstone = _strokeTombstones[key];
      if (stroke != null &&
          strokeDot != null &&
          (tombstone == null || tombstone.compareTimestampTo(strokeDot) < 0)) {
        next = _updatePagePayload(
          next,
          pageId: pageId,
          update: (pagePayload) => _updateLayerStrokes(
            pagePayload,
            nodeId: nodeId,
            pageId: pageId,
            layerId: layerId,
            replace: stroke,
            incrementRevision: false,
          ),
        );
      }
      if (tombstone != null) {
        next = _updatePagePayload(
          next,
          pageId: pageId,
          update: (pagePayload) => _updateLayerStrokes(
            pagePayload,
            nodeId: nodeId,
            pageId: pageId,
            layerId: layerId,
            deleteId: strokeId,
            incrementRevision: false,
          ),
        );
      }
    }
    return next;
  }

  DrawingPaperPayload _updatePagePayload(
    DrawingPaperPayload payload, {
    required String pageId,
    required DrawingPaperPayload Function(DrawingPaperPayload payload) update,
  }) {
    if (pageId == 'root-page') return update(payload);
    final updatedPages = _mapDrawingPagePayload(
      payload.studioPages,
      pageId: pageId,
      update: update,
    );
    if (identical(updatedPages, payload.studioPages)) return payload;
    return payload.copyWith(studioPages: updatedPages);
  }

  List<DrawingPaperPage> _mapDrawingPagePayload(
    List<DrawingPaperPage> pages, {
    required String pageId,
    required DrawingPaperPayload Function(DrawingPaperPayload payload) update,
  }) {
    var changed = false;
    final nextPages = <DrawingPaperPage>[];
    for (final page in pages) {
      if (page.id == pageId) {
        final nextPayload = update(page.payload);
        changed = changed || !identical(nextPayload, page.payload);
        nextPages.add(page.copyWith(payload: nextPayload));
        continue;
      }
      final nestedPages = _mapDrawingPagePayload(
        page.payload.studioPages,
        pageId: pageId,
        update: update,
      );
      if (!identical(nestedPages, page.payload.studioPages)) {
        changed = true;
        nextPages.add(
          page.copyWith(
            payload: page.payload.copyWith(studioPages: nestedPages),
          ),
        );
      } else {
        nextPages.add(page);
      }
    }
    return changed ? nextPages : pages;
  }

  void _applyNodeDelete(CrdtOperation operation) {
    final previous = _nodeTombstones[operation.targetId];
    if (previous != null && _dotBlocksOperation(previous, operation)) {
      return;
    }
    final nodeDot = _nodeDots[operation.targetId];
    if (nodeDot != null && _dotBlocksOperation(nodeDot, operation)) {
      return;
    }
    _nodeTombstones[operation.targetId] = operation.dot;
    _nodes.remove(operation.targetId);
    _fieldRegisters.removeWhere(
      (key, _) => key.startsWith('${operation.targetId}|'),
    );
    _text.removeWhere((key, _) => key.startsWith('${operation.targetId}|'));
    _seededText.removeWhere((key) => key.startsWith('${operation.targetId}|'));
    _clearNodeDrawingState(operation.targetId);
  }

  void _applyEdgeUpsert(CrdtOperation operation) {
    final rawEdge = operation.value['edge'];
    if (rawEdge is! Map) return;
    final edge = CanvasEdge.fromJson(Map<String, dynamic>.from(rawEdge));
    final tombstone = _edgeTombstones[edge.id];
    if (tombstone != null && tombstone.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    final previous = _edgeDots[edge.id];
    if (previous != null && previous.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    _edgeTombstones.remove(edge.id);
    _edgeDots[edge.id] = operation.dot;
    _edges[edge.id] = edge;
  }

  void _applyEdgeDelete(CrdtOperation operation) {
    final previous = _edgeTombstones[operation.targetId];
    if (previous != null && previous.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    final edgeDot = _edgeDots[operation.targetId];
    if (edgeDot != null && edgeDot.compareTimestampTo(operation.dot) > 0) {
      return;
    }
    _edgeTombstones[operation.targetId] = operation.dot;
    _edges.remove(operation.targetId);
  }

  void _applyAssetUpsert(CrdtOperation operation) {
    final rawAsset = operation.value['asset'];
    if (rawAsset is! Map) return;
    final asset = DocumentAsset.fromJson(Map<String, dynamic>.from(rawAsset));
    final tombstone = _assetTombstones[asset.id];
    if (tombstone != null && tombstone.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    final previous = _assetDots[asset.id];
    if (previous != null && previous.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    _assetTombstones.remove(asset.id);
    _assetDots[asset.id] = operation.dot;
    _assets[asset.id] = asset;
  }

  void _applyAssetDelete(CrdtOperation operation) {
    final previous = _assetTombstones[operation.targetId];
    if (previous != null && previous.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    final assetDot = _assetDots[operation.targetId];
    if (assetDot != null && assetDot.compareTimestampTo(operation.dot) > 0) {
      return;
    }
    _assetTombstones[operation.targetId] = operation.dot;
    _assets.remove(operation.targetId);
  }

  void _applyTokenUpsert(CrdtOperation operation) {
    final rawToken = operation.value['token'];
    if (rawToken is! Map) return;
    final token = DesignToken.fromJson(Map<String, dynamic>.from(rawToken));
    if (token.id != operation.targetId) return;
    final tombstone = _tokenTombstones[token.id];
    if (tombstone != null && tombstone.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    final previous = _tokenDots[token.id];
    if (previous != null && previous.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    _tokenTombstones.remove(token.id);
    _tokenDots[token.id] = operation.dot;
    _tokens[token.id] = token;

    final rawModes = operation.value['modes'];
    if (rawModes is List) {
      final modes = rawModes.whereType<String>().where(
        (mode) => mode.isNotEmpty,
      );
      final nextModes = modes.toSet().toList(growable: false);
      if (nextModes.isNotEmpty) _tokenModes = nextModes;
    }
    final rawVersion = operation.value['version'];
    if (rawVersion is num && rawVersion.toInt() > 0) {
      _tokenSetVersion = rawVersion.toInt();
    }
  }

  void _applyTokenDelete(CrdtOperation operation) {
    final previous = _tokenTombstones[operation.targetId];
    if (previous != null && previous.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    final tokenDot = _tokenDots[operation.targetId];
    if (tokenDot != null && tokenDot.compareTimestampTo(operation.dot) > 0) {
      return;
    }
    _tokenTombstones[operation.targetId] = operation.dot;
    _tokens.remove(operation.targetId);
  }

  _CrdtHandlerDisposition _applyNodeField(CrdtOperation operation) {
    final node = _nodes[operation.targetId];
    if (operation.field == null) return _CrdtHandlerDisposition.rejected;
    if (node == null) return _CrdtHandlerDisposition.buffered;
    final nodeDot = _nodeDots[operation.targetId];
    if (nodeDot != null && nodeDot.compareTimestampTo(operation.dot) >= 0) {
      return _CrdtHandlerDisposition.applied;
    }
    final key = '${operation.targetId}|${operation.field}';
    final previous = _fieldRegisters[key];
    if (previous != null &&
        previous.dot.compareTimestampTo(operation.dot) >= 0) {
      return _CrdtHandlerDisposition.applied;
    }
    final value = operation.value['value'];
    _fieldRegisters[key] = CrdtRegisterValue(dot: operation.dot, value: value);
    _nodes[operation.targetId] = _setNodeField(node, operation.field!, value);
    return _CrdtHandlerDisposition.applied;
  }

  void _reapplyNodeFields(String nodeId) {
    final storedNode = _nodes[nodeId];
    if (storedNode == null) return;
    var node = storedNode;
    final nodeDot = _nodeDots[nodeId];
    for (final entry in _fieldRegisters.entries) {
      if (!entry.key.startsWith('$nodeId|')) continue;
      if (nodeDot != null && nodeDot.compareTimestampTo(entry.value.dot) >= 0) {
        continue;
      }
      final field = entry.key.substring(nodeId.length + 1);
      node = _setNodeField(node, field, entry.value.value);
    }
    _nodes[nodeId] = node;
  }

  void _applyTextInsert(CrdtOperation operation) {
    final field = operation.field;
    if (field == null) return;
    final sequence = _textSequenceFor(operation.targetId, field);
    final rawAfter = operation.value['after'];
    final after = rawAfter is Map
        ? CrdtDot.fromJson(Map<String, dynamic>.from(rawAfter))
        : null;
    final value = operation.value['text'];
    if (value is! String || value.isEmpty) return;
    sequence.insert(id: operation.dot, after: after, value: value);
    _materializeText(operation.targetId, field, sequence.visibleText);
  }

  void _applyTextDelete(CrdtOperation operation) {
    final field = operation.field;
    final rawTarget = operation.value['target'];
    if (field == null || rawTarget is! Map) return;
    final target = CrdtDot.fromJson(Map<String, dynamic>.from(rawTarget));
    final sequence = _textSequenceFor(operation.targetId, field);
    sequence.delete(target, operation.dot);
    _materializeText(operation.targetId, field, sequence.visibleText);
  }

  void _applyTextFormat(CrdtOperation operation) {
    final field = operation.field;
    final rawTargets = operation.value['targets'];
    final format = operation.value['format'];
    if (field == null || rawTargets is! List || format is! String) return;
    final sequence = _textSequenceFor(operation.targetId, field);
    for (final rawTarget in rawTargets) {
      if (rawTarget is Map) {
        sequence.format(
          target: CrdtDot.fromJson(Map<String, dynamic>.from(rawTarget)),
          dot: operation.dot,
          key: format,
          value: operation.value['value'],
        );
      }
    }
  }

  _CrdtHandlerDisposition _applyRasterReset(CrdtOperation operation) {
    final rawPageId = operation.value['pageId'];
    final pageId = rawPageId is String && rawPageId.trim().isNotEmpty
        ? rawPageId
        : rawPageId == null
        ? 'root-page'
        : null;
    if (pageId == null) return _CrdtHandlerDisposition.rejected;
    final previous = _rasterResetDots[operation.targetId]?[pageId];
    if (previous != null && previous.compareTimestampTo(operation.dot) >= 0) {
      return _CrdtHandlerDisposition.applied;
    }
    _rasterResetDots.putIfAbsent(operation.targetId, () => {})[pageId] =
        operation.dot;
    final values = _rasterOperationValues[operation.targetId];
    final dots = _rasterOperationDots[operation.targetId];
    final pageValues = values?[pageId];
    final pageDots = dots?[pageId];
    if (pageValues != null) {
      pageValues.removeWhere((id, _) {
        final dot = pageDots?[id];
        return dot == null || dot.compareTimestampTo(operation.dot) <= 0;
      });
      pageDots?.removeWhere(
        (id, dot) =>
            dot.compareTimestampTo(operation.dot) <= 0 ||
            !pageValues.containsKey(id),
      );
      if (pageValues.isEmpty) values!.remove(pageId);
      if (pageDots?.isEmpty == true) dots!.remove(pageId);
    }
    _rebuildRasterOperationCache(operation.targetId);
    final node = _nodes[operation.targetId];
    if (node?.payload is! DrawingPaperPayload) {
      return _CrdtHandlerDisposition.buffered;
    }
    final updated = _materializeRasterOperations(operation.targetId);
    return updated
        ? _CrdtHandlerDisposition.applied
        : _CrdtHandlerDisposition.buffered;
  }

  _CrdtHandlerDisposition _applyRasterOperation(CrdtOperation operation) {
    final raw = operation.value['operation'];
    if (raw is! Map) return _CrdtHandlerDisposition.rejected;
    final rawOperation = Map<String, dynamic>.from(raw);
    final operationId = rawOperation['id'];
    if (operationId is! String || operationId.trim().isEmpty) {
      return _CrdtHandlerDisposition.rejected;
    }
    final rawPageId = operation.value['pageId'];
    final pageId = rawPageId is String && rawPageId.trim().isNotEmpty
        ? rawPageId
        : rawPageId == null
        ? 'root-page'
        : null;
    if (pageId == null) return _CrdtHandlerDisposition.rejected;

    late final RasterEditOperation rasterOperation;
    try {
      rasterOperation = RasterEditOperation.fromJson(rawOperation);
    } catch (_) {
      return _CrdtHandlerDisposition.rejected;
    }
    if (rasterOperation.id != operationId) {
      return _CrdtHandlerDisposition.rejected;
    }
    final generationDot = _nodeGenerationDots[operation.targetId];
    if (generationDot != null &&
        !operation.dependencies.satisfies(
          CrdtVersionVector({generationDot.actorId: generationDot.counter}),
        )) {
      return _CrdtHandlerDisposition.applied;
    }

    final nodeOperations = _rasterOperationValues.putIfAbsent(
      operation.targetId,
      () => {},
    );
    final pageOperations = nodeOperations.putIfAbsent(pageId, () => {});
    final nodeDots = _rasterOperationDots.putIfAbsent(
      operation.targetId,
      () => {},
    );
    final pageDots = nodeDots.putIfAbsent(pageId, () => {});
    final resetDot = _rasterResetDots[operation.targetId]?[pageId];
    if (resetDot != null && resetDot.compareTimestampTo(operation.dot) >= 0) {
      return _CrdtHandlerDisposition.applied;
    }
    if (resetDot != null && resetDot.compareTimestampTo(operation.dot) < 0) {
      _rasterResetDots[operation.targetId]?.remove(pageId);
    }
    final existingDot = pageDots[operation.dot.key];
    if (existingDot != null &&
        existingDot.compareTimestampTo(operation.dot) >= 0) {
      return _CrdtHandlerDisposition.applied;
    }
    pageOperations[operation.dot.key] = rawOperation;
    pageDots[operation.dot.key] = operation.dot;
    _rebuildRasterOperationCache(operation.targetId);

    final node = _nodes[operation.targetId];
    final payload = node?.payload;
    if (node == null || payload is! DrawingPaperPayload) {
      return _CrdtHandlerDisposition.buffered;
    }
    final updated = _materializeRasterOperations(operation.targetId);
    return updated
        ? _CrdtHandlerDisposition.applied
        : _CrdtHandlerDisposition.buffered;
  }

  void _rebuildRasterOperationCache(String nodeId) {
    final values = _rasterOperationValues[nodeId];
    final dots = _rasterOperationDots[nodeId];
    if (values == null || dots == null) return;
    final records = <_RasterOperationRecord>[];
    for (final pageEntry in values.entries) {
      final pageDots = dots[pageEntry.key] ?? const <String, CrdtDot>{};
      for (final operationEntry in pageEntry.value.entries) {
        records.add(
          _RasterOperationRecord(
            pageId: pageEntry.key,
            operation: operationEntry.value,
            dot: pageDots[operationEntry.key],
          ),
        );
      }
    }
    records.sort((left, right) {
      final leftDot = left.dot;
      final rightDot = right.dot;
      if (leftDot == null && rightDot == null) {
        return (left.operation['id'] as String).compareTo(
          right.operation['id'] as String,
        );
      }
      if (leftDot == null) return -1;
      if (rightDot == null) return 1;
      final dotOrder = leftDot.compareTimestampTo(rightDot);
      if (dotOrder != 0) return dotOrder;
      return (left.operation['id'] as String).compareTo(
        right.operation['id'] as String,
      );
    });
    _rasterOperations[nodeId] = [
      for (final record in records) record.operation,
    ];
  }

  bool _materializeRasterOperations(String nodeId) {
    final node = _nodes[nodeId];
    final payload = node?.payload;
    if (node == null || payload is! DrawingPaperPayload) return false;
    var nextPayload = payload;
    final values = _rasterOperationValues[nodeId] ?? const {};
    final dots = _rasterOperationDots[nodeId] ?? const {};
    final pages = <String>{
      ...values.keys,
      ...dots.keys,
      ...?_rasterResetDots[nodeId]?.keys,
    };
    for (final pageId in pages) {
      final operations = values[pageId] ?? const {};
      final pageDots = dots[pageId] ?? const {};
      final ordered = operations.entries.toList()
        ..sort((left, right) {
          final leftDot = pageDots[left.key];
          final rightDot = pageDots[right.key];
          if (leftDot == null && rightDot == null) {
            return left.key.compareTo(right.key);
          }
          if (leftDot == null) return -1;
          if (rightDot == null) return 1;
          final dotOrder = leftDot.compareTimestampTo(rightDot);
          return dotOrder == 0 ? left.key.compareTo(right.key) : dotOrder;
        });
      final pagePayload = _findPagePayload(nextPayload, pageId);
      if (pagePayload == null) continue;
      final rasterOperations = <RasterEditOperation>[];
      for (final entry in ordered) {
        try {
          rasterOperations.add(RasterEditOperation.fromJson(entry.value));
        } catch (_) {
          continue;
        }
      }
      final resetDot = _rasterResetDots[nodeId]?[pageId];
      final revisionDots = [...pageDots.values, ?resetDot];
      final revision = _deriveRasterRevision(
        pagePayload,
        rasterOperations: rasterOperations,
        dots: revisionDots,
      );
      nextPayload = _updatePagePayload(
        nextPayload,
        pageId: pageId,
        update: (current) => current.copyWith(
          rasterOperations: rasterOperations,
          rasterRevision: revision,
        ),
      );
    }
    if (identical(nextPayload, payload)) return false;
    _nodes[nodeId] = node.copyWith(payload: nextPayload);
    return true;
  }

  int _deriveRasterRevision(
    DrawingPaperPayload payload, {
    Iterable<RasterEditOperation> rasterOperations = const [],
    Iterable<CrdtDot> dots = const [],
  }) {
    var revision = payload.rasterRevision;
    for (final dot in dots) {
      if (dot.counter > revision) revision = dot.counter;
    }
    return revision;
  }

  _CrdtHandlerDisposition _applyStrokeUpsert(CrdtOperation operation) {
    final pageId = operation.value['pageId'];
    final layerId = operation.value['layerId'];
    final strokeId = operation.value['strokeId'];
    final rawStroke = operation.value['stroke'];
    if (pageId is! String ||
        layerId is! String ||
        strokeId is! String ||
        rawStroke is! Map) {
      return _CrdtHandlerDisposition.rejected;
    }
    late final DrawingStroke stroke;
    try {
      stroke = DrawingStroke.fromJson(Map<String, dynamic>.from(rawStroke));
    } catch (_) {
      return _CrdtHandlerDisposition.rejected;
    }
    if (stroke.id != strokeId) return _CrdtHandlerDisposition.rejected;
    final key = _strokeKey(
      nodeId: operation.targetId,
      pageId: pageId,
      layerId: layerId,
      strokeId: strokeId,
    );
    _recordStrokeRevisionDot(
      nodeId: operation.targetId,
      pageId: pageId,
      dot: operation.dot,
    );
    final tombstone = _strokeTombstones[key];
    if (tombstone != null && tombstone.compareTimestampTo(operation.dot) >= 0) {
      _materializeStrokeRevision(operation.targetId, pageId);
      return _CrdtHandlerDisposition.applied;
    }
    final previous = _strokeDots[key];
    if (previous != null && previous.compareTimestampTo(operation.dot) > 0) {
      _materializeStrokeRevision(operation.targetId, pageId);
      return _CrdtHandlerDisposition.applied;
    }

    _strokeTombstones.remove(key);
    _strokeDots[key] = operation.dot;
    _strokeRegisters[key] = stroke;
    _recordStrokeRevisionDot(
      nodeId: operation.targetId,
      pageId: pageId,
      dot: operation.dot,
    );
    if (!_hasDrawingLayer(
      nodeId: operation.targetId,
      pageId: pageId,
      layerId: layerId,
    )) {
      return _CrdtHandlerDisposition.buffered;
    }
    _updateDrawingPayload(
      nodeId: operation.targetId,
      pageId: pageId,
      update: (payload) => _updateLayerStrokes(
        payload,
        nodeId: operation.targetId,
        pageId: pageId,
        layerId: layerId,
        replace: stroke,
        incrementRevision: false,
      ),
    );
    _materializeStrokeRevision(operation.targetId, pageId);
    return _CrdtHandlerDisposition.applied;
  }

  _CrdtHandlerDisposition _applyStrokeDelete(CrdtOperation operation) {
    final pageId = operation.value['pageId'];
    final layerId = operation.value['layerId'];
    final strokeId = operation.value['strokeId'];
    if (pageId is! String || layerId is! String || strokeId is! String) {
      return _CrdtHandlerDisposition.rejected;
    }
    _recordStrokeRevisionDot(
      nodeId: operation.targetId,
      pageId: pageId,
      dot: operation.dot,
    );
    final key = _strokeKey(
      nodeId: operation.targetId,
      pageId: pageId,
      layerId: layerId,
      strokeId: strokeId,
    );
    final previous = _strokeTombstones[key];
    if (previous != null && previous.compareTimestampTo(operation.dot) >= 0) {
      _materializeStrokeRevision(operation.targetId, pageId);
      return _CrdtHandlerDisposition.applied;
    }
    final strokeDot = _strokeDots[key];
    if (strokeDot != null && strokeDot.compareTimestampTo(operation.dot) > 0) {
      _materializeStrokeRevision(operation.targetId, pageId);
      return _CrdtHandlerDisposition.applied;
    }

    _strokeTombstones[key] = operation.dot;
    _strokeRegisters.remove(key);
    _recordStrokeRevisionDot(
      nodeId: operation.targetId,
      pageId: pageId,
      dot: operation.dot,
    );
    if (!_hasDrawingLayer(
      nodeId: operation.targetId,
      pageId: pageId,
      layerId: layerId,
    )) {
      return _CrdtHandlerDisposition.buffered;
    }
    _updateDrawingPayload(
      nodeId: operation.targetId,
      pageId: pageId,
      update: (payload) => _updateLayerStrokes(
        payload,
        nodeId: operation.targetId,
        pageId: pageId,
        layerId: layerId,
        deleteId: strokeId,
        incrementRevision: false,
      ),
    );
    _materializeStrokeRevision(operation.targetId, pageId);
    return _CrdtHandlerDisposition.applied;
  }

  void _recordStrokeRevisionDot({
    required String nodeId,
    required String pageId,
    required CrdtDot dot,
  }) {
    _strokeRevisionDots.putIfAbsent(nodeId, () => {})['$pageId|${dot.key}'] =
        dot;
  }

  void _materializeStrokeRevision(String nodeId, String pageId) {
    final node = _nodes[nodeId];
    final payload = node?.payload;
    if (node == null || payload is! DrawingPaperPayload) return;
    final pagePayload = _findPagePayload(payload, pageId);
    if (pagePayload == null) return;
    final dots =
        _strokeRevisionDots[nodeId]?.entries
            .where((entry) => entry.key.startsWith('$pageId|'))
            .map((entry) => entry.value) ??
        const <CrdtDot>[];
    final revision = _deriveRasterRevision(pagePayload, dots: dots);
    _updateDrawingPayload(
      nodeId: nodeId,
      pageId: pageId,
      update: (current) => current.copyWith(rasterRevision: revision),
    );
  }

  void _materializeAllStrokeRevisions(String nodeId) {
    final pages = _strokeRevisionDots[nodeId]?.keys
        .map((key) => key.split('|').first)
        .toSet();
    for (final pageId in pages ?? const <String>{}) {
      _materializeStrokeRevision(nodeId, pageId);
    }
  }

  String _strokeKey({
    required String nodeId,
    required String pageId,
    required String layerId,
    required String strokeId,
  }) => '$nodeId|$pageId|$layerId|$strokeId';

  bool _hasDrawingLayer({
    required String nodeId,
    required String pageId,
    required String layerId,
  }) {
    final node = _nodes[nodeId];
    final payload = node?.payload;
    if (payload is! DrawingPaperPayload) return false;
    final pagePayload = _findPagePayload(payload, pageId);
    return pagePayload?.layers.any((layer) => layer.id == layerId) ?? false;
  }

  DrawingPaperPayload? _findPagePayload(
    DrawingPaperPayload payload,
    String pageId,
  ) {
    if (pageId == 'root-page') return payload;
    for (final page in payload.studioPages) {
      if (page.id == pageId) return page.payload;
      final nested = _findPagePayload(page.payload, pageId);
      if (nested != null) return nested;
    }
    return null;
  }

  bool _updateDrawingPayload({
    required String nodeId,
    required String pageId,
    required DrawingPaperPayload Function(DrawingPaperPayload payload) update,
  }) {
    final node = _nodes[nodeId];
    final payload = node?.payload;
    if (node == null || payload is! DrawingPaperPayload) return false;
    final nextPayload = _updatePagePayload(
      payload,
      pageId: pageId,
      update: update,
    );
    if (identical(nextPayload, payload)) return false;
    _nodes[nodeId] = node.copyWith(payload: nextPayload);
    return true;
  }

  DrawingPaperPayload _updateLayerStrokes(
    DrawingPaperPayload payload, {
    required String nodeId,
    required String pageId,
    required String layerId,
    DrawingStroke? replace,
    String? deleteId,
    bool incrementRevision = true,
  }) {
    final layerIndex = payload.layers.indexWhere(
      (layer) => layer.id == layerId,
    );
    if (layerIndex < 0) return payload;
    final layer = payload.layers[layerIndex];
    final originalOrder = {
      for (var index = 0; index < layer.strokes.length; index++)
        layer.strokes[index].id: index,
    };
    final strokes = List<DrawingStroke>.from(layer.strokes);
    if (deleteId != null) {
      strokes.removeWhere((stroke) => stroke.id == deleteId);
    } else if (replace != null) {
      final index = strokes.indexWhere((stroke) => stroke.id == replace.id);
      if (index < 0) {
        strokes.add(replace);
      } else {
        strokes[index] = replace;
      }
    }
    strokes.sort((left, right) {
      final leftDot =
          _strokeDots[_strokeKey(
            nodeId: nodeId,
            pageId: pageId,
            layerId: layerId,
            strokeId: left.id,
          )];
      final rightDot =
          _strokeDots[_strokeKey(
            nodeId: nodeId,
            pageId: pageId,
            layerId: layerId,
            strokeId: right.id,
          )];
      if (leftDot == null && rightDot == null) {
        return (originalOrder[left.id] ?? 1 << 30).compareTo(
          originalOrder[right.id] ?? 1 << 30,
        );
      }
      if (leftDot == null) return -1;
      if (rightDot == null) return 1;
      return leftDot.compareTo(rightDot);
    });
    final layers = List<DrawingLayer>.from(payload.layers);
    layers[layerIndex] = layer.copyWith(strokes: strokes);
    return payload.copyWith(
      layers: layers,
      rasterRevision: incrementRevision
          ? payload.rasterRevision + 1
          : payload.rasterRevision,
    );
  }

  void _applyCommentUpsert(CrdtOperation operation) {
    final raw = operation.value['comment'];
    if (raw is! Map) return;
    final tombstone = _commentTombstones[operation.targetId];
    if (tombstone != null && tombstone.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    final previous = _commentDots[operation.targetId];
    if (previous != null && previous.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    _commentTombstones.remove(operation.targetId);
    _commentDots[operation.targetId] = operation.dot;
    final incoming = CanvasComment.fromJson(Map<String, dynamic>.from(raw));
    final existing = _comments[operation.targetId];
    final hasReplyOperations = _commentReplyDots.keys.any(
      (key) => key.startsWith('${operation.targetId}|'),
    );
    final hasReactionOperations = _commentReactionRegisters.keys.any(
      (key) => key.startsWith('${operation.targetId}|'),
    );
    _comments[operation.targetId] = incoming.copyWith(
      replies: hasReplyOperations
          ? existing?.replies ?? incoming.replies
          : null,
      reactions: hasReactionOperations
          ? existing?.reactions ?? incoming.reactions
          : null,
      resolved: _commentResolveRegisters[operation.targetId]?.value is bool
          ? _commentResolveRegisters[operation.targetId]!.value as bool
          : incoming.resolved,
    );
  }

  void _applyCommentDelete(CrdtOperation operation) {
    final previous = _commentTombstones[operation.targetId];
    if (previous != null && previous.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    final commentDot = _commentDots[operation.targetId];
    if (commentDot != null &&
        commentDot.compareTimestampTo(operation.dot) > 0) {
      return;
    }
    _commentTombstones[operation.targetId] = operation.dot;
    _comments.remove(operation.targetId);
  }

  void _applyCommentReplyUpsert(CrdtOperation operation) {
    final rawReply = operation.value['reply'];
    final comment = _comments[operation.targetId];
    if (rawReply is! Map || comment == null) return;
    final reply = CommentReply.fromJson(Map<String, dynamic>.from(rawReply));
    final key = '${operation.targetId}|${reply.id}';
    final tombstone = _commentReplyTombstones[key];
    if (tombstone != null && tombstone.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    final previous = _commentReplyDots[key];
    if (previous != null && previous.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    _commentReplyTombstones.remove(key);
    _commentReplyDots[key] = operation.dot;
    final replies =
        comment.replies.where((existing) => existing.id != reply.id).toList()
          ..add(reply);
    replies.sort((left, right) {
      final leftDot = _commentReplyDots['${operation.targetId}|${left.id}'];
      final rightDot = _commentReplyDots['${operation.targetId}|${right.id}'];
      if (leftDot == null && rightDot == null) return 0;
      if (leftDot == null) return -1;
      if (rightDot == null) return 1;
      return leftDot.compareTo(rightDot);
    });
    _comments[operation.targetId] = comment.copyWith(replies: replies);
  }

  void _applyCommentReplyDelete(CrdtOperation operation) {
    final comment = _comments[operation.targetId];
    final rawReplyId = operation.value['replyId'];
    if (comment == null || rawReplyId is! String) return;
    final key = '${operation.targetId}|$rawReplyId';
    final previousTombstone = _commentReplyTombstones[key];
    if (previousTombstone != null &&
        previousTombstone.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    final previous = _commentReplyDots[key];
    if (previous != null && previous.compareTimestampTo(operation.dot) > 0) {
      return;
    }
    _commentReplyTombstones[key] = operation.dot;
    _comments[operation.targetId] = comment.copyWith(
      replies: comment.replies
          .where((reply) => reply.id != rawReplyId)
          .toList(),
    );
  }

  void _applyCommentReactionSet(CrdtOperation operation) {
    final comment = _comments[operation.targetId];
    final userId = operation.value['userId'];
    final emoji = operation.value['emoji'];
    final active = operation.value['active'];
    if (comment == null ||
        userId is! String ||
        emoji is! String ||
        active is! bool) {
      return;
    }
    final key = '${operation.targetId}|$userId|$emoji';
    final previous = _commentReactionRegisters[key];
    if (previous != null &&
        previous.dot.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    final reactions = Map<String, int>.from(comment.reactions);
    final previousActive = previous?.value == true;
    if (previousActive) {
      reactions[emoji] = (reactions[emoji] ?? 1) - 1;
      if (reactions[emoji]! <= 0) reactions.remove(emoji);
    }
    if (active) reactions[emoji] = (reactions[emoji] ?? 0) + 1;
    _commentReactionRegisters[key] = CrdtRegisterValue(
      dot: operation.dot,
      value: active,
    );
    _comments[operation.targetId] = comment.copyWith(reactions: reactions);
  }

  void _applyCommentResolveSet(CrdtOperation operation) {
    final comment = _comments[operation.targetId];
    final resolved = operation.value['resolved'];
    if (comment == null || resolved is! bool) return;
    final previous = _commentResolveRegisters[operation.targetId];
    if (previous != null &&
        previous.dot.compareTimestampTo(operation.dot) >= 0) {
      return;
    }
    _commentResolveRegisters[operation.targetId] = CrdtRegisterValue(
      dot: operation.dot,
      value: resolved,
    );
    _comments[operation.targetId] = comment.copyWith(resolved: resolved);
  }

  void _materializeText(String nodeId, String field, String value) {
    final node = _nodes[nodeId];
    if (node == null) return;
    _nodes[nodeId] = _setTextField(node, field, value);
  }

  CrdtTextSequence _textSequenceFor(String nodeId, String field) {
    final key = '$nodeId|$field';
    final existing = _text[key];
    if (existing != null) return existing;
    final node = _nodes[nodeId];
    final initial = node == null ? '' : _readTextField(node, field) ?? '';
    final sequence = CrdtTextSequence.seed(initial);
    _text[key] = sequence;
    _seededText.add(key);
    return sequence;
  }

  void _seedTextForDocument(CanvasDocument document) {
    for (final node in document.nodes) {
      _seedTextForNode(node);
    }
  }

  void _seedTextForNode(CanvasNode node) {
    for (final field in const ['payload.text', 'payload.label', 'name']) {
      final value = _readTextField(node, field);
      if (value == null) continue;
      final key = '${node.id}|$field';
      if (_seededText.contains(key)) continue;
      _text[key] = CrdtTextSequence.seed(value);
      _seededText.add(key);
    }
  }

  Map<String, dynamic> snapshotState() => {
    'nodes': _nodes.map((id, node) => MapEntry(id, node.toPersistenceJson())),
    'edges': _edges.map((id, edge) => MapEntry(id, edge.toPersistenceJson())),
    'nodeDots': _nodeDots.map((id, dot) => MapEntry(id, dot.toJson())),
    'nodeGenerationDots': _nodeGenerationDots.map(
      (id, dot) => MapEntry(id, dot.toJson()),
    ),
    'edgeDots': _edgeDots.map((id, dot) => MapEntry(id, dot.toJson())),
    'nodeTombstones': _nodeTombstones.map(
      (id, dot) => MapEntry(id, dot.toJson()),
    ),
    'edgeTombstones': _edgeTombstones.map(
      (id, dot) => MapEntry(id, dot.toJson()),
    ),
    'commentDots': _commentDots.map((id, dot) => MapEntry(id, dot.toJson())),
    'commentTombstones': _commentTombstones.map(
      (id, dot) => MapEntry(id, dot.toJson()),
    ),
    'commentReplyDots': _commentReplyDots.map(
      (id, dot) => MapEntry(id, dot.toJson()),
    ),
    'commentReplyTombstones': _commentReplyTombstones.map(
      (id, dot) => MapEntry(id, dot.toJson()),
    ),
    'commentReactionRegisters': _commentReactionRegisters.map(
      (id, register) => MapEntry(id, register.toJson()),
    ),
    'commentResolveRegisters': _commentResolveRegisters.map(
      (id, register) => MapEntry(id, register.toJson()),
    ),
    'strokeDots': _strokeDots.map((id, dot) => MapEntry(id, dot.toJson())),
    'strokeRegisters': _strokeRegisters.map(
      (id, stroke) => MapEntry(id, stroke.toJson()),
    ),
    'strokeTombstones': _strokeTombstones.map(
      (id, dot) => MapEntry(id, dot.toJson()),
    ),
    'strokeRevisionDots': _strokeRevisionDots.map(
      (nodeId, pageDots) => MapEntry(
        nodeId,
        pageDots.map((key, dot) => MapEntry(key, dot.toJson())),
      ),
    ),
    'assets': _assets.map(
      (id, asset) => MapEntry(id, asset.toPersistenceJson()),
    ),
    'assetDots': _assetDots.map((id, dot) => MapEntry(id, dot.toJson())),
    'assetTombstones': _assetTombstones.map(
      (id, dot) => MapEntry(id, dot.toJson()),
    ),
    'tokens': _tokens.map((id, token) => MapEntry(id, token.toJson())),
    'tokenSetVersion': _tokenSetVersion,
    'tokenModes': _tokenModes,
    'tokenDots': _tokenDots.map((id, dot) => MapEntry(id, dot.toJson())),
    'tokenTombstones': _tokenTombstones.map(
      (id, dot) => MapEntry(id, dot.toJson()),
    ),
    'fieldRegisters': _fieldRegisters.map(
      (key, register) => MapEntry(key, register.toJson()),
    ),
    'text': _text.map((key, sequence) => MapEntry(key, sequence.toJson())),
    'rasterOperations': _rasterOperations,
    'rasterOperationValues': _rasterOperationValues,
    'rasterOperationDots': _rasterOperationDots.map(
      (nodeId, pages) => MapEntry(
        nodeId,
        pages.map(
          (pageId, operations) => MapEntry(
            pageId,
            operations.map((id, dot) => MapEntry(id, dot.toJson())),
          ),
        ),
      ),
    ),
    'rasterResetDots': _rasterResetDots.map(
      (nodeId, pages) => MapEntry(
        nodeId,
        pages.map((pageId, dot) => MapEntry(pageId, dot.toJson())),
      ),
    ),
  };

  void _restoreState(Map<String, dynamic> state) {
    void restoreNodes(Object? raw) {
      if (raw is! Map) return;
      _nodes.clear();
      for (final entry in raw.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        try {
          final node = CanvasNode.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
          _nodes[entry.key as String] = node;
        } catch (_) {
          // Preserve valid snapshot entries when one node is corrupt.
        }
      }
    }

    void restoreEdges(Object? raw) {
      if (raw is! Map) return;
      _edges.clear();
      for (final entry in raw.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        try {
          final edge = CanvasEdge.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
          _edges[entry.key as String] = edge;
        } catch (_) {
          // Preserve valid snapshot entries when one edge is corrupt.
        }
      }
    }

    Map<String, CrdtDot> readDots(Object? raw) {
      if (raw is! Map) return {};
      final result = <String, CrdtDot>{};
      for (final entry in raw.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        try {
          result[entry.key as String] = CrdtDot.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        } catch (_) {
          // Ignore malformed register metadata without dropping the snapshot.
        }
      }
      return result;
    }

    Map<String, CrdtRegisterValue> readRegisters(Object? raw) {
      if (raw is! Map) return {};
      final result = <String, CrdtRegisterValue>{};
      for (final entry in raw.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        try {
          result[entry.key as String] = CrdtRegisterValue.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        } catch (_) {
          // Ignore malformed register metadata without dropping the snapshot.
        }
      }
      return result;
    }

    restoreNodes(state['nodes']);
    restoreEdges(state['edges']);
    final rawAssets = state['assets'];
    if (rawAssets is Map) {
      final restoredAssets = <String, DocumentAsset>{};
      for (final entry in rawAssets.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final asset = DocumentAsset.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (entry.key != asset.id) {
          throw FormatException(
            'CRDT asset snapshot key "${entry.key}" does not match asset ID '
            '"${asset.id}".',
          );
        }
        restoredAssets[entry.key as String] = asset;
      }
      DocumentAssetManifest(entries: restoredAssets).validateIdentity();
      _assets
        ..clear()
        ..addAll(restoredAssets);
    }
    final rawTokens = state['tokens'];
    if (rawTokens is Map) {
      _tokens
        ..clear()
        ..addAll({
          for (final entry in rawTokens.entries)
            if (entry.key is String && entry.value is Map)
              entry.key as String: DesignToken.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              ),
        });
    }
    final rawTokenModes = state['tokenModes'];
    if (rawTokenModes is List) {
      final modes = rawTokenModes
          .whereType<String>()
          .where((mode) => mode.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (modes.isNotEmpty) _tokenModes = modes;
    }
    final rawTokenVersion = state['tokenSetVersion'];
    if (rawTokenVersion is num && rawTokenVersion.toInt() > 0) {
      _tokenSetVersion = rawTokenVersion.toInt();
    }
    _nodeDots
      ..clear()
      ..addAll(readDots(state['nodeDots']));
    _nodeGenerationDots
      ..clear()
      ..addAll(readDots(state['nodeGenerationDots']));
    _edgeDots
      ..clear()
      ..addAll(readDots(state['edgeDots']));
    _nodeTombstones
      ..clear()
      ..addAll(readDots(state['nodeTombstones']));
    _edgeTombstones
      ..clear()
      ..addAll(readDots(state['edgeTombstones']));
    _commentDots
      ..clear()
      ..addAll(readDots(state['commentDots']));
    _commentTombstones
      ..clear()
      ..addAll(readDots(state['commentTombstones']));
    _commentReplyDots
      ..clear()
      ..addAll(readDots(state['commentReplyDots']));
    _commentReplyTombstones
      ..clear()
      ..addAll(readDots(state['commentReplyTombstones']));
    _commentReactionRegisters
      ..clear()
      ..addAll(readRegisters(state['commentReactionRegisters']));
    _commentResolveRegisters
      ..clear()
      ..addAll(readRegisters(state['commentResolveRegisters']));
    _strokeDots
      ..clear()
      ..addAll(readDots(state['strokeDots']));
    final rawStrokeRegisters = state['strokeRegisters'];
    if (rawStrokeRegisters is Map) {
      final restoredStrokes = <String, DrawingStroke>{};
      for (final entry in rawStrokeRegisters.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        try {
          restoredStrokes[entry.key as String] = DrawingStroke.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        } catch (_) {
          // Ignore malformed stroke entries while restoring the rest.
        }
      }
      _strokeRegisters
        ..clear()
        ..addAll(restoredStrokes);
    }
    _strokeTombstones
      ..clear()
      ..addAll(readDots(state['strokeTombstones']));
    final rawStrokeRevisionDots = state['strokeRevisionDots'];
    if (rawStrokeRevisionDots is Map) {
      _strokeRevisionDots
        ..clear()
        ..addAll({
          for (final nodeEntry in rawStrokeRevisionDots.entries)
            if (nodeEntry.key is String && nodeEntry.value is Map)
              nodeEntry.key as String: readDots(nodeEntry.value),
        });
    }
    _assetDots
      ..clear()
      ..addAll(readDots(state['assetDots']));
    _assetTombstones
      ..clear()
      ..addAll(readDots(state['assetTombstones']));
    _tokenDots
      ..clear()
      ..addAll(readDots(state['tokenDots']));
    _tokenTombstones
      ..clear()
      ..addAll(readDots(state['tokenTombstones']));

    final rawRegisters = state['fieldRegisters'];
    if (rawRegisters is Map) {
      _fieldRegisters
        ..clear()
        ..addAll({
          for (final entry in rawRegisters.entries)
            if (entry.key is String && entry.value is Map)
              entry.key as String: CrdtRegisterValue.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              ),
        });
    }

    final rawText = state['text'];
    if (rawText is Map) {
      _text
        ..clear()
        ..addAll({
          for (final entry in rawText.entries)
            if (entry.key is String && entry.value is Map)
              entry.key as String: CrdtTextSequence.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              ),
        });
      _seededText.addAll(_text.keys);
    }

    final rawRaster = state['rasterOperations'];
    if (rawRaster is Map) {
      _rasterOperations
        ..clear()
        ..addAll({
          for (final entry in rawRaster.entries)
            if (entry.key is String && entry.value is List)
              entry.key as String: [
                for (final value in entry.value)
                  if (value is Map) Map<String, dynamic>.from(value),
              ],
        });
    }
    final rawRasterValues = state['rasterOperationValues'];
    if (rawRasterValues is Map) {
      _rasterOperationValues
        ..clear()
        ..addAll({
          for (final nodeEntry in rawRasterValues.entries)
            if (nodeEntry.key is String && nodeEntry.value is Map)
              nodeEntry.key as String: {
                for (final pageEntry in (nodeEntry.value as Map).entries)
                  if (pageEntry.key is String && pageEntry.value is Map)
                    pageEntry.key as String: {
                      for (final operationEntry
                          in (pageEntry.value as Map).entries)
                        if (operationEntry.key is String &&
                            operationEntry.value is Map)
                          operationEntry.key
                              as String: Map<String, dynamic>.from(
                            operationEntry.value as Map,
                          ),
                    },
              },
        });
    }
    final rawRasterDots = state['rasterOperationDots'];
    if (rawRasterDots is Map) {
      _rasterOperationDots
        ..clear()
        ..addAll({
          for (final nodeEntry in rawRasterDots.entries)
            if (nodeEntry.key is String && nodeEntry.value is Map)
              nodeEntry.key as String: {
                for (final pageEntry in (nodeEntry.value as Map).entries)
                  if (pageEntry.key is String && pageEntry.value is Map)
                    pageEntry.key as String: readDots(pageEntry.value),
              },
        });
    }
    final rawRasterResetDots = state['rasterResetDots'];
    if (rawRasterResetDots is Map) {
      _rasterResetDots
        ..clear()
        ..addAll({
          for (final nodeEntry in rawRasterResetDots.entries)
            if (nodeEntry.key is String && nodeEntry.value is Map)
              nodeEntry.key as String: readDots(nodeEntry.value),
        });
    }
    _seedRasterOperationsForCurrentNodes();
    for (final nodeId in <String>{
      ..._rasterOperationValues.keys,
      ..._rasterOperationDots.keys,
      ..._rasterResetDots.keys,
    }) {
      _rebuildRasterOperationCache(nodeId);
      _materializeRasterOperations(nodeId);
    }
    for (final node in _nodes.values) {
      _reapplyNodeFields(node.id);
    }
  }

  CanvasDocument _materializeDocument() {
    return _baseDocument.copyWith(
      nodes: List<CanvasNode>.unmodifiable(_nodes.values),
      edges: List<CanvasEdge>.unmodifiable(_edges.values),
      assets: DocumentAssetManifest(entries: _assets),
      tokens: DesignTokenSet(
        version: _tokenSetVersion,
        modes: _tokenModes,
        entries: _tokens,
      ),
      updatedAt: _baseDocument.updatedAt,
    );
  }

  String? _readTextField(CanvasNode node, String field) {
    if (field == 'name') return node.name;
    if (field == 'payload.text') {
      final payload = node.payload;
      if (payload is TextPayload) return payload.text;
      if (payload is StickyNotePayload) return payload.text;
    }
    if (field == 'payload.label' && node.payload is ShapePayload) {
      return (node.payload as ShapePayload).label;
    }
    return null;
  }

  CanvasNode _setTextField(CanvasNode node, String field, String value) {
    if (field == 'name') return node.copyWith(name: value);
    if (field == 'payload.text') {
      final payload = node.payload;
      if (payload is TextPayload) {
        return node.copyWith(payload: payload.copyWith(text: value));
      }
      if (payload is StickyNotePayload) {
        return node.copyWith(payload: payload.copyWith(text: value));
      }
    }
    if (field == 'payload.label' && node.payload is ShapePayload) {
      return node.copyWith(
        payload: (node.payload as ShapePayload).copyWith(label: value),
      );
    }
    return node;
  }

  CanvasNode _setNodeField(CanvasNode node, String field, Object? value) {
    switch (field) {
      case 'x':
        return node.copyWith(x: _doubleValue(value, node.x));
      case 'y':
        return node.copyWith(y: _doubleValue(value, node.y));
      case 'width':
        return node.copyWith(width: _doubleValue(value, node.width));
      case 'height':
        return node.copyWith(height: _doubleValue(value, node.height));
      case 'rotation':
        return node.copyWith(rotation: _doubleValue(value, node.rotation));
      case 'opacity':
        return node.copyWith(opacity: _doubleValue(value, node.opacity));
      case 'zIndex':
        return node.copyWith(zIndex: _intValue(value, node.zIndex));
      case 'visible':
        return node.copyWith(visible: value as bool? ?? node.visible);
      case 'locked':
        return node.copyWith(locked: value as bool? ?? node.locked);
      case 'parentId':
        return node.copyWith(parentId: value as String?);
      case 'name':
        return node.copyWith(name: value as String?);
      case 'payload':
        if (value is Map) {
          return node.copyWith(
            payload: NodePayload.fromJson(
              node.type,
              Map<String, dynamic>.from(value),
            ),
          );
        }
    }
    return node;
  }

  double _doubleValue(Object? value, double fallback) =>
      value is num && value.toDouble().isFinite ? value.toDouble() : fallback;

  int _intValue(Object? value, int fallback) =>
      value is num ? value.toInt() : fallback;
}

extension CrdtCanvasCommentSnapshot on CrdtDocumentSession {
  List<CanvasComment> get comments => List.unmodifiable(_comments.values);

  String encodeState() => jsonEncode({
    'projectId': projectId,
    'version': version.toJson(),
    'document': document.toPersistenceJson(),
    'comments': comments.map((comment) => comment.toJson()).toList(),
    'crdt': snapshotState(),
  });
}
