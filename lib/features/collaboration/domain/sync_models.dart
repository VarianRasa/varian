import 'crdt_primitives.dart';

enum CollaborationSyncStatus {
  synced,
  savedLocally,
  syncing,
  conflicted,
  failed,
  paused,
}

enum ConflictResolutionChoice { keepLocal, keepRemote, merge }

class CollaborationConflict {
  final String id;
  final String targetId;
  final String? field;
  final CrdtOperation localOperation;
  final CrdtOperation remoteOperation;
  final DateTime detectedAt;

  const CollaborationConflict({
    required this.id,
    required this.targetId,
    required this.localOperation,
    required this.remoteOperation,
    required this.detectedAt,
    this.field,
  });

  String get description => field == null
      ? 'Concurrent edits target $targetId.'
      : 'Concurrent edits target $targetId.$field.';
}
