import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../domain/models/durable_asset_reference.dart';
import 'file_artifact_store_types.dart';

FileArtifactStore createPlatformFileArtifactStore() =>
    NativeFileArtifactStore();

class NativeFileArtifactStore implements FileArtifactStore {
  @override
  Future<FileArtifact> save(
    Uint8List bytes, {
    String fileName = 'document.bin',
  }) async {
    validateFileArtifactBytes(bytes, fileName: fileName);
    final folder = await _artifactDirectory();
    await folder.create(recursive: true);
    final id = Uri.parse(newFileArtifactReference()).host;
    final safeName = sanitizeFileArtifactName(fileName);
    final file = File(p.join(folder.path, '${id}_$safeName'));
    await file.writeAsBytes(bytes, flush: true);
    return FileArtifact(
      path: file.path,
      reference: 'varian-file://$id',
      fileName: safeName,
    );
  }

  @override
  Future<FileArtifact?> hydrate(String reference, {String? fileName}) async {
    final normalized = durableOpaqueArtifactReference(reference, 'varian-file');
    if (normalized == null) return null;
    final artifact = await _artifactForReference(normalized);
    if (artifact == null || !await exists(artifact)) return null;
    return fileName == null
        ? artifact
        : FileArtifact(
            path: artifact.path,
            reference: artifact.reference,
            fileName: sanitizeFileArtifactName(fileName),
          );
  }

  @override
  Future<bool> exists(FileArtifact artifact) async {
    final file = await _resolveOwnedArtifact(artifact);
    return file != null && await file.exists() && await file.length() > 0;
  }

  @override
  Future<Uint8List?> read(FileArtifact artifact) async {
    final file = await _resolveOwnedArtifact(artifact);
    if (file == null || !await file.exists()) return null;
    final bytes = Uint8List.fromList(await file.readAsBytes());
    validateFileArtifactBytes(bytes);
    return bytes;
  }

  @override
  Future<void> dispose(FileArtifact artifact) async {
    // Durable files are document data, not widget-owned temporary files.
  }

  Future<Directory> _artifactDirectory() async {
    final root = await getApplicationSupportDirectory();
    return Directory(p.join(root.path, 'varian-files'));
  }

  Future<FileArtifact?> _artifactForReference(String reference) async {
    final id = Uri.parse(reference).host;
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$').hasMatch(id)) return null;
    final folder = await _artifactDirectory();
    if (!await folder.exists()) return null;
    final entries = await folder
        .list(followLinks: false)
        .where(
          (entity) =>
              entity is File && p.basename(entity.path).startsWith('${id}_'),
        )
        .toList();
    if (entries.isEmpty) return null;
    final file = entries.first as File;
    return FileArtifact(
      path: file.path,
      reference: reference,
      fileName: sanitizeFileArtifactName(
        p.basename(file.path).substring(id.length + 1),
      ),
    );
  }

  Future<File?> _resolveOwnedArtifact(FileArtifact artifact) async {
    final reference = artifact.reference;
    if (reference != null) {
      final normalized = durableOpaqueArtifactReference(
        reference,
        'varian-file',
      );
      if (normalized != null) {
        final hydrated = await _artifactForReference(normalized);
        if (hydrated?.path != null) return File(hydrated!.path!);
      }
    }
    final path = artifact.path;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return await _isOwnedArtifactFile(file) ? file : null;
  }

  Future<bool> _isOwnedArtifactFile(File file) async {
    try {
      if (!await file.exists()) return false;
      final folder = await _artifactDirectory();
      if (!await folder.exists()) return false;
      final root = await folder.resolveSymbolicLinks();
      final resolved = await file.resolveSymbolicLinks();
      final relative = p.relative(resolved, from: root);
      return relative != '.' &&
          !p.isAbsolute(relative) &&
          relative != '..' &&
          !relative.startsWith('..${p.separator}');
    } catch (_) {
      return false;
    }
  }
}
