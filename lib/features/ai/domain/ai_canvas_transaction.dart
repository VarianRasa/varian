import '../data/ai_canvas_actions.dart';

enum AICanvasTransactionPhase {
  preview,
  applying,
  applied,
  inserted,
  replaced,
  rejected,
  retrying,
  canceled,
  failed,
  undone,
}

extension AICanvasTransactionPhaseDetails on AICanvasTransactionPhase {
  String get label {
    switch (this) {
      case AICanvasTransactionPhase.preview:
        return 'Preview';
      case AICanvasTransactionPhase.applying:
        return 'Applying';
      case AICanvasTransactionPhase.applied:
        return 'Applied';
      case AICanvasTransactionPhase.inserted:
        return 'Inserted';
      case AICanvasTransactionPhase.replaced:
        return 'Replaced';
      case AICanvasTransactionPhase.rejected:
        return 'Rejected';
      case AICanvasTransactionPhase.retrying:
        return 'Retrying';
      case AICanvasTransactionPhase.canceled:
        return 'Canceled';
      case AICanvasTransactionPhase.failed:
        return 'Failed';
      case AICanvasTransactionPhase.undone:
        return 'Undone';
    }
  }

  bool get isTerminal => switch (this) {
    AICanvasTransactionPhase.preview ||
    AICanvasTransactionPhase.applying ||
    AICanvasTransactionPhase.retrying => false,
    _ => true,
  };

  bool get canRetry => switch (this) {
    AICanvasTransactionPhase.failed ||
    AICanvasTransactionPhase.rejected ||
    AICanvasTransactionPhase.canceled => true,
    _ => false,
  };

  bool get canUndo => switch (this) {
    AICanvasTransactionPhase.applied ||
    AICanvasTransactionPhase.inserted ||
    AICanvasTransactionPhase.replaced => true,
    _ => false,
  };
}

enum AICanvasTransactionOperation {
  apply,
  insert,
  replace,
  retry,
  reject,
  cancel,
  undo,
}

extension AICanvasTransactionOperationDetails on AICanvasTransactionOperation {
  String get label {
    switch (this) {
      case AICanvasTransactionOperation.apply:
        return 'Apply';
      case AICanvasTransactionOperation.insert:
        return 'Insert';
      case AICanvasTransactionOperation.replace:
        return 'Replace';
      case AICanvasTransactionOperation.retry:
        return 'Retry';
      case AICanvasTransactionOperation.reject:
        return 'Reject';
      case AICanvasTransactionOperation.cancel:
        return 'Cancel';
      case AICanvasTransactionOperation.undo:
        return 'Undo';
    }
  }
}

class AICanvasTransactionEntry {
  final String id;
  final String projectId;
  final AICanvasAction action;
  final AICanvasActionPreview? preview;
  final AICanvasTransactionPhase phase;
  final AICanvasTransactionOperation? operation;
  final AICanvasActionStatus? resultStatus;
  final String? resultId;
  final String? message;
  final String? text;
  final String? suggestedTitle;
  final List<String> affectedNodeIds;
  final int attempts;
  final int? undoDepth;
  final DateTime createdAt;
  final DateTime updatedAt;

  AICanvasTransactionEntry({
    required this.id,
    required this.projectId,
    required this.action,
    this.preview,
    this.phase = AICanvasTransactionPhase.preview,
    this.operation,
    this.resultStatus,
    this.resultId,
    this.message,
    this.text,
    this.suggestedTitle,
    List<String> affectedNodeIds = const [],
    this.attempts = 0,
    this.undoDepth,
    required this.createdAt,
    required this.updatedAt,
  }) : affectedNodeIds = List.unmodifiable(affectedNodeIds);

  bool get isPending =>
      phase == AICanvasTransactionPhase.preview ||
      phase == AICanvasTransactionPhase.applying ||
      phase == AICanvasTransactionPhase.retrying;

  bool get canApply => phase == AICanvasTransactionPhase.preview;
  bool get canCancel => isPending;

  AICanvasTransactionEntry copyWith({
    String? id,
    String? projectId,
    AICanvasAction? action,
    Object? preview = _sentinel,
    AICanvasTransactionPhase? phase,
    Object? operation = _sentinel,
    Object? resultStatus = _sentinel,
    Object? resultId = _sentinel,
    Object? message = _sentinel,
    Object? text = _sentinel,
    Object? suggestedTitle = _sentinel,
    List<String>? affectedNodeIds,
    int? attempts,
    Object? undoDepth = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AICanvasTransactionEntry(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    action: action ?? this.action,
    preview: preview == _sentinel
        ? this.preview
        : preview as AICanvasActionPreview?,
    phase: phase ?? this.phase,
    operation: operation == _sentinel
        ? this.operation
        : operation as AICanvasTransactionOperation?,
    resultStatus: resultStatus == _sentinel
        ? this.resultStatus
        : resultStatus as AICanvasActionStatus?,
    resultId: resultId == _sentinel ? this.resultId : resultId as String?,
    message: message == _sentinel ? this.message : message as String?,
    text: text == _sentinel ? this.text : text as String?,
    suggestedTitle: suggestedTitle == _sentinel
        ? this.suggestedTitle
        : suggestedTitle as String?,
    affectedNodeIds: affectedNodeIds ?? this.affectedNodeIds,
    attempts: attempts ?? this.attempts,
    undoDepth: undoDepth == _sentinel ? this.undoDepth : undoDepth as int?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'action': action.toJson(),
    'phase': phase.name,
    'operation': operation?.name,
    'resultStatus': resultStatus?.name,
    'resultId': resultId,
    'message': message,
    'text': text,
    'suggestedTitle': suggestedTitle,
    'affectedNodeIds': affectedNodeIds,
    'attempts': attempts,
    'undoDepth': undoDepth,
    'documentFingerprint': preview?.documentFingerprint,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  Map<String, dynamic> toPersistenceJson() => toJson();

  factory AICanvasTransactionEntry.fromJson(Map<String, dynamic> json) {
    final rawAction = json['action'];
    if (rawAction is! Map) {
      throw const FormatException('AI canvas transaction action is missing.');
    }
    final action = AICanvasAction.fromJson(
      Map<String, dynamic>.from(rawAction),
    );
    final rawId = json['id'];
    final rawProjectId = json['projectId'];
    final rawCreatedAt = json['createdAt'];
    final rawUpdatedAt = json['updatedAt'];
    if (rawId is! String ||
        rawProjectId is! String ||
        rawCreatedAt is! String ||
        rawUpdatedAt is! String) {
      throw const FormatException('AI canvas transaction metadata is invalid.');
    }
    return AICanvasTransactionEntry(
      id: rawId,
      projectId: rawProjectId,
      action: action,
      phase: _enumValue(
        AICanvasTransactionPhase.values,
        json['phase'] as String?,
        AICanvasTransactionPhase.failed,
      ),
      operation: _enumValueOrNull(
        AICanvasTransactionOperation.values,
        json['operation'] as String?,
      ),
      resultStatus: _enumValueOrNull(
        AICanvasActionStatus.values,
        json['resultStatus'] as String?,
      ),
      resultId: json['resultId'] as String?,
      message: json['message'] as String?,
      text: json['text'] as String?,
      suggestedTitle: json['suggestedTitle'] as String?,
      affectedNodeIds: (json['affectedNodeIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      undoDepth: (json['undoDepth'] as num?)?.toInt(),
      createdAt: DateTime.parse(rawCreatedAt),
      updatedAt: DateTime.parse(rawUpdatedAt),
    );
  }

  static const Object _sentinel = Object();
}

class AICanvasTransactionState {
  final bool isLoading;
  final bool isExecuting;
  final String? error;
  final List<AICanvasTransactionEntry> entries;

  const AICanvasTransactionState({
    this.isLoading = true,
    this.isExecuting = false,
    this.error,
    this.entries = const [],
  });

  AICanvasTransactionEntry? get activeEntry {
    for (final entry in entries) {
      if (entry.isPending) return entry;
    }
    return null;
  }

  List<AICanvasTransactionEntry> get pendingEntries =>
      entries.where((entry) => entry.isPending).toList(growable: false);

  AICanvasTransactionState copyWith({
    bool? isLoading,
    bool? isExecuting,
    Object? error = _sentinel,
    List<AICanvasTransactionEntry>? entries,
  }) => AICanvasTransactionState(
    isLoading: isLoading ?? this.isLoading,
    isExecuting: isExecuting ?? this.isExecuting,
    error: error == _sentinel ? this.error : error as String?,
    entries: entries ?? this.entries,
  );

  static const Object _sentinel = Object();
}

T _enumValue<T extends Enum>(List<T> values, String? raw, T fallback) =>
    values.firstWhere((value) => value.name == raw, orElse: () => fallback);

T? _enumValueOrNull<T extends Enum>(List<T> values, String? raw) {
  if (raw == null) return null;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return null;
}
