enum WorkspaceNoteScopeChangeStatus {
  pending,
  copying,
  cleanup,
  failed,
  complete,
}

class WorkspaceNoteScopeChangeJob {
  const WorkspaceNoteScopeChangeJob({
    required this.jobId,
    required this.status,
    this.attemptCount = 0,
    this.lastErrorCode,
  });

  final String jobId;
  final WorkspaceNoteScopeChangeStatus status;
  final int attemptCount;
  final String? lastErrorCode;

  factory WorkspaceNoteScopeChangeJob.fromJson(Map<String, dynamic> json) {
    final rawJobId = json['id'] ?? json['job_id'];
    final rawStatus = json['status'];
    final status = WorkspaceNoteScopeChangeStatus.values
        .where((candidate) => candidate.name == rawStatus)
        .firstOrNull;
    final rawAttemptCount = json['attempt_count'] ?? 0;
    final rawErrorCode = json['last_error_code'];
    if (rawJobId is! String ||
        rawJobId.isEmpty ||
        status == null ||
        rawAttemptCount is! num ||
        rawAttemptCount < 0 ||
        (rawErrorCode != null && rawErrorCode is! String)) {
      throw const FormatException('Note scope change status is invalid.');
    }
    return WorkspaceNoteScopeChangeJob(
      jobId: rawJobId,
      status: status,
      attemptCount: rawAttemptCount.toInt(),
      lastErrorCode: rawErrorCode as String?,
    );
  }
}
