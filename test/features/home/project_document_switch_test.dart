import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/document_assets_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/collaboration/state/collaboration_session_provider.dart';
import 'package:varian/features/home/presentation/project_route_screen.dart';

import '../../test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('switching documents restores each document own content', (
    tester,
  ) async {
    final created = DateTime(2026, 9, 29);
    final first = _project('project-a', 'Document A', created);
    final second = _project('project-b', 'Document B', created);
    final firstDocument = CanvasDocument(
      projectId: first.id,
      nodes: [_node('node-a')],
      assets: DocumentAssetManifest(
        entries: {'asset-a': _asset('asset-a', 'first.png', created)},
      ),
      updatedAt: created,
    );
    final secondDocument = CanvasDocument(
      projectId: second.id,
      nodes: [_node('node-b')],
      assets: DocumentAssetManifest(
        entries: {'asset-b': _asset('asset-b', 'second.png', created)},
      ),
      updatedAt: created,
    );
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([first.toJson(), second.toJson()]),
      'ccs_doc_${first.id}': jsonEncode(firstDocument.toJson()),
      'ccs_doc_${second.id}': jsonEncode(secondDocument.toJson()),
    });

    final store = DurableProjectStore(
      database: ProjectDurableDatabase(NativeDatabase.memory()),
    );
    addTearDown(store.close);
    final container = ProviderContainer(
      overrides: [durableProjectStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    Widget route(String projectId) => UncontrolledProviderScope(
      container: container,
      child: testApp(
        ProjectRouteScreen(
          projectId: projectId,
          editorBuilder: (id, name, role) => Consumer(
            builder: (context, ref, _) {
              final nodeIds = ref
                  .watch(documentNodesProvider)
                  .map((node) => node.id)
                  .join(',');
              final assetNames = ref
                  .watch(documentAssetsProvider)
                  .items
                  .map((asset) => asset.name)
                  .join(',');
              return Column(
                children: [
                  Text(name),
                  Text('nodes:$nodeIds'),
                  Text('assets:$assetNames'),
                ],
              );
            },
          ),
        ),
      ),
    );

    Future<void> finishRouteLoad() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.pumpWidget(route(first.id));
    await finishRouteLoad();
    expect(find.text('nodes:node-a'), findsOneWidget);
    expect(find.text('assets:first.png'), findsOneWidget);

    final sessionALease = container.listen(
      collaborationSessionProvider(first.id),
      (_, _) {},
    );
    addTearDown(sessionALease.close);
    final sessionA = container.read(
      collaborationSessionProvider(first.id).notifier,
    );
    await sessionA.start(
      initialDocument: firstDocument,
      userId: 'local-user-a',
      userName: 'Local User',
      userColor: Colors.blue,
    );

    await tester.pumpWidget(route(second.id));
    await finishRouteLoad();
    expect(find.text('nodes:node-b'), findsOneWidget);
    expect(find.text('assets:second.png'), findsOneWidget);
    expect(find.text('nodes:node-a'), findsNothing);
    expect(sessionA.state.pendingOperations, 0);

    await tester.pumpWidget(route(first.id));
    await finishRouteLoad();
    expect(find.text('nodes:node-a'), findsOneWidget);
    expect(find.text('assets:first.png'), findsOneWidget);
    expect(find.text('nodes:node-b'), findsNothing);
  });
}

LocalProjectMetadata _project(String id, String name, DateTime created) =>
    LocalProjectMetadata(
      id: id,
      name: name,
      createdAt: created,
      updatedAt: created,
    );

CanvasNode _node(String id) => CanvasNode(
  id: id,
  type: NodeType.rectangle,
  x: 0,
  y: 0,
  width: 100,
  height: 80,
  payload: ShapePayload(),
);

DocumentAsset _asset(String id, String name, DateTime created) => DocumentAsset(
  id: id,
  kind: DocumentAssetKind.image,
  storage: DocumentAssetStorage.embedded,
  name: name,
  mimeType: 'image/png',
  createdAt: created,
  updatedAt: created,
);
