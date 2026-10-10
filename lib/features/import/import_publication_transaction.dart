/// Executes a synchronous multi-store publication with explicit rollback.
///
/// Provider state cannot be committed atomically across independent notifiers.
/// Callers therefore stage their changes inside [commit] and restore every
/// affected store from a snapshot in [rollback] when publication fails.
class ImportPublicationTransaction {
  ImportPublicationTransaction._();

  static void run({
    required void Function() commit,
    required void Function() rollback,
  }) {
    try {
      commit();
    } catch (_) {
      try {
        rollback();
      } catch (_) {
        // The original publication error is the actionable failure. Callers
        // still own logging/reporting if rollback itself cannot be completed.
      }
      rethrow;
    }
  }
}
