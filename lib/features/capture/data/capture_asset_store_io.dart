import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'capture_asset_store_types.dart';

CaptureAssetStore createPlatformCaptureAssetStore() =>
    NativeCaptureAssetStore();

class NativeCaptureAssetStore implements CaptureAssetStore {
  @override
  Future<String> save(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    validateCaptureAssetBytes(bytes);
    final reference = newCaptureAssetReference();
    final directory = await _directory();
    await directory.create(recursive: true);
    final id = Uri.parse(reference).host;
    final file = File(
      p.join(directory.path, '${id}_${sanitizeCaptureAssetFileName(fileName)}'),
    );
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      throw const CaptureAssetStoreException(
        'Capture asset could not be written.',
      );
    }
    return reference;
  }

  @override
  Future<Uint8List?> read(String reference) async {
    final file = await _resolve(reference);
    if (file == null || !await file.exists()) return null;
    final bytes = Uint8List.fromList(await file.readAsBytes());
    validateCaptureAssetBytes(bytes);
    return bytes;
  }

  @override
  Future<bool> exists(String reference) async {
    final file = await _resolve(reference);
    return file != null && await file.exists() && await file.length() > 0;
  }

  @override
  Future<void> delete(String reference) async {
    final file = await _resolve(reference);
    if (file != null && await file.exists()) await file.delete();
  }

  Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    return Directory(p.join(root.path, 'varian-captures'));
  }

  Future<File?> _resolve(String reference) async {
    if (!isCaptureAssetReference(reference)) return null;
    final uri = Uri.parse(reference.trim());
    final directory = await _directory();
    if (!await directory.exists()) return null;
    final root = await directory.resolveSymbolicLinks();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          !p.basename(entity.path).startsWith('${uri.host}_')) {
        continue;
      }
      try {
        final resolved = await entity.resolveSymbolicLinks();
        final relative = p.relative(resolved, from: root);
        if (relative != '.' &&
            !p.isAbsolute(relative) &&
            relative != '..' &&
            !relative.startsWith('..${p.separator}')) {
          return File(resolved);
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
