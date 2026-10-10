import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/durable_asset_reference.dart';
import 'model3d_artifact_store_types.dart';
import 'model3d_validation.dart';

Model3DArtifactStore createPlatformModel3DArtifactStore() =>
    NativeModel3DArtifactStore();

const _nativeArtifactFolder = 'varian-models3d';

Future<Model3DArtifact?> hydratePlatformModel3DArtifact(
  String reference,
) async {
  final validReference = validModel3DArtifactReference(reference);
  if (validReference == null) return null;
  final store = NativeModel3DArtifactStore();
  final artifact = await store._artifactForReference(validReference);
  return artifact == null || !await store.exists(artifact) ? null : artifact;
}

Future<bool> isPlatformModel3DArtifactPathAllowed(String path) =>
    _isOwnedArtifactFile(File(path.trim()));

Future<bool> _isOwnedArtifactFile(File file) async {
  try {
    if (!await file.exists()) return false;
    final directory = await getApplicationSupportDirectory();
    final artifactDirectory = Directory(
      p.join(directory.path, _nativeArtifactFolder),
    );
    if (!await artifactDirectory.exists()) return false;

    final root = await artifactDirectory.resolveSymbolicLinks();
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

Future<void> disposePlatformHydratedModel3DArtifact(
  Model3DArtifact artifact,
) async {
  // Native artifact files are durable project data, not widget-owned files.
}

class NativeModel3DArtifactStore implements Model3DArtifactStore {
  @override
  Future<Model3DArtifact> save(
    Uint8List bytes, {
    String fileName = 'model.glb',
  }) async {
    validateGlbBytes(bytes);
    final directory = await getApplicationSupportDirectory();
    final folder = Directory(p.join(directory.path, _nativeArtifactFolder));
    await folder.create(recursive: true);
    final safeName = sanitizeModel3DFileName(fileName);
    final id = const Uuid().v4();
    final file = File(p.join(folder.path, '${id}_$safeName'));
    await file.writeAsBytes(bytes, flush: true);
    return Model3DArtifact(
      path: file.path,
      reference: 'varian-model3d://$id',
      fileName: safeName,
    );
  }

  @override
  Future<Model3DArtifact?> hydrate(String reference, {String? fileName}) async {
    final validReference = validModel3DArtifactReference(reference);
    if (validReference == null) return null;
    final artifact = await _artifactForReference(validReference);
    if (artifact == null || !await exists(artifact)) return null;
    return fileName == null
        ? artifact
        : Model3DArtifact(
            path: artifact.path,
            reference: artifact.reference,
            fileName: sanitizeModel3DFileName(fileName),
          );
  }

  @override
  Future<bool> exists(Model3DArtifact artifact) async {
    final file = await _resolveOwnedArtifact(artifact);
    if (file == null || !await file.exists()) return false;
    return await file.length() > 0;
  }

  @override
  Future<Uint8List?> read(Model3DArtifact artifact) async {
    final file = await _resolveOwnedArtifact(artifact);
    if (file == null || !await file.exists()) return null;
    final bytes = await file.readAsBytes();
    validateGlbBytes(bytes);
    return bytes;
  }

  @override
  Future<void> dispose(Model3DArtifact artifact) async {
    // Model artifacts remain available to reopened and duplicated documents.
  }

  Future<Model3DArtifact?> _artifactForReference(String reference) async {
    final id = Uri.parse(reference).host;
    final directory = await getApplicationSupportDirectory();
    final folder = Directory(p.join(directory.path, _nativeArtifactFolder));
    if (!await folder.exists()) return null;
    final files = await folder.list(followLinks: false).where((entity) {
      return entity is File && p.basename(entity.path).startsWith('${id}_');
    }).toList();
    if (files.isEmpty) return null;
    final file = files.first as File;
    return Model3DArtifact(
      path: file.path,
      reference: reference,
      fileName: sanitizeModel3DFileName(
        p.basename(file.path).substring(id.length + 1),
      ),
    );
  }

  Future<File?> _resolveOwnedArtifact(Model3DArtifact artifact) async {
    final reference = validModel3DArtifactReference(artifact.reference);
    if (reference != null) {
      final hydrated = await _artifactForReference(reference);
      if (hydrated != null) return File(hydrated.path!);
    }
    final path = artifact.path;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return await _isOwnedArtifactFile(file) ? file : null;
  }
}
