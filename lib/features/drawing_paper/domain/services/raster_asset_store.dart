export 'raster_asset_store_contract.dart';

import 'raster_asset_store_contract.dart';
import 'raster_asset_store_platform.dart'
    if (dart.library.io) 'raster_asset_store_io.dart'
    as platform;

RasterAssetStore createDefaultRasterAssetStore() =>
    platform.createRasterAssetStore();
