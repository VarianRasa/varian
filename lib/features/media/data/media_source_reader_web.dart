import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:varian/features/ai/data/video_artifact_store.dart';

import 'media_artifact_store.dart';

Future<Uint8List?> readPlatformMediaSourceBytes(
  String sourceKey, {
  required int maxBytes,
  http.Client? httpClient,
  VideoArtifactStore? videoArtifactStore,
  MediaArtifactStore? mediaArtifactStore,
}) async {
  if (maxBytes <= 0) return null;
  final source = sourceKey.trim();
  if (source.isEmpty) return null;
  final dataBytes = _decodeDataUri(source, maxBytes: maxBytes);
  if (dataBytes != null) return dataBytes;
  if (source.startsWith('varian-media://')) {
    final store = mediaArtifactStore ?? createMediaArtifactStore();
    final artifact = await store.hydrate(source);
    if (artifact == null) return null;
    try {
      final bytes = await store.read(artifact);
      return bytes != null && bytes.length <= maxBytes ? bytes : null;
    } finally {
      await store.dispose(artifact);
    }
  }
  if (source.startsWith('varian-video://')) {
    final store = videoArtifactStore ?? createVideoArtifactStore();
    final artifact = await store.hydrate(source);
    if (artifact == null) return null;
    try {
      final bytes = await store.read(artifact);
      return bytes != null && bytes.length <= maxBytes ? bytes : null;
    } finally {
      await store.dispose(artifact);
    }
  }
  if (!source.startsWith('http://') && !source.startsWith('https://')) {
    return null;
  }
  final client = httpClient ?? http.Client();
  try {
    final request = http.Request('GET', Uri.parse(source))
      ..followRedirects = false;
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.isRedirect ||
        response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (response.contentLength != null &&
            response.contentLength! > maxBytes)) {
      return null;
    }
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
    if (httpClient == null) client.close();
  }
}

Uint8List? _decodeDataUri(String source, {required int maxBytes}) {
  if (!source.startsWith('data:')) return null;
  final separator = source.indexOf(',');
  if (separator < 0) return null;
  final header = source.substring(0, separator);
  final payload = source.substring(separator + 1);
  try {
    if (header.toLowerCase().contains(';base64')) {
      if (payload.length > ((maxBytes + 2) ~/ 3) * 4 + 4) return null;
      final bytes = base64Decode(payload);
      return bytes.isEmpty || bytes.length > maxBytes
          ? null
          : Uint8List.fromList(bytes);
    }
    final bytes = utf8.encode(Uri.decodeComponent(payload));
    return bytes.isEmpty || bytes.length > maxBytes
        ? null
        : Uint8List.fromList(bytes);
  } catch (_) {
    return null;
  }
}
