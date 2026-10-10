import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/assets/data/asset_library_repository.dart';
import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/assets/domain/asset_library.dart';
import 'package:varian/features/assets/presentation/asset_library_dialog.dart';

import '../../test_app.dart';

class _FakeLibrary implements AssetLibraryRepository {
  final AssetLibraryItem item;
  String? updatedId;
  String? updatedName;
  String? updatedFolderId;
  List<String>? updatedTags;
  String? deletedId;

  _FakeLibrary(this.item);

  @override
  Future<void> load() async {}

  @override
  Future<AssetLibraryPage> search(AssetLibraryQuery query) async =>
      AssetLibraryPage(items: [item]);

  @override
  Future<List<AssetLibraryFolder>> loadFolders() async => const [];

  @override
  Future<AssetLibraryFolder> createFolder(String name, {String? parentId}) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteFolder(String folderId) async {}

  @override
  Future<AssetLibraryItem> save(AssetLibraryItem item) async => item;

  @override
  Future<AssetLibraryItem> saveProviderItem(AssetLibraryItem item) async =>
      item;

  @override
  Future<AssetLibraryItem> saveUpload(
    AssetPickerResult result, {
    String? folderId,
    Iterable<String> tags = const [],
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> setFavorite(String itemId, bool active) async {}

  @override
  Future<void> updateMetadata(
    String itemId, {
    String? name,
    String? folderId,
    Iterable<String>? tags,
  }) async {
    updatedId = itemId;
    updatedName = name;
    updatedFolderId = folderId;
    updatedTags = tags?.toList();
  }

  @override
  Future<void> delete(String itemId) async => deletedId = itemId;

  @override
  Future<void> recordUsage(
    String itemId, {
    String? projectId,
    String? nodeId,
  }) async {}
}

void main() {
  testWidgets('renders reusable cards and inserts a catalog item', (
    tester,
  ) async {
    final item = AssetLibraryItem(
      id: 'upload-1',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Brand hero',
      localPath: r'C:\assets\hero.png',
      license: 'User supplied',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );
    AssetLibraryItem? inserted;
    await tester.pumpWidget(
      testApp(
        AssetLibraryDialog(
          nodes: const [],
          library: _FakeLibrary(item),
          scopeId: 'project-1',
          onInsertAsset: (value) async => inserted = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('REUSABLE LIBRARY'), findsOneWidget);
    expect(find.text('Brand hero'), findsOneWidget);
    final action = find.byKey(const ValueKey('asset-library-insert-upload-1'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(inserted?.id, 'upload-1');
  });

  testWidgets('saves and confirms deletion of a catalog asset', (tester) async {
    final item = AssetLibraryItem(
      id: 'upload-crud',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'Original name',
      tags: const ['before'],
      localPath: r'C:\assets\hero.png',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );
    final library = _FakeLibrary(item);
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          AssetLibraryDialog(
            nodes: const [],
            library: library,
            scopeId: 'project-1',
            onInsertAsset: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final edit = find.byTooltip('Edit asset metadata');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final editorDialog = find.ancestor(
      of: find.text('Edit library asset'),
      matching: find.byType(UiDialog),
    );
    final fields = find.descendant(
      of: editorDialog,
      matching: find.byType(TextFormField),
    );
    final nameField = fields.at(0);
    final tagsField = fields.at(1);
    await tester.enterText(nameField, 'Updated name');
    await tester.enterText(tagsField, 'brand, approved');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(library.updatedId, 'upload-crud');
    expect(library.updatedName, 'Updated name');
    expect(library.updatedTags, ['brand', 'approved']);

    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(library.deletedId, 'upload-crud');
  });

  testWidgets('keeps the catalog usable across responsive viewports', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final item = AssetLibraryItem(
      id: 'upload-responsive',
      scopeId: 'project-1',
      kind: AssetLibraryItemKind.image,
      source: AssetLibrarySource.upload,
      name: 'A very long asset title that should truncate',
      localPath: r'C:\\assets\\hero.png',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );
    const viewports = [
      Size(320, 720),
      Size(768, 900),
      Size(1024, 900),
      Size(1440, 1000),
    ];

    for (final viewport in viewports) {
      await tester.binding.setSurfaceSize(viewport);
      await tester.pumpWidget(
        testApp(
          AssetLibraryDialog(
            nodes: const [],
            library: _FakeLibrary(item),
            scopeId: 'project-1',
            onInsertAsset: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        viewport.width < 360 ? 1 : greaterThan(1),
        reason: 'catalog cards should reflow at viewport $viewport',
      );
      expect(tester.takeException(), isNull, reason: 'viewport $viewport');
      expect(
        find.byKey(const ValueKey('asset-library-insert-upload-responsive')),
        findsOneWidget,
        reason: 'viewport $viewport',
      );
    }
  });
}
