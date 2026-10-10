import 'package:uuid/uuid.dart';

/// In-memory, one-shot signal to add a local Inbox capture to one project.
///
/// The signal is passed through router `extra` only. Capture contents and IDs
/// are never serialized into a URL or persisted, so refresh cannot replay it.
bool canAcceptLocalCaptureCanvasHandoff({
  required bool readOnly,
  required bool collaborationRoom,
  required bool hasCollaborationRole,
}) => !readOnly && !collaborationRoom && !hasCollaborationRole;

String stableDocumentAssetIdForCapture({
  required String? preferredId,
  required Set<String> occupiedManifestIds,
  required Set<String> occupiedNodeIds,
  required String fallback,
}) {
  final preferred = preferredId?.trim();
  if (preferred != null &&
      preferred.isNotEmpty &&
      !occupiedManifestIds.contains(preferred) &&
      !occupiedNodeIds.contains(preferred)) {
    return preferred;
  }
  final normalizedFallback = fallback.trim();
  if (normalizedFallback.isNotEmpty &&
      !occupiedManifestIds.contains(normalizedFallback) &&
      !occupiedNodeIds.contains(normalizedFallback)) {
    return normalizedFallback;
  }
  return const Uuid().v4();
}

class CaptureCanvasHandoff {
  CaptureCanvasHandoff({
    required this.projectId,
    required this.accountId,
    required this.captureId,
  });

  final String projectId;
  final String? accountId;
  final String captureId;

  bool _consumed = false;

  bool get isConsumed => _consumed;

  bool consume({required String projectId, required String? accountId}) {
    if (_consumed) return false;
    _consumed = true;
    return projectId == this.projectId && accountId == this.accountId;
  }
}
