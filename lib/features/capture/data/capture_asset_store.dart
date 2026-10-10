export 'capture_asset_store_types.dart';

import 'capture_asset_store_types.dart';
import 'capture_asset_store_web.dart'
    if (dart.library.io) 'capture_asset_store_io.dart'
    as platform;

CaptureAssetStore createCaptureAssetStore() =>
    platform.createPlatformCaptureAssetStore();
