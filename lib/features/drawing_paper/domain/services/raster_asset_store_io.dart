import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'raster_asset_store_contract.dart';

RasterAssetStore createRasterAssetStore() => _IoRasterAssetStore();

class _IoRasterAssetStore implements RasterAssetStore {
  Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}raster');
    await directory.create(recursive: true);
    return directory;
  }

  String _safeName(String reference) => reference
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');

  Future<File> _file(String reference) async {
    final directory = await _directory();
    return File(
      '${directory.path}${Platform.pathSeparator}${_safeName(reference)}.png',
    );
  }

  @override
  Future<bool> contains(String reference) async =>
      (await _file(reference)).exists();

  @override
  Future<void> delete(String reference) async {
    final file = await _file(reference);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<Uint8List?> read(String reference) async {
    final file = await _file(reference);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> write(String reference, Uint8List bytes) async {
    final file = await _file(reference);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
