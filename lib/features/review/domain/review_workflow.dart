enum ReviewApprovalState { draft, inReview, changesRequested, approved }

class ReviewChecklistItem {
  final String id;
  final String label;
  final bool completed;
  final String? completedBy;
  final DateTime? completedAt;

  const ReviewChecklistItem({
    required this.id,
    required this.label,
    this.completed = false,
    this.completedBy,
    this.completedAt,
  });

  ReviewChecklistItem copyWith({
    String? id,
    String? label,
    bool? completed,
    Object? completedBy = _unset,
    Object? completedAt = _unset,
  }) => ReviewChecklistItem(
    id: id ?? this.id,
    label: label ?? this.label,
    completed: completed ?? this.completed,
    completedBy: completedBy == _unset
        ? this.completedBy
        : completedBy as String?,
    completedAt: completedAt == _unset
        ? this.completedAt
        : completedAt as DateTime?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'completed': completed,
    'completedBy': completedBy,
    'completedAt': completedAt?.toUtc().toIso8601String(),
  };

  factory ReviewChecklistItem.fromJson(Map<String, dynamic> json) =>
      ReviewChecklistItem(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        completed: json['completed'] as bool? ?? false,
        completedBy: json['completedBy']?.toString(),
        completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
      );

  static const Object _unset = Object();
}

class ReviewWalkthroughStep {
  final String id;
  final String title;
  final String description;
  final String? nodeId;
  final int order;

  const ReviewWalkthroughStep({
    required this.id,
    required this.title,
    this.description = '',
    this.nodeId,
    this.order = 0,
  });

  ReviewWalkthroughStep copyWith({
    String? id,
    String? title,
    String? description,
    Object? nodeId = _unset,
    int? order,
  }) => ReviewWalkthroughStep(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    nodeId: nodeId == _unset ? this.nodeId : nodeId as String?,
    order: order ?? this.order,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'nodeId': nodeId,
    'order': order,
  };

  factory ReviewWalkthroughStep.fromJson(Map<String, dynamic> json) =>
      ReviewWalkthroughStep(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        nodeId: json['nodeId']?.toString(),
        order: (json['order'] as num?)?.toInt() ?? 0,
      );

  static const Object _unset = Object();
}

class ReviewWorkflow {
  static const int schemaVersion = 1;

  final String projectId;
  final ReviewApprovalState approvalState;
  final List<String> reviewerIds;
  final String? updatedBy;
  final DateTime updatedAt;
  final String? spotlightNodeId;
  final DateTime? spotlightExpiresAt;
  final List<ReviewChecklistItem> handoffChecklist;
  final List<ReviewWalkthroughStep> walkthrough;
  final Map<String, String> speakerNotes;

  const ReviewWorkflow({
    required this.projectId,
    this.approvalState = ReviewApprovalState.draft,
    this.reviewerIds = const [],
    this.updatedBy,
    required this.updatedAt,
    this.spotlightNodeId,
    this.spotlightExpiresAt,
    this.handoffChecklist = const [],
    this.walkthrough = const [],
    this.speakerNotes = const {},
  });

  factory ReviewWorkflow.empty(String projectId) =>
      ReviewWorkflow(projectId: projectId, updatedAt: DateTime.now().toUtc());

  List<ReviewWalkthroughStep> get orderedWalkthrough {
    final result = List<ReviewWalkthroughStep>.from(walkthrough)
      ..sort((a, b) {
        final order = a.order.compareTo(b.order);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });
    return List.unmodifiable(result);
  }

  bool isReviewer(String actorId) => reviewerIds.contains(actorId.trim());

  bool canReview(String actorId, {required bool canEditCanvas}) =>
      canEditCanvas || isReviewer(actorId);

  bool isSpotlightActive([DateTime? now]) {
    final nodeId = spotlightNodeId?.trim();
    if (nodeId == null || nodeId.isEmpty) return false;
    final expiresAt = spotlightExpiresAt;
    return expiresAt == null || expiresAt.isAfter(now ?? DateTime.now());
  }

  ReviewWorkflow copyWith({
    String? projectId,
    ReviewApprovalState? approvalState,
    List<String>? reviewerIds,
    Object? updatedBy = _unset,
    DateTime? updatedAt,
    Object? spotlightNodeId = _unset,
    Object? spotlightExpiresAt = _unset,
    List<ReviewChecklistItem>? handoffChecklist,
    List<ReviewWalkthroughStep>? walkthrough,
    Map<String, String>? speakerNotes,
  }) => ReviewWorkflow(
    projectId: projectId ?? this.projectId,
    approvalState: approvalState ?? this.approvalState,
    reviewerIds: reviewerIds ?? this.reviewerIds,
    updatedBy: updatedBy == _unset ? this.updatedBy : updatedBy as String?,
    updatedAt: updatedAt ?? this.updatedAt,
    spotlightNodeId: spotlightNodeId == _unset
        ? this.spotlightNodeId
        : spotlightNodeId as String?,
    spotlightExpiresAt: spotlightExpiresAt == _unset
        ? this.spotlightExpiresAt
        : spotlightExpiresAt as DateTime?,
    handoffChecklist: handoffChecklist ?? this.handoffChecklist,
    walkthrough: walkthrough ?? this.walkthrough,
    speakerNotes: speakerNotes ?? this.speakerNotes,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'projectId': projectId,
    'approvalState': approvalState.name,
    'reviewerIds': reviewerIds,
    'updatedBy': updatedBy,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'spotlightNodeId': spotlightNodeId,
    'spotlightExpiresAt': spotlightExpiresAt?.toUtc().toIso8601String(),
    'handoffChecklist': handoffChecklist.map((item) => item.toJson()).toList(),
    'walkthrough': walkthrough.map((step) => step.toJson()).toList(),
    'speakerNotes': speakerNotes,
  };

  factory ReviewWorkflow.fromJson(Map<String, dynamic> json) {
    final rawState = json['approvalState']?.toString();
    final state = ReviewApprovalState.values.firstWhere(
      (value) => value.name == rawState,
      orElse: () => ReviewApprovalState.draft,
    );
    final rawReviewers = json['reviewerIds'];
    final rawChecklist = json['handoffChecklist'];
    final rawWalkthrough = json['walkthrough'];
    final rawNotes = json['speakerNotes'];
    return ReviewWorkflow(
      projectId: json['projectId']?.toString() ?? '',
      approvalState: state,
      reviewerIds: rawReviewers is List
          ? _uniqueStrings(rawReviewers)
          : const [],
      updatedBy: json['updatedBy']?.toString(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      spotlightNodeId: json['spotlightNodeId']?.toString(),
      spotlightExpiresAt: DateTime.tryParse(
        json['spotlightExpiresAt']?.toString() ?? '',
      )?.toUtc(),
      handoffChecklist: rawChecklist is List
          ? [
              for (final item in rawChecklist)
                if (item is Map)
                  ReviewChecklistItem.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      walkthrough: rawWalkthrough is List
          ? [
              for (final item in rawWalkthrough)
                if (item is Map)
                  ReviewWalkthroughStep.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
            ]
          : const [],
      speakerNotes: rawNotes is Map
          ? {
              for (final entry in rawNotes.entries)
                entry.key.toString(): entry.value.toString(),
            }
          : const {},
    );
  }

  static List<String> _uniqueStrings(Iterable<Object?> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = value?.toString().trim() ?? '';
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      result.add(normalized);
    }
    return List.unmodifiable(result);
  }

  static const Object _unset = Object();
}
