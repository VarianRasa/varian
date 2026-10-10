import 'dart:typed_data';

import 'package:uuid/uuid.dart';

const int maxCaptureAssetBytes = 50 * 1024 * 1024;
final RegExp _captureAssetReferencePattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$',
);

abstract interface class CaptureAssetStore {
  Future<String> save(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  });

  Future<Uint8List?> read(String reference);

  Future<bool> exists(String reference);

  Future<void> delete(String reference);
}

class MemoryCaptureAssetStore implements CaptureAssetStore {
  final Map<String, Uint8List> _items = {};

  List<String> get references => List.unmodifiable(_items.keys);

  @override
  Future<String> save(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    _validateCaptureAsset(bytes);
    final reference = 'capture-asset://${_newCaptureAssetId()}';
    _items[reference] = Uint8List.fromList(bytes);
    return reference;
  }

  @override
  Future<Uint8List?> read(String reference) async {
    final bytes = _items[reference];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<bool> exists(String reference) async => _items.containsKey(reference);

  @override
  Future<void> delete(String reference) async {
    _items.remove(reference);
  }
}

void validateCaptureAssetBytes(Uint8List bytes) {
  _validateCaptureAsset(bytes);
}

bool isCaptureAssetReference(String reference) {
  final uri = Uri.tryParse(reference.trim());
  return uri != null &&
      uri.scheme == 'capture-asset' &&
      uri.host.isNotEmpty &&
      uri.path.isEmpty &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty &&
      _captureAssetReferencePattern.hasMatch(uri.host);
}

void _validateCaptureAsset(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maxCaptureAssetBytes) {
    throw const CaptureAssetStoreException(
      'Capture asset is empty or exceeds the size limit.',
    );
  }
}

class CaptureAssetStoreException implements Exception {
  const CaptureAssetStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _newCaptureAssetId() => const Uuid().v4().replaceAll('-', '');

String newCaptureAssetReference() => 'capture-asset://${_newCaptureAssetId()}';

String sanitizeCaptureAssetFileName(String value) {
  final base = value
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'[<>:"|?*\u0000-\u001F]'), '_')
      .trim();
  if (base.isEmpty || base == '.' || base == '..') return 'capture.bin';
  return base.substring(0, base.length > 160 ? 160 : base.length);
}
