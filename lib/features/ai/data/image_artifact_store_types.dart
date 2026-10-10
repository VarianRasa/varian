import 'dart:typed_data';

import 'video_media_validation.dart';

const maxImageArtifactBytes = 50 * 1024 * 1024;

class ImageArtifactStoreException implements Exception {
  final String message;

  const ImageArtifactStoreException(this.message);

  @override
  String toString() => message;
}

class ImageArtifact {
  final String? path;
  final String? url;
  final String? reference;
  final Uint8List? bytes;
  final String fileName;

  const ImageArtifact({
    this.path,
    this.url,
    this.reference,
    this.bytes,
    required this.fileName,
  });

  bool get isPersistent => reference?.trim().isNotEmpty == true;

  ImageArtifact copyWith({String? path, String? url, String? reference}) =>
      ImageArtifact(
        path: path ?? this.path,
        url: url ?? this.url,
        reference: reference ?? this.reference,
        bytes: bytes,
        fileName: fileName,
      );
}

abstract interface class ImageArtifactStore {
  Future<ImageArtifact> save(Uint8List bytes, {String fileName});

  Future<ImageArtifact?> hydrate(String reference, {String? fileName});

  Future<bool> exists(ImageArtifact artifact);

  Future<Uint8List?> read(ImageArtifact artifact);

  Future<void> dispose(ImageArtifact artifact);
}

class MemoryImageArtifactStore implements ImageArtifactStore {
  final Map<String, Uint8List> _items = {};
  int _nextId = 0;

  @override
  Future<ImageArtifact> save(
    Uint8List bytes, {
    String fileName = 'image.png',
  }) async {
    validateImageArtifactBytes(bytes);
    final safeName = sanitizeImageArtifactFileName(fileName);
    final reference = 'varian-image://memory-${_nextId++}';
    final stored = Uint8List.fromList(bytes);
    _items[reference] = stored;
    return ImageArtifact(
      reference: reference,
      bytes: Uint8List.fromList(stored),
      fileName: safeName,
    );
  }

  @override
  Future<ImageArtifact?> hydrate(String reference, {String? fileName}) async {
    final bytes = _items[reference];
    if (bytes == null) return null;
    return ImageArtifact(
      reference: reference,
      bytes: Uint8List.fromList(bytes),
      fileName: sanitizeImageArtifactFileName(fileName ?? 'image.png'),
    );
  }

  @override
  Future<bool> exists(ImageArtifact artifact) async {
    final reference = artifact.reference;
    return reference != null && _items.containsKey(reference);
  }

  @override
  Future<Uint8List?> read(ImageArtifact artifact) async {
    final reference = artifact.reference;
    final bytes = reference == null ? null : _items[reference];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> dispose(ImageArtifact artifact) async {
    // Image artifacts referenced by a canvas are durable. Runtime hydration
    // disposal revokes only the transient render handle on Web.
  }
}

void validateImageArtifactBytes(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maxImageArtifactBytes) {
    throw const ImageArtifactStoreException(
      'Image content is empty or exceeds the size limit.',
    );
  }
  if (!isValidImageBytes(bytes)) {
    throw const ImageArtifactStoreException(
      'Image content is not a valid PNG, JPEG, or WebP image.',
    );
  }
}

String sanitizeImageArtifactFileName(String value) {
  final base = value
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'[<>:"|?*\u0000-\u001F]'), '_')
      .trim();
  final withoutExtension = base.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final safeBase = withoutExtension
      .trim()
      .replaceFirst(RegExp(r'^\.+'), '')
      .trim();
  final name = safeBase.isEmpty ? 'generated-image' : safeBase;
  final bounded = name.substring(0, name.length > 120 ? 120 : name.length);
  return '$bounded${_extensionForName(value)}';
}

String _extensionForName(String value) {
  final extension = value.split(RegExp(r'[\\/]')).last.split('.').last;
  switch (extension.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return '.jpg';
    case 'webp':
      return '.webp';
    default:
      return '.png';
  }
}
