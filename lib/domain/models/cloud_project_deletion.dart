enum CloudProjectDeletionStatus { pending, copying, cleanup, failed, complete }

class CloudProjectDeletionResult {
  const CloudProjectDeletionResult({
    required this.status,
    this.jobId,
    this.attemptCount = 0,
    this.lastErrorCode,
  });

  final CloudProjectDeletionStatus status;
  final String? jobId;
  final int attemptCount;
  final String? lastErrorCode;

  factory CloudProjectDeletionResult.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'];
    final status = CloudProjectDeletionStatus.values
        .where((candidate) => candidate.name == rawStatus)
        .firstOrNull;
    final rawJobId = json['job_id'] ?? json['id'];
    final rawAttemptCount = json['attempt_count'] ?? 0;
    final rawErrorCode = json['last_error_code'];
    if (status == null ||
        (rawJobId != null && rawJobId is! String) ||
        rawAttemptCount is! num ||
        (rawErrorCode != null && rawErrorCode is! String)) {
      throw const FormatException(
        'Cloud project deletion response is invalid.',
      );
    }
    return CloudProjectDeletionResult(
      status: status,
      jobId: rawJobId as String?,
      attemptCount: rawAttemptCount.toInt(),
      lastErrorCode: rawErrorCode as String?,
    );
  }
}
