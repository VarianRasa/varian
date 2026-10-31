String formatWorkspaceDateKey(DateTime timestamp) =>
    _formatWorkspaceDate(timestamp.toLocal());

String formatWorkspaceTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_formatWorkspaceDate(local)} $hour:$minute';
}

String _formatWorkspaceDate(DateTime local) {
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
