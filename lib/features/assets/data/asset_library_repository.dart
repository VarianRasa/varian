import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/assets/domain/asset_library.dart';

abstract interface class AssetLibraryRepository {
  Future<void> load();

  Future<AssetLibraryPage> search(AssetLibraryQuery query);

  Future<List<AssetLibraryFolder>> loadFolders();

  Future<AssetLibraryFolder> createFolder(String name, {String? parentId});

  Future<void> deleteFolder(String folderId);

  Future<AssetLibraryItem> save(AssetLibraryItem item);

  Future<AssetLibraryItem> saveProviderItem(AssetLibraryItem item);

  Future<AssetLibraryItem> saveUpload(
    AssetPickerResult result, {
    String? folderId,
    Iterable<String> tags,
  });

  Future<void> setFavorite(String itemId, bool active);

  Future<void> updateMetadata(
    String itemId, {
    String? name,
    String? folderId,
    Iterable<String>? tags,
  });

  Future<void> delete(String itemId);

  Future<void> recordUsage(String itemId, {String? projectId, String? nodeId});
}
