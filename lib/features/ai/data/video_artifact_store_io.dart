import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/durable_asset_reference.dart';
import 'video_artifact_store_types.dart';

VideoArtifactStore createPlatformVideoArtifactStore() =>
    NativeVideoArtifactStore();

Future<VideoArtifact?> hydratePlatformVideoArtifact(String reference) =>
    NativeVideoArtifactStore().hydrate(reference);

Future<void> disposePlatformHydratedVideoArtifact(VideoArtifact artifact) =>
    NativeVideoArtifactStore().dispose(artifact);

class NativeVideoArtifactStore implements VideoArtifactStore {
  @override
  Future<VideoArtifact> save(
    Uint8List bytes, {
    String fileName = 'video.mp4',
  }) async {
    validateVideoArtifactBytes(bytes);
    final directory = await getApplicationSupportDirectory();
    final folder = Directory(p.join(directory.path, 'varian-videos'));
    await folder.create(recursive: true);
    final safeName = sanitizeVideoFileName(fileName);
    final id = const Uuid().v4();
    final file = File(p.join(folder.path, '${id}_$safeName'));
    await file.writeAsBytes(bytes, flush: true);
    return VideoArtifact(
      path: file.path,
      reference: 'varian-video://$id',
      fileName: safeName,
    );
  }

  @override
  Future<VideoArtifact?> hydrate(String reference, {String? fileName}) async {
    final validReference = validVideoArtifactReference(reference);
    if (validReference == null) return null;
    final artifact = await _artifactForReference(validReference);
    if (artifact == null || !await exists(artifact)) return null;
    return artifact;
  }

  @override
  Future<bool> exists(VideoArtifact artifact) async {
    final resolved = await _resolveOwnedArtifact(artifact);
    if (resolved == null) return false;
    return await resolved.exists() && await resolved.length() > 0;
  }

  @override
  Future<Uint8List?> read(VideoArtifact artifact) async {
    final file = await _resolveOwnedArtifact(artifact);
    if (file == null || !await file.exists()) return null;
    final bytes = await file.readAsBytes();
    validateVideoArtifactBytes(bytes);
    return bytes;
  }

  @override
  Future<void> dispose(VideoArtifact artifact) async {
    // Native artifact files are durable document data, not widget-owned files.
  }

  Future<VideoArtifact?> _artifactForReference(String reference) async {
    final id = Uri.parse(reference).host;
    final directory = await getApplicationSupportDirectory();
    final folder = Directory(p.join(directory.path, 'varian-videos'));
    if (!await folder.exists()) return null;
    final files = await folder.list(followLinks: false).where((entity) {
      return entity is File && p.basename(entity.path).startsWith('${id}_');
    }).toList();
    if (files.isEmpty) return null;
    final file = files.first as File;
    return VideoArtifact(
      path: file.path,
      reference: reference,
      fileName: sanitizeVideoFileName(
        p.basename(file.path).substring(id.length + 1),
      ),
    );
  }

  Future<File?> _resolveOwnedArtifact(VideoArtifact artifact) async {
    final reference = validVideoArtifactReference(artifact.reference);
    if (reference != null) {
      final hydrated = await _artifactForReference(reference);
      if (hydrated != null) return File(hydrated.path!);
    }
    final path = artifact.path;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return await _isOwnedArtifactFile(file) ? file : null;
  }

  Future<bool> _isOwnedArtifactFile(File file) async {
    try {
      if (!await file.exists()) return false;
      final directory = await getApplicationSupportDirectory();
      final rootDirectory = Directory(p.join(directory.path, 'varian-videos'));
      if (!await rootDirectory.exists()) return false;
      final root = await rootDirectory.resolveSymbolicLinks();
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
