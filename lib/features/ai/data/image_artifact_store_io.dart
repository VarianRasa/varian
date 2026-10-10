import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'image_artifact_store_types.dart';

const _nativeArtifactFolder = 'varian-images';

ImageArtifactStore createPlatformImageArtifactStore() =>
    NativeImageArtifactStore();

Future<ImageArtifact?> hydratePlatformImageArtifact(String reference) =>
    NativeImageArtifactStore().hydrate(reference);

Future<void> disposePlatformHydratedImageArtifact(
  ImageArtifact artifact,
) async {
  // Durable image files must remain available to reopened and duplicated
  // documents. Hydration disposal is intentionally a no-op on native.
}

class NativeImageArtifactStore implements ImageArtifactStore {
  @override
  Future<ImageArtifact> save(
    Uint8List bytes, {
    String fileName = 'image.png',
  }) async {
    validateImageArtifactBytes(bytes);
    final id = const Uuid().v4();
    final folder = await _artifactDirectory();
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, '$id.bin'));
    await file.writeAsBytes(bytes, flush: true);
    return ImageArtifact(
      path: file.path,
      reference: 'varian-image://$id',
      fileName: sanitizeImageArtifactFileName(fileName),
    );
  }

  @override
  Future<ImageArtifact?> hydrate(String reference, {String? fileName}) async {
    final id = _imageArtifactId(reference);
    if (id == null) return null;
    final file = await _ownedFile(id);
    if (file == null || !await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      validateImageArtifactBytes(bytes);
      return ImageArtifact(
        path: file.path,
        reference: reference,
        fileName: fileName ?? _fileNameForBytes(bytes),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> exists(ImageArtifact artifact) async {
    final reference = artifact.reference;
    final id = reference == null ? null : _imageArtifactId(reference);
    if (id == null) return false;
    final file = await _ownedFile(id);
    return file != null && await file.exists() && await file.length() > 0;
  }

  @override
  Future<Uint8List?> read(ImageArtifact artifact) async {
    final reference = artifact.reference;
    final id = reference == null ? null : _imageArtifactId(reference);
    if (id == null) return null;
    final file = await _ownedFile(id);
    if (file == null || !await file.exists()) return null;
    final bytes = await file.readAsBytes();
    validateImageArtifactBytes(bytes);
    return bytes;
  }

  @override
  Future<void> dispose(ImageArtifact artifact) async {
    // References are durable document data. Do not delete them when a widget
    // releases its transient render handle.
  }

  Future<Directory> _artifactDirectory() async {
    final root = await getApplicationSupportDirectory();
    return Directory(p.join(root.path, _nativeArtifactFolder));
  }

  Future<File?> _ownedFile(String id) async {
    if (!_validId(id)) return null;
    final folder = await _artifactDirectory();
    final candidate = File(p.join(folder.path, '$id.bin'));
    if (!await _isOwnedArtifactFile(candidate, folder)) return null;
    return candidate;
  }

  Future<bool> _isOwnedArtifactFile(File file, Directory folder) async {
    try {
      if (!await file.exists() || !await folder.exists()) return false;
      final root = await folder.resolveSymbolicLinks();
      final resolved = await file.resolveSymbolicLinks();
      final relative = p.relative(resolved, from: root);
      return relative != '.' &&
          !p.isAbsolute(relative) &&
          relative != '..' &&
          !relative.startsWith('..${p.separator}') &&
          p.basename(relative).endsWith('.bin');
    } catch (_) {
      return false;
    }
  }
}

String? _imageArtifactId(String reference) {
  final uri = Uri.tryParse(reference.trim());
  if (uri == null || uri.scheme != 'varian-image' || uri.host.isEmpty) {
    return null;
  }
  if (uri.path.isNotEmpty || uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
    return null;
  }
  final id = uri.host;
  return _validId(id) ? id : null;
}

bool _validId(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$').hasMatch(value);

String _fileNameForBytes(Uint8List bytes) {
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'generated-image.webp';
  }
  if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    return 'generated-image.jpg';
  }
  return 'generated-image.png';
}
