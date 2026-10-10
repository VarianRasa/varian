import 'dart:convert';

import 'document.dart';
import 'document_asset.dart';
import 'document_migrations.dart';

class DocumentPackageException extends FormatException {
  const DocumentPackageException(super.message);
}

class CanvasDocumentPackage {
  static const String format = 'varian.canvas.package';
  static const int packageVersion = 2;
  static const int minimumReaderVersion = 1;

  final CanvasDocument document;
  final DocumentAssetManifest assets;

  const CanvasDocumentPackage({
    required this.document,
    this.assets = const DocumentAssetManifest(),
  });

  Map<String, dynamic> toJson() {
    final resolvedAssets = assets.items.isEmpty ? document.assets : assets;
    final packagedDocument = document.copyWith(assets: resolvedAssets);
    return {
      'format': format,
      'packageVersion': packageVersion,
      'compatibility': {
        'minimumReaderVersion': minimumReaderVersion,
        'documentSchemaVersion': packagedDocument.schemaVersion,
      },
      // Package envelopes are persisted documents, not render-facing runtime
      // snapshots. Keep native paths, provider URLs, and inline delivery data
      // out of both the document and the duplicated asset manifest.
      'document': packagedDocument.toPersistenceJson(),
      'assets': resolvedAssets.toPersistenceJson(),
    };
  }

  String encode({bool pretty = true}) {
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(toJson())
        : jsonEncode(toJson());
  }

  factory CanvasDocumentPackage.fromJson(Map<String, dynamic> json) {
    if (json['format'] != format) {
      throw const DocumentPackageException(
        'Unsupported Varian document package.',
      );
    }
    final version = (json['packageVersion'] as num?)?.toInt() ?? 1;
    if (version > packageVersion) {
      throw DocumentPackageException(
        'Document package version $version is newer than supported version $packageVersion.',
      );
    }
    final rawDocument = json['document'];
    if (rawDocument is! Map) {
      throw const DocumentPackageException(
        'Document package is missing document data.',
      );
    }
    final rawAssets = json['assets'];
    final assets = DocumentAssetManifest.fromJson(rawAssets);
    final document = CanvasDocument.fromJson(
      Map<String, dynamic>.from(rawDocument),
    );
    return CanvasDocumentPackage(
      document: document.copyWith(
        assets: assets.items.isEmpty ? document.assets : assets,
      ),
      assets: assets.items.isEmpty ? document.assets : assets,
    );
  }

  factory CanvasDocumentPackage.decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const DocumentPackageException(
          'Document package root must be an object.',
        );
      }
      return CanvasDocumentPackage.fromJson(Map<String, dynamic>.from(decoded));
    } on DocumentPackageException {
      rethrow;
    } on DocumentSchemaException {
      rethrow;
    } catch (error) {
      throw DocumentPackageException('Invalid document package: $error');
    }
  }
}
