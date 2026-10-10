import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/design_tokens.dart';

void main() {
  test('resolves token values by mode and round trips JSON', () {
    final token = DesignToken(
      id: 'color.surface',
      name: 'Surface',
      type: DesignTokenType.color,
      value: '#ffffff',
      modeValues: const {'dark': '#111111'},
      updatedAt: DateTime.utc(2026, 9, 11),
    );
    final set = const DesignTokenSet(modes: ['base', 'dark']).upsert(token);

    expect(set.resolve('color.surface'), '#ffffff');
    expect(set.resolve('color.surface', 'dark'), '#111111');
    final restored = DesignTokenSet.fromJson(set.toJson());
    expect(restored['color.surface']?.modeValues['dark'], '#111111');
  });

  test('migrates schema v2 documents with an empty token set', () {
    final json = {
      'schemaVersion': 2,
      'projectId': 'legacy-v2',
      'nodes': const [],
      'edges': const [],
      'updatedAt': '2026-09-11T00:00:00.000Z',
    };
    final document = CanvasDocument.fromJson(json);
    expect(document.tokens.entries, isEmpty);
    expect(document.schemaVersion, 4);
  });
}
