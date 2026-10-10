import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/templates/domain/project_template.dart';

ProjectTemplate _template(
  String id,
  DateTime updatedAt, {
  ProjectTemplateScope scope = ProjectTemplateScope.personal,
}) => ProjectTemplate(
  id: id,
  name: id,
  description: '',
  scope: scope,
  createdAt: updatedAt,
  updatedAt: updatedAt,
);

void main() {
  test(
    'two-way merge keeps local-only and uploads it, while remote-only is added',
    () {
      final local = ProjectTemplateCatalog.withBuiltIns(
        custom: [_template('local-only', DateTime.utc(2026, 9, 13, 10))],
      );
      final remote = ProjectTemplateCatalog.withBuiltIns(
        custom: [_template('remote-only', DateTime.utc(2026, 9, 13, 11))],
      );

      final result = local.mergeRemote(remote);

      expect(
        result.catalog.search(scope: ProjectTemplateScope.personal),
        hasLength(2),
      );
      expect(result.localWins.map((template) => template.id), ['local-only']);
      expect(result.remoteOnly.map((template) => template.id), ['remote-only']);
    },
  );

  test(
    'newer local template wins a conflict and older local yields to remote',
    () {
      final local = ProjectTemplateCatalog.withBuiltIns(
        custom: [
          _template('local-newer', DateTime.utc(2026, 9, 13, 12)),
          _template('remote-newer', DateTime.utc(2026, 9, 13, 9)),
        ],
      );
      final remote = ProjectTemplateCatalog.withBuiltIns(
        custom: [
          _template('local-newer', DateTime.utc(2026, 9, 13, 11)),
          _template('remote-newer', DateTime.utc(2026, 9, 13, 13)),
        ],
      );

      final result = local.mergeRemote(remote);

      expect(
        result.catalog.templates
            .firstWhere((item) => item.id == 'local-newer')
            .updatedAt
            .hour,
        12,
      );
      expect(
        result.catalog.templates
            .firstWhere((item) => item.id == 'remote-newer')
            .updatedAt
            .hour,
        13,
      );
      expect(result.localWins.map((template) => template.id), ['local-newer']);
      expect(result.remoteWins.map((template) => template.id), [
        'remote-newer',
      ]);
    },
  );

  test('equal timestamps use remote as the deterministic winner', () {
    final timestamp = DateTime.utc(2026, 9, 13, 14);
    final local = ProjectTemplateCatalog.withBuiltIns(
      custom: [_template('same', timestamp)],
    );
    final remote = ProjectTemplateCatalog.withBuiltIns(
      custom: [_template('same', timestamp).copyWith(name: 'Remote canonical')],
    );

    final result = local.mergeRemote(remote);

    expect(
      result.catalog.templates.firstWhere((item) => item.id == 'same').name,
      'Remote canonical',
    );
    expect(result.remoteWins.map((template) => template.id), ['same']);
  });
}
