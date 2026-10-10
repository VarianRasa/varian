import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import 'document_asset.dart';
import 'document_package.dart';
import 'durable_asset_reference.dart';

class DocumentPackageArchiveException extends FormatException {
  const DocumentPackageArchiveException(super.message);
}

class DocumentPackageArchiveChecksum {
  DocumentPackageArchiveChecksum._();

  static String sha256(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();
}

class DocumentPackageArchive {
  static const format = 'varian.canvas.archive';
  static const archiveVersion = 1;
  static const defaultPbkdf2Iterations = 120000;
  static const maxPbkdf2Iterations = 1000000;
  static const _magic = [0x56, 0x43, 0x41, 0x31];
  static const _associatedData = 'varian.canvas.archive:v1';

  final CanvasDocumentPackage package;
  final Map<String, Uint8List> assetBytes;
  final List<String> invalidAssetIds;
  final bool packageChecksumValid;
  final bool encrypted;

  DocumentPackageArchive({
    required this.package,
    Map<String, Uint8List> assetBytes = const {},
    this.invalidAssetIds = const [],
    this.packageChecksumValid = true,
    this.encrypted = false,
  }) : assetBytes = Map.unmodifiable({
         for (final entry in assetBytes.entries)
           entry.key: Uint8List.fromList(entry.value),
       });

  DocumentAssetManifest get _effectiveAssets =>
      package.assets.items.isEmpty ? package.document.assets : package.assets;

  List<String> get missingAssetIds => _effectiveAssets.items
      .where((asset) => !assetBytes.containsKey(asset.id))
      .map((asset) => asset.id)
      .toList(growable: false);

  bool get isPortable {
    try {
      _effectiveAssets.validateIdentity();
    } on FormatException {
      return false;
    }
    return packageChecksumValid &&
        missingAssetIds.isEmpty &&
        invalidAssetIds.isEmpty &&
        assetBytes.keys.every(_effectiveAssets.entries.containsKey) &&
        _assetChecksumsMatchManifest;
  }

  Map<String, dynamic> toManifestJson({String? password}) {
    _effectiveAssets.validateIdentity();
    final entries = _effectiveAssets.items
        .map((asset) {
          final bytes = assetBytes[asset.id];
          final checksum = bytes == null ? asset.checksum : _checksum(bytes);
          return <String, dynamic>{
            'id': asset.id,
            'name': asset.name,
            'mimeType': asset.mimeType,
            'path': _assetPath(asset.id),
            'embedded': bytes != null,
            'sizeBytes': bytes?.length ?? asset.sizeBytes,
            'checksum': ?checksum,
          };
        })
        .toList(growable: false);
    return {
      'format': format,
      'archiveVersion': archiveVersion,
      'encrypted': password?.trim().isNotEmpty == true,
      'document': 'document.json',
      'manifest': 'manifest.json',
      'packageChecksum': _packageChecksum(package),
      'portable': isPortable,
      'assets': entries,
    };
  }

  Uint8List encode({
    String? password,
    int pbkdf2Iterations = defaultPbkdf2Iterations,
  }) {
    if (pbkdf2Iterations < 10000 || pbkdf2Iterations > maxPbkdf2Iterations) {
      throw ArgumentError.value(
        pbkdf2Iterations,
        'pbkdf2Iterations',
        'PBKDF2 iteration count must be between 10000 and '
            '$maxPbkdf2Iterations.',
      );
    }
    _validateAssetBytes();
    final normalizedPassword = password?.trim() ?? '';
    final zipBytes = _encodeZip(encrypted: normalizedPassword.isNotEmpty);
    if (normalizedPassword.isEmpty) return zipBytes;
    return _encrypt(zipBytes, normalizedPassword, pbkdf2Iterations);
  }

  factory DocumentPackageArchive.decode(Uint8List bytes, {String? password}) {
    try {
      final envelope = _decryptIfNeeded(bytes, password?.trim() ?? '');
      final archive = ZipDecoder().decodeBytes(envelope.bytes, verify: true);
      final manifestFiles = archive.files
          .where((file) => file.name == 'manifest.json')
          .toList(growable: false);
      final documentFiles = archive.files
          .where((file) => file.name == 'document.json')
          .toList(growable: false);
      if (manifestFiles.length != 1 ||
          documentFiles.length != 1 ||
          !manifestFiles.single.isFile ||
          !documentFiles.single.isFile) {
        throw const DocumentPackageArchiveException(
          'Archive must contain exactly one manifest.json and document.json.',
        );
      }
      final manifestFile = manifestFiles.single;
      final documentFile = documentFiles.single;
      final manifest = _decodeObject(manifestFile.content, 'manifest.json');
      if (manifest['format'] != format) {
        throw const DocumentPackageArchiveException(
          'Unsupported Varian project archive.',
        );
      }
      final declaredEncrypted = manifest['encrypted'];
      if (declaredEncrypted is! bool ||
          declaredEncrypted != envelope.encrypted) {
        throw const DocumentPackageArchiveException(
          'Archive encryption metadata does not match its envelope.',
        );
      }
      if (manifest['document'] != 'document.json' ||
          manifest['manifest'] != 'manifest.json') {
        throw const DocumentPackageArchiveException(
          'Archive document or manifest path is invalid.',
        );
      }
      final rawVersion = manifest['archiveVersion'];
      if (rawVersion is! num ||
          !rawVersion.isFinite ||
          rawVersion != rawVersion.toInt() ||
          rawVersion < 1) {
        throw const DocumentPackageArchiveException(
          'Archive version is invalid.',
        );
      }
      final version = rawVersion.toInt();
      if (version > archiveVersion) {
        throw DocumentPackageArchiveException(
          'Archive version $version is newer than supported version $archiveVersion.',
        );
      }
      final package = CanvasDocumentPackage.decode(
        utf8.decode(documentFile.content, allowMalformed: false),
      );
      final rawPackageChecksum = manifest['packageChecksum'];
      if (rawPackageChecksum is! String ||
          !RegExp(
            r'^(?:sha256:)?[0-9a-fA-F]{64}$',
          ).hasMatch(rawPackageChecksum)) {
        throw const DocumentPackageArchiveException(
          'Archive package checksum is invalid.',
        );
      }
      final declaredPortable = manifest['portable'];
      if (declaredPortable is! bool) {
        throw const DocumentPackageArchiveException(
          'Archive portability metadata is invalid.',
        );
      }
      final embeddedAssets = <String, Uint8List>{};
      final invalidAssets = <String>[];
      final rawAssets = manifest['assets'];
      if (rawAssets is! List || rawAssets.length > 500) {
        throw const DocumentPackageArchiveException(
          'Archive asset manifest must contain a bounded list.',
        );
      }
      final knownAssets = package.assets.items.isEmpty
          ? package.document.assets
          : package.assets;
      if (knownAssets.items.length > 500) {
        throw const DocumentPackageArchiveException(
          'Archive contains too many document assets.',
        );
      }
      for (final asset in knownAssets.items) {
        _validateArchiveAssetReferences(asset);
        if (asset.id.isEmpty ||
            asset.id.length > 256 ||
            asset.id.trim() != asset.id ||
            _hasArchiveControlCharacter(asset.id)) {
          throw const DocumentPackageArchiveException(
            'Archive document asset IDs are invalid.',
          );
        }
      }
      final declaredEmbeddedPaths = <String>{};
      final declaredAssetIds = <String>{};
      for (final raw in rawAssets) {
        if (raw is! Map) {
          throw const DocumentPackageArchiveException(
            'Archive asset entries must be objects.',
          );
        }
        final rawId = raw['id'];
        final rawPath = raw['path'];
        if (rawId is! String || rawPath is! String) {
          throw const DocumentPackageArchiveException(
            'Archive asset entries must declare string IDs and paths.',
          );
        }
        final id = rawId.trim();
        if (id.isEmpty || rawId != id || !knownAssets.entries.containsKey(id)) {
          throw DocumentPackageArchiveException(
            'Archive asset $id is not declared by document.json.',
          );
        }
        if (!declaredAssetIds.add(id)) {
          throw DocumentPackageArchiveException(
            'Archive contains duplicate asset $id.',
          );
        }
        final canonicalPath = _assetPath(id);
        if (rawPath != canonicalPath) {
          throw DocumentPackageArchiveException(
            'Archive asset $id has a non-canonical payload path.',
          );
        }
        final knownAsset = knownAssets[id]!;
        if (raw['name'] != knownAsset.name ||
            raw['mimeType'] != knownAsset.mimeType) {
          throw DocumentPackageArchiveException(
            'Archive asset $id does not match document metadata.',
          );
        }
        final embedded = raw['embedded'];
        if (embedded is! bool) {
          throw DocumentPackageArchiveException(
            'Archive asset $id has an invalid embedded flag.',
          );
        }
        final rawSize = raw['sizeBytes'];
        int? declaredSize;
        if (rawSize != null) {
          if (rawSize is! num ||
              !rawSize.isFinite ||
              rawSize != rawSize.toInt() ||
              rawSize < 0 ||
              rawSize > 512 * 1024 * 1024) {
            throw DocumentPackageArchiveException(
              'Archive asset $id has an invalid size.',
            );
          }
          declaredSize = rawSize.toInt();
        }
        final rawChecksum = raw['checksum'];
        String? declaredChecksum;
        if (rawChecksum != null) {
          if (rawChecksum is! String ||
              !RegExp(r'^(?:sha256:)?[0-9a-fA-F]{64}$').hasMatch(rawChecksum)) {
            throw DocumentPackageArchiveException(
              'Archive asset $id has an invalid checksum.',
            );
          }
          declaredChecksum = rawChecksum;
        }
        if (embedded &&
            (declaredSize == null ||
                declaredSize < 1 ||
                declaredChecksum == null)) {
          throw DocumentPackageArchiveException(
            'Embedded archive asset $id must declare size and checksum.',
          );
        }
        if (embedded && knownAsset.checksum?.trim().isNotEmpty != true) {
          throw DocumentPackageArchiveException(
            'Embedded archive asset $id must declare a document checksum.',
          );
        }
        if (!embedded &&
            (declaredSize != knownAsset.sizeBytes ||
                (declaredChecksum == null) !=
                    (knownAsset.checksum?.trim().isNotEmpty != true) ||
                (declaredChecksum != null &&
                    !_checksumEquals(
                      declaredChecksum,
                      knownAsset.checksum!.trim(),
                    )))) {
          throw DocumentPackageArchiveException(
            'Archive asset $id metadata does not match document.json.',
          );
        }
        final file = archive.find(canonicalPath);
        if (!embedded) {
          if (file != null) {
            throw DocumentPackageArchiveException(
              'Archive contains bytes for a non-embedded asset $id.',
            );
          }
          continue;
        }
        declaredEmbeddedPaths.add(canonicalPath);
        if (file == null || !file.isFile) continue;

        final asset = file.content;
        if (declaredSize == null ||
            declaredSize < 1 ||
            declaredSize != asset.length ||
            (knownAsset.sizeBytes != null &&
                knownAsset.sizeBytes != declaredSize) ||
            declaredChecksum == null ||
            !_checksumEquals(_checksum(asset), declaredChecksum) ||
            (knownAsset.checksum?.trim().isNotEmpty == true &&
                !_checksumEquals(
                  _checksum(asset),
                  knownAsset.checksum!.trim(),
                )) ||
            !_assetBytesMatchMimeSignature(asset, knownAsset.mimeType)) {
          invalidAssets.add(id);
          continue;
        }
        embeddedAssets[id] = asset;
      }
      if (declaredAssetIds.length != knownAssets.items.length ||
          knownAssets.items.any(
            (asset) => !declaredAssetIds.contains(asset.id),
          )) {
        throw const DocumentPackageArchiveException(
          'Archive manifest does not exactly match document assets.',
        );
      }
      final archiveAssetPaths = <String>{};
      for (final file in archive.files) {
        if (file.name == 'manifest.json' || file.name == 'document.json') {
          continue;
        }
        if (!file.name.startsWith('assets/')) {
          throw DocumentPackageArchiveException(
            'Archive contains an unsupported path ${file.name}.',
          );
        }
        if (!archiveAssetPaths.add(file.name)) {
          throw DocumentPackageArchiveException(
            'Archive contains duplicate asset payload ${file.name}.',
          );
        }
        if (!declaredEmbeddedPaths.contains(file.name)) {
          throw DocumentPackageArchiveException(
            'Archive contains unpaired asset bytes at ${file.name}.',
          );
        }
      }
      final packageChecksumValid = _checksumEquals(
        _packageChecksum(package),
        rawPackageChecksum,
      );
      final decoded = DocumentPackageArchive(
        package: package,
        assetBytes: embeddedAssets,
        invalidAssetIds: invalidAssets,
        packageChecksumValid: packageChecksumValid,
        encrypted: envelope.encrypted,
      );
      if (declaredPortable != decoded.isPortable) {
        throw const DocumentPackageArchiveException(
          'Archive portability metadata does not match its contents.',
        );
      }
      return decoded;
    } on DocumentPackageArchiveException {
      rethrow;
    } on InvalidCipherTextException {
      throw const DocumentPackageArchiveException(
        'Unable to decrypt archive. Check the project password.',
      );
    } catch (error) {
      throw DocumentPackageArchiveException('Invalid project archive: $error');
    }
  }

  Uint8List _encodeZip({required bool encrypted}) {
    final zip = Archive();
    final manifestJson = toManifestJson();
    manifestJson['encrypted'] = encrypted;
    final manifest = jsonEncode(manifestJson);
    zip.addFile(ArchiveFile.string('manifest.json', manifest));
    zip.addFile(
      ArchiveFile.bytes(
        'document.json',
        utf8.encode(package.encode(pretty: false)),
      ),
    );
    for (final entry in assetBytes.entries) {
      zip.addFile(ArchiveFile.bytes(_assetPath(entry.key), entry.value));
    }
    return ZipEncoder().encodeBytes(zip);
  }

  bool get _assetChecksumsMatchManifest {
    for (final asset in _effectiveAssets.items) {
      final bytes = assetBytes[asset.id];
      if (bytes != null && bytes.isEmpty) return false;
      final expected = asset.checksum?.trim();
      if (bytes != null &&
          expected != null &&
          expected.isNotEmpty &&
          !_checksumEquals(_checksum(bytes), expected)) {
        return false;
      }
    }
    return true;
  }

  void _validateAssetBytes() {
    try {
      _effectiveAssets.validateIdentity();
    } on FormatException catch (error) {
      throw DocumentPackageArchiveException(
        'Archive asset manifest identities are invalid: ${error.message}',
      );
    }
    final assets = _effectiveAssets.items;
    if (assets.length > 500) {
      throw const DocumentPackageArchiveException(
        'Archive contains too many document assets.',
      );
    }
    for (final asset in assets) {
      _validateArchiveAssetReferences(asset);
      if (asset.id.isEmpty ||
          asset.id.length > 256 ||
          asset.id.trim() != asset.id ||
          _hasArchiveControlCharacter(asset.id)) {
        throw const DocumentPackageArchiveException(
          'Archive document asset IDs are invalid.',
        );
      }
    }
    final knownIds = _effectiveAssets.entries.keys.toSet();
    final unknownIds = assetBytes.keys.where((id) => !knownIds.contains(id));
    if (unknownIds.isNotEmpty) {
      throw DocumentPackageArchiveException(
        'Archive contains bytes for unknown asset ${unknownIds.first}.',
      );
    }
    for (final entry in assetBytes.entries) {
      if (entry.value.isEmpty || entry.value.length > 512 * 1024 * 1024) {
        throw DocumentPackageArchiveException(
          'Asset ${entry.key} has an invalid embedded payload size.',
        );
      }
      final asset = _effectiveAssets.entries[entry.key]!;
      if (asset.sizeBytes == null || asset.sizeBytes != entry.value.length) {
        throw DocumentPackageArchiveException(
          'Asset ${entry.key} size does not match its declared size.',
        );
      }
      if (asset.checksum?.trim().isNotEmpty != true) {
        throw DocumentPackageArchiveException(
          'Asset ${entry.key} must declare a checksum for embedded bytes.',
        );
      }
      if (!_assetBytesMatchMimeSignature(entry.value, asset.mimeType)) {
        throw DocumentPackageArchiveException(
          'Asset ${entry.key} bytes do not match its declared MIME type.',
        );
      }
    }
    for (final asset in assets) {
      final bytes = assetBytes[asset.id];
      final expected = asset.checksum?.trim();
      if (bytes != null &&
          expected != null &&
          expected.isNotEmpty &&
          !_checksumEquals(_checksum(bytes), expected)) {
        throw DocumentPackageArchiveException(
          'Asset ${asset.id} checksum does not match its declared checksum.',
        );
      }
    }
  }

  static _ArchiveEnvelope _decryptIfNeeded(Uint8List input, String password) {
    if (!_startsWith(input, _magic)) {
      return _ArchiveEnvelope(bytes: input, encrypted: false);
    }
    if (password.isEmpty) {
      throw const DocumentPackageArchiveException(
        'Archive is encrypted and requires a password.',
      );
    }
    if (input.length < 37 || input[4] != 1) {
      throw const DocumentPackageArchiveException(
        'Invalid archive encryption header.',
      );
    }
    final iterations = _readUint32(input, 5);
    if (iterations < 10000 || iterations > maxPbkdf2Iterations) {
      throw const DocumentPackageArchiveException(
        'Invalid archive key-derivation parameters.',
      );
    }
    final salt = Uint8List.fromList(input.sublist(9, 25));
    final nonce = Uint8List.fromList(input.sublist(25, 37));
    final ciphertext = Uint8List.fromList(input.sublist(37));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(_deriveKey(password, salt, iterations)),
          128,
          nonce,
          Uint8List.fromList(utf8.encode(_associatedData)),
        ),
      );
    return _ArchiveEnvelope(bytes: cipher.process(ciphertext), encrypted: true);
  }

  Uint8List _encrypt(Uint8List plaintext, String password, int iterations) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => random.nextInt(256)),
    );
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(_deriveKey(password, salt, iterations)),
          128,
          nonce,
          Uint8List.fromList(utf8.encode(_associatedData)),
        ),
      );
    final ciphertext = cipher.process(plaintext);
    final output = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(1)
      ..add(_uint32(iterations))
      ..add(salt)
      ..add(nonce)
      ..add(ciphertext);
    return output.takeBytes();
  }

  static Uint8List _deriveKey(String password, Uint8List salt, int iterations) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    final key = Uint8List(32);
    derivator.deriveKey(Uint8List.fromList(utf8.encode(password)), 0, key, 0);
    return key;
  }

  static Map<String, dynamic> _decodeObject(Uint8List bytes, String path) {
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map) {
      throw DocumentPackageArchiveException(
        '$path must contain a JSON object.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  static String _assetPath(String id) =>
      'assets/${base64UrlEncode(utf8.encode(id)).replaceAll('=', '')}';

  static String _packageChecksum(CanvasDocumentPackage package) => _checksum(
    Uint8List.fromList(utf8.encode(_canonicalJson(package.toJson()))),
  );

  static String _checksum(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();

  static bool _checksumEquals(String actual, String expected) {
    final normalized = expected.toLowerCase().replaceFirst('sha256:', '');
    return actual.toLowerCase() == normalized;
  }

  static String _canonicalJson(Object? value) =>
      jsonEncode(_canonicalize(value));

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is Iterable) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }

  static bool _assetBytesMatchMimeSignature(Uint8List bytes, String mimeType) {
    final normalized = mimeType.trim().toLowerCase().split(';').first;
    bool startsWith(List<int> prefix, {int offset = 0}) {
      if (bytes.length < offset + prefix.length) return false;
      for (var index = 0; index < prefix.length; index++) {
        if (bytes[offset + index] != prefix[index]) return false;
      }
      return true;
    }

    bool containsAscii(String value) {
      final needle = value.codeUnits;
      final limit = bytes.length - needle.length;
      for (var start = 0; start <= limit && start < 1024; start++) {
        var matches = true;
        for (var index = 0; index < needle.length; index++) {
          final actual = bytes[start + index];
          final expected = needle[index];
          final lowerActual = actual >= 65 && actual <= 90
              ? actual + 32
              : actual;
          final lowerExpected = expected >= 65 && expected <= 90
              ? expected + 32
              : expected;
          if (lowerActual != lowerExpected) {
            matches = false;
            break;
          }
        }
        if (matches) return true;
      }
      return false;
    }

    return switch (normalized) {
      'image/png' => startsWith([137, 80, 78, 71, 13, 10, 26, 10]),
      'image/jpeg' => startsWith([255, 216, 255]),
      'image/gif' => startsWith('GIF'.codeUnits),
      'image/webp' =>
        startsWith('RIFF'.codeUnits) && startsWith('WEBP'.codeUnits, offset: 8),
      'image/bmp' => startsWith('BM'.codeUnits),
      'image/svg+xml' => containsAscii('<svg'),
      'application/pdf' => startsWith('%PDF-'.codeUnits),
      'application/zip' ||
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
      'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
        startsWith([80, 75, 3, 4]) || startsWith([80, 75, 5, 6]),
      'model/gltf-binary' => startsWith('glTF'.codeUnits),
      'video/mp4' ||
      'video/quicktime' ||
      'audio/mp4' => startsWith('ftyp'.codeUnits, offset: 4),
      'video/x-msvideo' =>
        startsWith('RIFF'.codeUnits) && startsWith('AVI '.codeUnits, offset: 8),
      'video/x-matroska' || 'video/webm' => startsWith([26, 69, 223, 163]),
      'audio/wav' =>
        startsWith('RIFF'.codeUnits) && startsWith('WAVE'.codeUnits, offset: 8),
      'audio/mpeg' =>
        startsWith('ID3'.codeUnits) ||
            (bytes.length >= 2 && bytes[0] == 255 && (bytes[1] & 224) == 224),
      'audio/flac' => startsWith('fLaC'.codeUnits),
      'audio/ogg' => startsWith('OggS'.codeUnits),
      'application/octet-stream' => true,
      _ => true,
    };
  }

  static void _validateArchiveAssetReferences(DocumentAsset asset) {
    String? typedReference(String? value) => switch (asset.kind) {
      DocumentAssetKind.image => validImageArtifactReference(value),
      DocumentAssetKind.audio => validMediaArtifactReference(value),
      DocumentAssetKind.video => validVideoArtifactReference(value),
      DocumentAssetKind.model3d => validModel3DArtifactReference(value),
      DocumentAssetKind.document => validFileArtifactReference(value),
      _ => null,
    };

    final durable = asset.durableReference;
    final isDurable =
        durableAssetReference(durable) != null ||
        typedReference(durable) != null;
    final thumbnail = asset.thumbnailReference;
    final isSafeThumbnail =
        thumbnail == null ||
        durableAssetReference(thumbnail) != null ||
        validImageArtifactReference(thumbnail) != null ||
        validMediaArtifactReference(thumbnail) != null;

    // Archives are durable envelopes. Native paths, provider URLs, signed
    // delivery URLs, inline data, and object URLs are never archive metadata.
    if (asset.localPath != null ||
        asset.remoteUrl != null ||
        (durable != null && !isDurable) ||
        !isSafeThumbnail) {
      throw const DocumentPackageArchiveException(
        'Archive asset references must use validated durable identities.',
      );
    }
  }

  static bool _hasArchiveControlCharacter(String value) =>
      value.codeUnits.any((code) => code < 0x20 || code == 0x7f);

  static bool _startsWith(List<int> input, List<int> prefix) {
    if (input.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (input[index] != prefix[index]) return false;
    }
    return true;
  }

  static int _readUint32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static List<int> _uint32(int value) => [
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ];
}

class _ArchiveEnvelope {
  final Uint8List bytes;
  final bool encrypted;

  const _ArchiveEnvelope({required this.bytes, required this.encrypted});
}
