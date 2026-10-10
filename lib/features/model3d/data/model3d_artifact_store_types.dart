import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../domain/models/durable_asset_reference.dart';
import 'model3d_validation.dart';

class Model3DArtifact {
  final String? path;
  final String? url;
  final String? reference;
  final Uint8List? bytes;
  final String fileName;

  const Model3DArtifact({
    this.path,
    this.url,
    this.reference,
    this.bytes,
    required this.fileName,
  });

  bool get isLocal => path?.isNotEmpty == true;
  bool get isWeb => url?.isNotEmpty == true;
  bool get isPersistent => reference?.isNotEmpty == true;
}

abstract interface class Model3DArtifactStore {
  Future<Model3DArtifact> save(Uint8List bytes, {String fileName});
  Future<Model3DArtifact?> hydrate(String reference, {String? fileName});
  Future<bool> exists(Model3DArtifact artifact);
  Future<Uint8List?> read(Model3DArtifact artifact);
  Future<void> dispose(Model3DArtifact artifact);
}

class MemoryModel3DArtifactStore implements Model3DArtifactStore {
  final Map<String, Uint8List> _items = {};
  final Set<Model3DArtifact> _disposedHandles = Set<Model3DArtifact>.identity();

  @override
  Future<Model3DArtifact> save(
    Uint8List bytes, {
    String fileName = 'model.glb',
  }) async {
    validateGlbBytes(bytes);
    final safeName = sanitizeModel3DFileName(fileName);
    final reference = 'varian-model3d://${const Uuid().v4()}';
    _items[reference] = Uint8List.fromList(bytes);
    return Model3DArtifact(
      path: reference,
      reference: reference,
      bytes: Uint8List.fromList(bytes),
      fileName: safeName,
    );
  }

  @override
  Future<Model3DArtifact?> hydrate(String reference, {String? fileName}) async {
    final normalized = validModel3DArtifactReference(reference);
    if (normalized == null) return null;
    final bytes = _items[normalized];
    if (bytes == null) return null;
    return Model3DArtifact(
      path: normalized,
      reference: normalized,
      bytes: Uint8List.fromList(bytes),
      fileName: fileName ?? 'model.glb',
    );
  }

  @override
  Future<bool> exists(Model3DArtifact artifact) async {
    final path = artifact.path;
    if (path == null) return artifact.bytes?.isNotEmpty == true;
    return _items.containsKey(path);
  }

  @override
  Future<Uint8List?> read(Model3DArtifact artifact) async {
    if (_disposedHandles.contains(artifact)) return null;
    final path = artifact.path;
    final bytes = path == null ? null : _items[path];
    if (bytes != null) return Uint8List.fromList(bytes);
    return artifact.bytes == null ? null : Uint8List.fromList(artifact.bytes!);
  }

  @override
  Future<void> dispose(Model3DArtifact artifact) async {
    _disposedHandles.add(artifact);
    // Model references are durable document data. Releasing a hydrated handle
    // must not delete bytes that a reopened document still needs.
  }
}
