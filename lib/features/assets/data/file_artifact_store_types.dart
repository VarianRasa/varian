import 'dart:typed_data';

import 'package:uuid/uuid.dart';

const maxFileArtifactBytes = 512 * 1024 * 1024;

class FileArtifactStoreException implements Exception {
  const FileArtifactStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FileArtifact {
  const FileArtifact({
    this.path,
    this.url,
    this.reference,
    this.bytes,
    required this.fileName,
  });

  final String? path;
  final String? url;
  final String? reference;
  final Uint8List? bytes;
  final String fileName;
}

abstract interface class FileArtifactStore {
  Future<FileArtifact> save(Uint8List bytes, {String fileName});
  Future<FileArtifact?> hydrate(String reference, {String? fileName});
  Future<bool> exists(FileArtifact artifact);
  Future<Uint8List?> read(FileArtifact artifact);
  Future<void> dispose(FileArtifact artifact);
}

class MemoryFileArtifactStore implements FileArtifactStore {
  final Map<String, Uint8List> _items = {};
  int _nextId = 0;

  @override
  Future<FileArtifact> save(
    Uint8List bytes, {
    String fileName = 'document.bin',
  }) async {
    validateFileArtifactBytes(bytes, fileName: fileName);
    final reference = 'varian-file://memory-${_nextId++}';
    final stored = Uint8List.fromList(bytes);
    _items[reference] = stored;
    return FileArtifact(
      reference: reference,
      bytes: Uint8List.fromList(stored),
      fileName: sanitizeFileArtifactName(fileName),
    );
  }

  @override
  Future<FileArtifact?> hydrate(String reference, {String? fileName}) async {
    final bytes = _items[reference];
    if (bytes == null) return null;
    return FileArtifact(
      reference: reference,
      bytes: Uint8List.fromList(bytes),
      fileName: sanitizeFileArtifactName(fileName ?? 'document.bin'),
    );
  }

  @override
  Future<bool> exists(FileArtifact artifact) async {
    final reference = artifact.reference;
    return reference != null && _items.containsKey(reference);
  }

  @override
  Future<Uint8List?> read(FileArtifact artifact) async {
    final reference = artifact.reference;
    final bytes = reference == null ? null : _items[reference];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> dispose(FileArtifact artifact) async {
    // Durable file references outlive transient preview handles.
  }
}

void validateFileArtifactBytes(Uint8List bytes, {String? fileName}) {
  if (bytes.isEmpty || bytes.length > maxFileArtifactBytes) {
    throw const FileArtifactStoreException(
      'File content is empty or exceeds the size limit.',
    );
  }
  final extension = fileName == null
      ? ''
      : fileName.split('.').last.toLowerCase();
  if (extension == 'pdf' && !_startsWithAscii(bytes, '%PDF-')) {
    throw const FileArtifactStoreException(
      'PDF content does not have a valid signature.',
    );
  }
}

bool _startsWithAscii(Uint8List bytes, String value) {
  if (bytes.length < value.length) return false;
  for (var index = 0; index < value.length; index++) {
    if (bytes[index] != value.codeUnitAt(index)) return false;
  }
  return true;
}

String sanitizeFileArtifactName(String value) {
  final base = value
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'[<>:"|?*\u0000-\u001F]'), '_')
      .trim();
  if (base.isEmpty || base == '.' || base == '..') return 'document.bin';
  final bounded = base.substring(0, base.length > 160 ? 160 : base.length);
  return bounded;
}

String newFileArtifactReference() => 'varian-file://${const Uuid().v4()}';
