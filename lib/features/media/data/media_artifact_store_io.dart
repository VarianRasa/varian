import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:varian/domain/models/media_timeline.dart';

import 'media_artifact_store_types.dart';

MediaArtifactStore createPlatformMediaArtifactStore() =>
    NativeMediaArtifactStore();

Future<MediaArtifact?> hydratePlatformMediaArtifact(
  String reference, {
  MediaArtifactKind? kind,
  String? mimeType,
  String? checksum,
  String? fileName,
}) async {
  final store = NativeMediaArtifactStore();
  return store.hydrate(
    reference,
    kind: kind,
    mimeType: mimeType,
    checksum: checksum,
    fileName: fileName,
  );
}

Future<Uint8List?> readPlatformMediaArtifactReference(String reference) async {
  final store = NativeMediaArtifactStore();
  final artifact = await store.hydrate(reference);
  if (artifact == null) return null;
  try {
    return await store.read(artifact);
  } finally {
    await store.dispose(artifact);
  }
}

Future<void> disposePlatformHydratedMediaArtifact(MediaArtifact artifact) =>
    NativeMediaArtifactStore().dispose(artifact);

class NativeMediaArtifactStore implements MediaArtifactStore {
  @override
  Future<MediaArtifact> save(
    Uint8List bytes, {
    required MediaArtifactKind kind,
    required String mimeType,
    required String checksum,
    required String fileName,
    MediaStoragePolicy storagePolicy = MediaStoragePolicy.cache,
  }) async {
    validateMediaArtifactBytes(bytes);
    final actualChecksum = mediaArtifactChecksum(bytes);
    final normalizedChecksum = checksum.trim().isEmpty
        ? actualChecksum
        : checksum.trim();
    if (normalizedChecksum != actualChecksum) {
      throw const MediaArtifactStoreException(
        'Media artifact checksum does not match its bytes.',
      );
    }
    final directory = await _artifactDirectory(storagePolicy);
    await directory.create(recursive: true);
    final safeName = sanitizeMediaArtifactFileName(
      fileName,
      kind: kind,
      mimeType: mimeType,
    );
    final file = File(
      p.join(directory.path, '${normalizedChecksum}_${kind.name}_$safeName'),
    );
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return MediaArtifact(
      kind: kind,
      path: file.path,
      reference: mediaArtifactReference(
        storagePolicy,
        normalizedChecksum,
        kind,
      ),
      mimeType: mimeType,
      sizeBytes: bytes.length,
      checksum: normalizedChecksum,
    );
  }

  @override
  Future<bool> exists(MediaArtifact artifact) async {
    final path = artifact.path;
    if (path != null && path.isNotEmpty) {
      if (!await _isOwnedArtifactFile(File(path))) return false;
    } else {
      final reference = artifact.reference;
      if (reference == null || reference.isEmpty) return false;
    }
    return await read(artifact) != null;
  }

  @override
  Future<Uint8List?> read(MediaArtifact artifact) async {
    final path = artifact.path;
    File? file;
    if (path != null &&
        path.isNotEmpty &&
        await _isOwnedArtifactFile(File(path))) {
      file = File(path);
    } else if (artifact.reference != null) {
      final hydrated = await hydrate(
        artifact.reference!,
        kind: artifact.kind,
        mimeType: artifact.mimeType,
        checksum: artifact.checksum,
      );
      if (hydrated?.path != null) file = File(hydrated!.path!);
    }
    if (file == null || !await file.exists()) return null;
    final declaredSize = artifact.sizeBytes;
    if (declaredSize != null && declaredSize > maxMediaArtifactBytes) {
      return null;
    }
    if (await file.length() > maxMediaArtifactBytes ||
        (declaredSize != null && await file.length() != declaredSize)) {
      return null;
    }
    final bytes = await file.readAsBytes();
    if (!_matchesIntegrity(bytes, artifact)) return null;
    validateMediaArtifactBytes(bytes);
    return bytes;
  }

  @override
  Future<MediaArtifact?> hydrate(
    String reference, {
    MediaArtifactKind? kind,
    String? mimeType,
    String? checksum,
    String? fileName,
  }) async {
    final normalizedReference = normalizeMediaArtifactReference(reference);
    if (normalizedReference == null) return null;
    final policy = mediaStoragePolicyFromReference(normalizedReference);
    if (policy == null) return null;
    final resolvedKind =
        kind ?? mediaArtifactKindFromReference(normalizedReference);
    final resolvedChecksum =
        checksum ?? mediaArtifactChecksumFromReference(normalizedReference);
    if (resolvedKind == null || resolvedChecksum == null) return null;
    final directory = await _artifactDirectory(policy);
    final file = await _findArtifactFile(
      directory,
      checksum: resolvedChecksum,
      kind: resolvedKind,
    );
    if (file == null || !await _isOwnedArtifactFile(file)) return null;
    final size = await file.length();
    if (size <= 0 || size > maxMediaArtifactBytes) return null;
    final bytes = await file.readAsBytes();
    if (mediaArtifactChecksum(bytes) != resolvedChecksum) return null;
    return MediaArtifact(
      kind: resolvedKind,
      path: file.path,
      reference: normalizedReference,
      mimeType: mimeType ?? _mimeTypeForKind(resolvedKind),
      sizeBytes: size,
      checksum: resolvedChecksum,
    );
  }

  @override
  Future<void> dispose(MediaArtifact artifact) async {
    if (mediaStoragePolicyFromReference(artifact.reference ?? '') !=
        MediaStoragePolicy.ephemeral) {
      return;
    }
    final path = artifact.path;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await _isOwnedArtifactFile(file)) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  bool _matchesIntegrity(Uint8List bytes, MediaArtifact artifact) {
    final declaredSize = artifact.sizeBytes;
    if (declaredSize != null && declaredSize != bytes.length) return false;
    final checksum = artifact.checksum?.trim();
    return checksum == null ||
        checksum.isEmpty ||
        sha256.convert(bytes).toString() == checksum;
  }

  Future<Directory> _artifactDirectory(MediaStoragePolicy policy) async {
    final root = policy == MediaStoragePolicy.ephemeral
        ? await getTemporaryDirectory()
        : await getApplicationSupportDirectory();
    return Directory(p.join(root.path, 'varian-media', policy.name));
  }

  Future<File?> _findArtifactFile(
    Directory directory, {
    required String checksum,
    required MediaArtifactKind kind,
  }) async {
    if (!await directory.exists()) return null;
    final prefix = '${checksum}_${kind.name}_';
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && p.basename(entity.path).startsWith(prefix)) {
        return entity;
      }
    }
    return null;
  }

  Future<bool> _isOwnedArtifactFile(File file) async {
    try {
      if (!await file.exists()) return false;
      final support = await getApplicationSupportDirectory();
      final temporary = await getTemporaryDirectory();
      final resolved = await file.resolveSymbolicLinks();
      final roots = [
        p.join(support.path, 'varian-media'),
        p.join(temporary.path, 'varian-media'),
      ];
      for (final rootPath in roots) {
        final root = Directory(rootPath);
        if (!await root.exists()) continue;
        final resolvedRoot = await root.resolveSymbolicLinks();
        final relative = p.relative(resolved, from: resolvedRoot);
        if (relative != '.' &&
            !p.isAbsolute(relative) &&
            relative != '..' &&
            !relative.startsWith('..${p.separator}')) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  String _mimeTypeForKind(MediaArtifactKind kind) => switch (kind) {
    MediaArtifactKind.thumbnail => 'image/svg+xml',
    MediaArtifactKind.waveform => 'application/json',
    _ => 'application/octet-stream',
  };
}
