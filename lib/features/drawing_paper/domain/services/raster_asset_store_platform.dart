import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'raster_asset_store_contract.dart';

RasterAssetStore createRasterAssetStore() => _WebRasterAssetStore();

class _WebRasterAssetStore implements RasterAssetStore {
  static const _prefix = 'ccs_raster_asset_';

  String _key(String reference) =>
      '$_prefix${base64UrlEncode(utf8.encode(reference))}';

  @override
  Future<bool> contains(String reference) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key(reference));
  }

  @override
  Future<void> delete(String reference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(reference));
  }

  @override
  Future<Uint8List?> read(String reference) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_key(reference));
    return encoded == null ? null : Uint8List.fromList(base64Decode(encoded));
  }

  @override
  Future<void> write(String reference, Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(_key(reference), base64Encode(bytes));
    if (!saved) {
      throw StateError('Raster asset could not be saved in browser storage.');
    }
  }
}
