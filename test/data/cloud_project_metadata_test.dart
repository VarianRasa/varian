import 'package:flutter_test/flutter_test.dart';
import 'package:varian/data/local/local_storage_service.dart';

void main() {
  test('project metadata round-trips cloud ownership and freshness', () {
    final metadata = LocalProjectMetadata.fromJson({
      'id': 'project-1',
      'name': 'Cloud project',
      'createdAt': '2026-10-01T08:00:00.000Z',
      'updatedAt': '2026-10-04T08:00:00.000Z',
      'cloudOwnerId': 'account-1',
      'cloudUpdatedAt': '2026-10-05T08:00:00.000Z',
    });

    expect(metadata.cloudOwnerId, 'account-1');
    expect(metadata.cloudUpdatedAt, DateTime.utc(2026, 10, 5, 8));
    expect(metadata.toJson()['cloudOwnerId'], 'account-1');
    expect(metadata.toJson()['cloudUpdatedAt'], '2026-10-05T08:00:00.000Z');
  });
}
