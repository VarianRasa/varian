import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/workspace_timestamp.dart';

void main() {
  test('formats timestamps with padded local date and 24-hour time', () {
    final timestamp = DateTime(2026, 1, 5, 9, 7);

    expect(formatWorkspaceTimestamp(timestamp), '2026-01-05 09:07');
  });

  test('formats a timestamp as its local ISO date key', () {
    expect(formatWorkspaceDateKey(DateTime(2026, 1, 5, 9, 7)), '2026-01-05');
  });

  test('converts UTC timestamps to local time before formatting', () {
    final timestamp = DateTime.utc(2026, 10, 11, 6, 5);
    final local = timestamp.toLocal();
    final expected =
        '${local.year.toString().padLeft(4, '0')}'
        '-${local.month.toString().padLeft(2, '0')}'
        '-${local.day.toString().padLeft(2, '0')}'
        ' ${local.hour.toString().padLeft(2, '0')}'
        ':${local.minute.toString().padLeft(2, '0')}';

    expect(formatWorkspaceTimestamp(timestamp), expected);
  });
}
