import 'dart:convert';

import '../../../domain/models/ai_job.dart';
import '../../../domain/models/collaboration.dart';
import '../../../domain/models/document_asset.dart';
import '../../../domain/models/node.dart';
import '../../history/snapshot_manager.dart';
import '../domain/semantic_index.dart';

class SemanticIndexSources {
  const SemanticIndexSources._();

  static List<SemanticIndexRecord> fromCanvas({
    required Iterable<CanvasNode> nodes,
    required Iterable<DocumentAsset> assets,
    required Iterable<CanvasComment> comments,
    required Iterable<DocumentSnapshotRecord> versions,
    required Iterable<AIJob> jobs,
    DateTime? indexedAt,
  }) {
    final now = (indexedAt ?? DateTime.now()).toUtc();
    return [
      ...nodes.map((node) => nodeRecord(node, indexedAt: now)),
      ...assets.map(assetRecord),
      ...comments.map(commentRecord),
      ...versions.map(versionRecord),
      ...jobs.where((job) => job.provenance.isNotEmpty).map(provenanceRecord),
    ];
  }

  static SemanticIndexRecord nodeRecord(
    CanvasNode node, {
    DateTime? indexedAt,
  }) {
    final title = node.name?.trim();
    return SemanticIndexRecord(
      id: node.id,
      kind: SemanticRecordKind.node,
      title: title == null || title.isEmpty ? node.type.name : title,
      content: jsonEncode(node.payload.toPersistenceJson()),
      tags: [
        node.type.name,
        if (node.pageId != null) 'page:${node.pageId}',
        if (node.parentId != null) 'parent:${node.parentId}',
      ],
      references: [
        if (node.pageId != null) node.pageId!,
        if (node.parentId != null) node.parentId!,
        if (node.variantOfNodeId != null) node.variantOfNodeId!,
      ],
      updatedAt: indexedAt ?? DateTime.now().toUtc(),
      metadata: {
        'type': node.type.name,
        'visible': node.visible,
        'locked': node.locked,
        'bounds': {
          'x': node.x,
          'y': node.y,
          'width': node.width,
          'height': node.height,
        },
      },
    );
  }

  static SemanticIndexRecord assetRecord(DocumentAsset asset) =>
      SemanticIndexRecord(
        id: asset.id,
        kind: SemanticRecordKind.asset,
        title: asset.name,
        content: [
          asset.mimeType,
          asset.license,
          asset.durableReference,
          jsonEncode(asset.metadata),
        ].whereType<String>().join(' '),
        tags: [asset.kind.name, asset.storage.name, ...asset.tags],
        references: [
          if (asset.folderId != null) asset.folderId!,
          if (asset.duplicateOf != null) asset.duplicateOf!,
          if (asset.checksum != null) asset.checksum!,
        ],
        updatedAt: asset.updatedAt,
        metadata: {
          ...asset.metadata,
          'mimeType': asset.mimeType,
          'license': asset.license,
          'sizeBytes': asset.sizeBytes,
          'checksum': asset.checksum,
        },
      );

  static SemanticIndexRecord commentRecord(CanvasComment comment) =>
      SemanticIndexRecord(
        id: comment.id,
        kind: SemanticRecordKind.comment,
        title: 'Comment by ${comment.authorName}',
        content: [
          comment.text,
          ...comment.replies.map((reply) => reply.text),
          comment.assigneeName,
        ].whereType<String>().join(' '),
        tags: [
          ...comment.normalizedLabels,
          ...comment.mentions,
          if (comment.resolved) 'resolved',
          if (comment.dueDate != null) 'due-date',
        ],
        references: [
          if (comment.nodeId != null) comment.nodeId!,
          if (comment.feedbackThreadId != null) comment.feedbackThreadId!,
          if (comment.assigneeId != null) comment.assigneeId!,
          ...comment.watchers,
        ],
        updatedAt: (comment.editedAt ?? comment.createdAt).toUtc(),
        metadata: {
          'authorId': comment.authorId,
          'resolved': comment.resolved,
          'replyCount': comment.replies.length,
          'attachmentCount': comment.attachments.length,
          'dueDate': comment.dueDate?.toUtc().toIso8601String(),
        },
      );

  static SemanticIndexRecord versionRecord(DocumentSnapshotRecord snapshot) =>
      SemanticIndexRecord(
        id: snapshot.id,
        kind: SemanticRecordKind.version,
        title: snapshot.description,
        content: [
          snapshot.description,
          ...snapshot.document.nodes.map(
            (node) => '${node.name ?? ''} ${node.type.name}',
          ),
        ].join(' '),
        tags: const ['version'],
        references: [snapshot.document.projectId],
        updatedAt: snapshot.timestamp.toUtc(),
        metadata: {
          'commandCount': snapshot.commandReplay?.entries.length ?? 0,
          'nodeCount': snapshot.document.nodes.length,
        },
      );

  static SemanticIndexRecord provenanceRecord(AIJob job) => SemanticIndexRecord(
    id: 'provenance:${job.id}',
    kind: SemanticRecordKind.provenance,
    title: '${job.capability.name} provenance',
    content: [
      job.prompt,
      job.provider,
      job.model,
      jsonEncode(job.provenance),
    ].whereType<String>().join(' '),
    tags: ['ai', job.capability.name, if (job.provider != null) job.provider!],
    references: [
      ...job.sourceNodeIds,
      ...job.sourceAssetIds,
      if (job.resultArtifact?.reference != null) job.resultArtifact!.reference!,
    ],
    updatedAt: job.updatedAt.toUtc(),
    metadata: {
      ...job.provenance,
      'provider': job.provider,
      'model': job.model,
      'estimatedCost': job.estimatedCost,
      'actualCost': job.actualCost,
      'jobStatus': job.status.name,
    },
  );
}
