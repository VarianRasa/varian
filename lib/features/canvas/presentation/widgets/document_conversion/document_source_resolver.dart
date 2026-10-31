import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_models.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/file_preview_type.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';

const maxDocumentPreviewBytes = 100 * 1024 * 1024;

class ResolvedDocumentSource {
  const ResolvedDocumentSource({required this.bytes, required this.extension});

  final Uint8List bytes;
  final String extension;
}

typedef LocalDocumentReader = Future<Uint8List?> Function(String path);
typedef RemoteDocumentReader = Future<Uint8List?> Function(Uri uri);
typedef StorageDocumentReader =
    Future<Uint8List?> Function(FilePayload payload, {required int maxBytes});

Future<ResolvedDocumentSource> resolveDocumentSource(
  FilePayload payload, {
  LocalDocumentReader? readLocal,
  RemoteDocumentReader? readRemote,
  StorageDocumentReader? readStorage,
  TransientFileSourceResolver? sourceResolver,
  int maxBytes = maxDocumentPreviewBytes,
}) async {
  final extension = normalizedFileExtension(payload);
  if (!const {
    'doc',
    'docx',
    'rtf',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'odt',
    'ods',
    'odp',
  }.contains(extension)) {
    throw const DocumentConversionFailure(
      DocumentConversionFailureCode.unsupportedExtension,
      'This document format is not supported.',
    );
  }

  Uint8List? bytes;
  final encoded = payload.base64Data?.trim();
  if (encoded != null && encoded.isNotEmpty) {
    try {
      final data = encoded.contains(',')
          ? encoded.substring(encoded.indexOf(',') + 1)
          : encoded;
      bytes = base64Decode(data);
    } catch (_) {}
  }
  if (bytes == null) {
    final resolver = sourceResolver;
    if (readStorage != null) {
      bytes = await readStorage(payload, maxBytes: maxBytes);
    } else if (resolver != null) {
      bytes = await resolver.resolveBytes(payload, maxBytes: maxBytes);
    }
  }
  final path = payload.localPath?.trim();
  if (bytes == null && path != null && path.isNotEmpty && readLocal != null) {
    bytes = await readLocal(path);
  }
  final uri = validDocumentRemoteUri(payload.remoteUrl);
  if (bytes == null && uri != null) {
    final reader = readRemote;
    if (reader == null) {
      bytes = await _readRemote(uri, maxBytes: maxBytes);
    } else {
      bytes = await reader(uri);
    }
  }
  if (bytes == null || bytes.isEmpty) {
    throw const DocumentConversionFailure(
      DocumentConversionFailureCode.missingSource,
      'No usable document source was found.',
    );
  }
  if (bytes.length > maxBytes) {
    throw const DocumentConversionFailure(
      DocumentConversionFailureCode.invalidSource,
      'The document is too large to preview.',
    );
  }
  return ResolvedDocumentSource(bytes: bytes, extension: extension);
}

Uri? validDocumentRemoteUri(String? value) {
  final normalized = value?.trim();
  if (normalized == null ||
      normalized.isEmpty ||
      normalized != value ||
      normalized.codeUnits.any((code) => code <= 0x20 || code == 0x7f)) {
    return null;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
}

Future<Uint8List?> _readRemote(Uri uri, {required int maxBytes}) async {
  final client = http.Client();
  try {
    final response = await client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > maxBytes) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (builder.length + chunk.length > maxBytes) return null;
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    return bytes.isEmpty ? null : Uint8List.fromList(bytes);
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}
