import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/import/import_publication_transaction.dart';

void main() {
  test('restores every published slice when a later slice fails', () {
    var nodes = <String>['existing-node'];
    var edges = <String>['existing-edge'];
    var assets = <String>['existing-asset'];
    var rollbackCalls = 0;

    expect(
      () => ImportPublicationTransaction.run(
        commit: () {
          nodes = [...nodes, 'imported-node'];
          edges = [...edges, 'imported-edge'];
          assets = [...assets, 'imported-asset'];
          throw StateError('asset provider failed');
        },
        rollback: () {
          rollbackCalls++;
          nodes = ['existing-node'];
          edges = ['existing-edge'];
          assets = ['existing-asset'];
        },
      ),
      throwsStateError,
    );

    expect(nodes, ['existing-node']);
    expect(edges, ['existing-edge']);
    expect(assets, ['existing-asset']);
    expect(rollbackCalls, 1);
  });

  test('does not invoke rollback after a successful commit', () {
    var rollbackCalls = 0;

    ImportPublicationTransaction.run(
      commit: () {},
      rollback: () => rollbackCalls++,
    );

    expect(rollbackCalls, 0);
  });
}
