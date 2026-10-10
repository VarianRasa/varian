import '../../domain/asset_library.dart';

abstract interface class AssetCatalogProvider {
  String get id;

  Future<AssetLibraryPage> search(AssetLibraryQuery query);
}

class AssetProviderException implements Exception {
  final String provider;
  final String message;
  final int? statusCode;

  const AssetProviderException(this.provider, this.message, {this.statusCode});

  @override
  String toString() => '$provider: $message';
}
