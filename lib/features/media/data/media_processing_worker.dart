import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/features/ai/data/video_artifact_store_types.dart';
import 'media_processing_queue.dart';
import 'media_artifact_store.dart';
import 'media_processing_isolate_runner.dart';
import 'media_source_reader.dart';
import 'media_video_proxy_transcoder.dart';
import 'platform_media_video_proxy_transcoder.dart';
import 'video_frame_thumbnailer.dart';

class DeterministicMediaProcessingWorker {
  final int waveformSampleCount;
  final MediaArtifactStore? artifactStore;
  final MediaArtifactStore? mediaArtifactStore;
  final MediaProcessingIsolateRunner isolateRunner;
  final MediaVideoProxyTranscoder videoProxyTranscoder;
  final VideoArtifactStore? videoArtifactStore;

  const DeterministicMediaProcessingWorker({
    this.waveformSampleCount = 96,
    this.artifactStore,
    this.mediaArtifactStore,
    this.isolateRunner = const MediaProcessingIsolateRunner(),
    this.videoProxyTranscoder = const UnsupportedMediaVideoProxyTranscoder(),
    this.videoArtifactStore,
  });

  Future<MediaProcessingOutput> process(
    MediaProcessingRequest request,
    MediaProcessingCancellationToken cancellation,
  ) async {
    if (request.sourceKey.trim().isEmpty ||
        request.inputChecksum.trim().isEmpty) {
      throw const MediaProcessingException(
        'Media source key and input checksum are required.',
      );
    }
    if (request.artifactKinds.isEmpty) {
      throw const MediaProcessingException(
        'At least one media artifact is required.',
      );
    }

    final requestDigest = _digest(_canonicalRequest(request));
    final sourceBytes = artifactStore == null
        ? null
        : await _readSourceBytes(request, cancellation);
    final artifacts = <MediaArtifact>[];
    final kinds = request.artifactKinds.toSet().toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    for (final kind in kinds) {
      cancellation.throwIfCancelled();
      await Future<void>.delayed(Duration.zero);
      cancellation.throwIfCancelled();
      final logicalChecksum = _digest('$requestDigest|${kind.name}');
      final bytes = await _materializeBytes(
        request: request,
        kind: kind,
        requestDigest: requestDigest,
        sourceBytes: sourceBytes,
        cancellation: cancellation,
      );
      final mimeType = _mimeType(request, kind, bytes: bytes);
      if (artifactStore == null) {
        artifacts.add(
          MediaArtifact(
            kind: kind,
            url: _artifactReference(request, kind, logicalChecksum),
            mimeType: mimeType,
            sizeBytes: _logicalSize(request, kind),
            checksum: logicalChecksum,
          ),
        );
        continue;
      }
      if (bytes == null) {
        throw MediaProcessingException(
          'Source bytes are required to materialize ${kind.name}.',
        );
      }
      final checksum = mediaArtifactChecksum(bytes);
      final saved = await artifactStore!.save(
        bytes,
        kind: kind,
        mimeType: mimeType,
        checksum: checksum,
        fileName: _fileName(request, kind, mimeType),
        storagePolicy: request.storagePolicy,
      );
      artifacts.add(saved);
    }

    final manifest = MediaArtifactManifest(items: List.unmodifiable(artifacts));
    final timeline = await _timelinePatch(
      request,
      requestDigest,
      manifest,
      kinds,
      sourceBytes,
      cancellation,
    );
    final outputChecksum = _digest(
      artifacts
          .map((artifact) => '${artifact.kind.name}:${artifact.checksum}')
          .join('|'),
    );
    return MediaProcessingOutput(
      artifacts: manifest,
      checksum: outputChecksum,
      timeline: timeline,
    );
  }

  String _canonicalRequest(MediaProcessingRequest request) {
    final metadata = request.metadata.keys.toList()..sort();
    final metadataValue = {
      for (final key in metadata) key: request.metadata[key],
    };
    return jsonEncode({
      'sourceKey': request.sourceKey,
      'inputChecksum': request.inputChecksum,
      'artifactKinds': request.artifactKinds.map((kind) => kind.name).toList()
        ..sort(),
      'storagePolicy': request.storagePolicy.name,
      'metadata': metadataValue,
    });
  }

  String _artifactReference(
    MediaProcessingRequest request,
    MediaArtifactKind kind,
    String checksum,
  ) =>
      'varian-media://${request.storagePolicy.name}/${checksum.substring(0, 24)}/${kind.name}';

  String _mimeType(
    MediaProcessingRequest request,
    MediaArtifactKind kind, {
    Uint8List? bytes,
  }) {
    final sourceMime = request.metadata['sourceMimeType']?.trim();
    if (kind == MediaArtifactKind.original && sourceMime?.isNotEmpty == true) {
      return sourceMime!;
    }
    if (kind == MediaArtifactKind.thumbnail) {
      if (_isRasterImage(sourceMime)) return 'image/png';
      if (_isPng(bytes)) return 'image/png';
      return 'image/svg+xml';
    }
    if (kind == MediaArtifactKind.proxy) {
      if (_isWav(bytes)) return 'audio/wav';
      if (_isM4a(bytes)) return 'audio/mp4';
    }
    if (kind == MediaArtifactKind.waveform) return 'application/json';
    if (sourceMime?.isNotEmpty == true) return sourceMime!;
    return 'application/octet-stream';
  }

  int _logicalSize(MediaProcessingRequest request, MediaArtifactKind kind) {
    final declared = int.tryParse(
      request.metadata['${kind.name}SizeBytes'] ?? '',
    );
    if (declared != null && declared > 0) return declared;
    return switch (kind) {
      MediaArtifactKind.original => 1,
      MediaArtifactKind.proxy => 1,
      MediaArtifactKind.thumbnail => 1,
      MediaArtifactKind.waveform => waveformSampleCount * 4,
      MediaArtifactKind.preview => 1,
      MediaArtifactKind.export => 1,
    };
  }

  Future<MediaTimeline?> _timelinePatch(
    MediaProcessingRequest request,
    String requestDigest,
    MediaArtifactManifest manifest,
    List<MediaArtifactKind> kinds,
    Uint8List? sourceBytes,
    MediaProcessingCancellationToken cancellation,
  ) async {
    final rawTimeline = request.metadata['timelineJson'];
    if (rawTimeline == null || rawTimeline.trim().isEmpty) return null;
    try {
      var timeline = MediaTimeline.fromJson(
        Map<String, dynamic>.from(jsonDecode(rawTimeline) as Map),
      );
      if (kinds.contains(MediaArtifactKind.waveform)) {
        timeline = timeline.copyWith(
          waveformSamples: await _waveformForSource(
            request: request,
            requestDigest: requestDigest,
            sourceBytes: sourceBytes,
            cancellation: cancellation,
          ),
        );
      }
      return timeline.copyWith(artifacts: manifest).normalized();
    } on MediaProcessingException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<List<double>> _waveformForSource({
    required MediaProcessingRequest request,
    required String requestDigest,
    required Uint8List? sourceBytes,
    required MediaProcessingCancellationToken cancellation,
  }) async {
    if (sourceBytes != null) {
      final decoded = await isolateRunner.decodeWaveform(
        sourceBytes,
        sampleCount: waveformSampleCount,
        isCancelled: () => cancellation.isCancelled,
      );
      cancellation.throwIfCancelled();
      if (decoded != null) return decoded;

      final formatHint = _audioFormatHint(request: request);
      if (formatHint != null) {
        final compressed = await isolateRunner.decodeCompressedWaveform(
          sourceBytes,
          sampleCount: waveformSampleCount,
          formatHint: formatHint,
        );
        cancellation.throwIfCancelled();
        if (compressed != null) return compressed;
      }
    }
    return _deterministicWaveform(requestDigest);
  }

  String? _audioFormatHint({required MediaProcessingRequest request}) {
    final mimeType = request.metadata['sourceMimeType']
        ?.toLowerCase()
        .split(';')
        .first
        .trim();
    final mimeHint = switch (mimeType) {
      'audio/mpeg' || 'audio/mp3' => 'mp3',
      'audio/aac' || 'audio/aacp' => 'aac',
      'audio/ogg' || 'application/ogg' => 'ogg',
      'audio/mp4' || 'audio/x-m4a' => 'm4a',
      'audio/wav' || 'audio/x-wav' => 'wav',
      'audio/flac' => 'flac',
      'audio/webm' => 'webm',
      'video/mp4' => 'mp4',
      'video/webm' => 'webm',
      'video/quicktime' => 'mov',
      _ => null,
    };
    if (mimeHint != null) return mimeHint;

    final candidates = [request.metadata['sourceFileName'], request.sourceKey];
    for (final candidate in candidates) {
      final value = candidate?.trim().toLowerCase();
      if (value == null || value.isEmpty) continue;
      final withoutQuery = value.split('?').first.split('#').first;
      final dot = withoutQuery.lastIndexOf('.');
      if (dot < 0 || dot == withoutQuery.length - 1) continue;
      final extension = withoutQuery.substring(dot + 1);
      if (extension == 'wav' || extension == 'wave') return 'wav';
      if (const {
        'wav',
        'wave',
        'mp3',
        'aac',
        'ogg',
        'oga',
        'opus',
        'm4a',
        'mp4',
        'flac',
        'webm',
        'mov',
      }.contains(extension)) {
        return extension;
      }
    }
    return null;
  }

  List<double> _deterministicWaveform(String digest) {
    final count = waveformSampleCount.clamp(16, 2048).toInt();
    return List<double>.generate(count, (index) {
      final first = int.parse(digest[(index * 2) % digest.length], radix: 16);
      final second = int.parse(
        digest[(index * 2 + 1) % digest.length],
        radix: 16,
      );
      return ((first * 16) + second) / 255;
    }, growable: false);
  }

  Future<Uint8List?> _readSourceBytes(
    MediaProcessingRequest request,
    MediaProcessingCancellationToken cancellation,
  ) async {
    cancellation.throwIfCancelled();
    final encoded = request.metadata['sourceBytesBase64'];
    if (encoded != null && encoded.trim().isNotEmpty) {
      try {
        final bytes = Uint8List.fromList(base64Decode(encoded.trim()));
        if (bytes.isNotEmpty) return bytes;
      } catch (_) {
        throw const MediaProcessingException(
          'Encoded media source bytes are invalid.',
        );
      }
    }
    final bytes = await readMediaSourceBytes(
      request.sourceKey,
      videoArtifactStore: videoArtifactStore,
      mediaArtifactStore: mediaArtifactStore ?? artifactStore,
    );
    cancellation.throwIfCancelled();
    return bytes;
  }

  Future<Uint8List?> _materializeBytes({
    required MediaProcessingRequest request,
    required MediaArtifactKind kind,
    required String requestDigest,
    required Uint8List? sourceBytes,
    required MediaProcessingCancellationToken cancellation,
  }) async {
    cancellation.throwIfCancelled();
    switch (kind) {
      case MediaArtifactKind.waveform:
        final samples = await _waveformForSource(
          request: request,
          requestDigest: requestDigest,
          sourceBytes: sourceBytes,
          cancellation: cancellation,
        );
        return Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'version': 1,
              'sourceKey': request.sourceKey,
              'samples': samples,
            }),
          ),
        );
      case MediaArtifactKind.thumbnail:
        if (_isVideoSource(request)) {
          final videoFrame = await createVideoFrameThumbnail(
            sourceKey: request.sourceKey,
            sourceBytes: sourceBytes,
            sourceFileName: request.metadata['sourceFileName'],
            positionMs: _posterPositionMs(request),
            maxDimension: 320,
          );
          if (videoFrame != null) return videoFrame;
        }
        final raster = await _materializeRasterImage(
          request: request,
          sourceBytes: sourceBytes,
          maxDimension: 320,
          outputFormat: 'png',
          cancellation: cancellation,
        );
        if (raster != null) return raster;
        return Uint8List.fromList(utf8.encode(_thumbnailSvg(requestDigest)));
      case MediaArtifactKind.original:
      case MediaArtifactKind.export:
        return sourceBytes;
      case MediaArtifactKind.proxy:
        if (_isAudioSource(request)) {
          return _materializeAudioProxy(
            request: request,
            sourceBytes: sourceBytes,
            cancellation: cancellation,
          );
        }
        if (_isVideo(request.metadata['sourceMimeType'])) {
          return _materializeVideoProxy(
            request: request,
            sourceBytes: sourceBytes,
            cancellation: cancellation,
          );
        }
        return await _materializeRasterImage(
              request: request,
              sourceBytes: sourceBytes,
              maxDimension: 1920,
              outputFormat: _rasterFormat(request.metadata['sourceMimeType']),
              cancellation: cancellation,
            ) ??
            sourceBytes;
      case MediaArtifactKind.preview:
        return await _materializeRasterImage(
              request: request,
              sourceBytes: sourceBytes,
              maxDimension: 960,
              outputFormat: _rasterFormat(request.metadata['sourceMimeType']),
              cancellation: cancellation,
            ) ??
            sourceBytes;
    }
  }

  Future<Uint8List?> _materializeAudioProxy({
    required MediaProcessingRequest request,
    required Uint8List? sourceBytes,
    required MediaProcessingCancellationToken cancellation,
  }) async {
    if (sourceBytes == null || !_isAudioSource(request)) return null;
    final formatHint = _audioFormatHint(request: request);
    if (formatHint == null) return null;
    final outputFormat = _proxyOutputFormat(request);
    final clips = _explicitEnabledClips(request);
    cancellation.throwIfCancelled();
    final transformed = clips == null
        ? await isolateRunner.transcodeAudio(
            sourceBytes,
            formatHint: formatHint,
            outputFormat: outputFormat,
          )
        : clips.length == 1
        ? await isolateRunner.trimAudio(
            sourceBytes,
            formatHint: formatHint,
            startMs: clips.single.startMs,
            endMs: clips.single.endMs,
            outputFormat: outputFormat,
          )
        : await isolateRunner.concatenateAudio(
            sourceBytes,
            formatHint: formatHint,
            clips: clips,
            outputFormat: outputFormat,
          );
    cancellation.throwIfCancelled();
    return transformed;
  }

  Future<Uint8List?> _materializeVideoProxy({
    required MediaProcessingRequest request,
    required Uint8List? sourceBytes,
    required MediaProcessingCancellationToken cancellation,
  }) async {
    if (sourceBytes == null) return null;
    final transcoder = videoProxyTranscoder;
    final result = transcoder is CancellableMediaVideoProxyTranscoder
        ? await transcoder.transcodeCancellable(
            sourceKey: request.sourceKey,
            sourceBytes: sourceBytes,
            sourceMimeType: request.metadata['sourceMimeType'],
            sourceFileName: request.metadata['sourceFileName'],
            formatHint: _audioFormatHint(request: request),
            outputFormat:
                request.metadata['proxyFormat']?.trim().toLowerCase() ?? 'mp4',
            clips: _explicitEnabledClips(request) ?? const [],
            isCancelled: () => cancellation.isCancelled,
          )
        : await transcoder.transcode(
            sourceKey: request.sourceKey,
            sourceBytes: sourceBytes,
            sourceMimeType: request.metadata['sourceMimeType'],
            sourceFileName: request.metadata['sourceFileName'],
            formatHint: _audioFormatHint(request: request),
            outputFormat:
                request.metadata['proxyFormat']?.trim().toLowerCase() ?? 'mp4',
            clips: _explicitEnabledClips(request) ?? const [],
          );
    cancellation.throwIfCancelled();
    if (result.status == MediaVideoProxyStatus.unsupported) {
      throw MediaProcessingException(
        result.message ??
            'Video proxy transcoding is unavailable on this platform.',
      );
    }
    if (result.status == MediaVideoProxyStatus.failed) {
      throw MediaProcessingException(
        result.message ?? 'Video proxy transcoding failed.',
      );
    }
    if (!result.isAvailable) {
      throw const MediaProcessingException(
        'Video proxy transcoder returned no encoded bytes.',
      );
    }
    return result.bytes;
  }

  bool _isAudioSource(MediaProcessingRequest request) {
    final mimeType = request.metadata['sourceMimeType']
        ?.toLowerCase()
        .split(';')
        .first
        .trim();
    if (mimeType?.isNotEmpty == true) return mimeType!.startsWith('audio/');
    return const {
      'mp3',
      'aac',
      'ogg',
      'oga',
      'opus',
      'm4a',
      'flac',
      'wma',
      'aiff',
      'aif',
      'amr',
      'caf',
      'alac',
    }.contains(_audioFormatHint(request: request));
  }

  String _proxyOutputFormat(MediaProcessingRequest request) {
    final requested = request.metadata['proxyFormat']?.trim().toLowerCase();
    return requested == 'm4a' ? 'm4a' : 'wav';
  }

  List<MediaClip>? _explicitEnabledClips(MediaProcessingRequest request) {
    final rawTimeline = request.metadata['timelineJson'];
    if (rawTimeline == null || rawTimeline.trim().isEmpty) return null;
    try {
      final timeline = MediaTimeline.fromJson(
        Map<String, dynamic>.from(jsonDecode(rawTimeline) as Map),
      ).normalized();
      if (timeline.clips.isEmpty) return null;
      return timeline.clips
          .where((clip) => clip.enabled && clip.durationMs > 0)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<Uint8List?> _materializeRasterImage({
    required MediaProcessingRequest request,
    required Uint8List? sourceBytes,
    required int maxDimension,
    required String outputFormat,
    required MediaProcessingCancellationToken cancellation,
  }) async {
    cancellation.throwIfCancelled();
    if (sourceBytes == null ||
        !_isRasterImage(request.metadata['sourceMimeType'])) {
      return null;
    }
    final encoded = await isolateRunner.rasterizeImage(
      sourceBytes,
      maxDimension: maxDimension,
      outputFormat: outputFormat,
      isCancelled: () => cancellation.isCancelled,
    );
    cancellation.throwIfCancelled();
    return encoded;
  }

  bool _isRasterImage(String? mimeType) {
    final normalized = mimeType?.toLowerCase().split(';').first.trim();
    return normalized == 'image/png' ||
        normalized == 'image/jpeg' ||
        normalized == 'image/jpg' ||
        normalized == 'image/webp';
  }

  bool _isVideo(String? mimeType) =>
      mimeType?.toLowerCase().split(';').first.trim().startsWith('video/') ==
      true;

  bool _isVideoSource(MediaProcessingRequest request) {
    if (_isVideo(request.metadata['sourceMimeType'])) return true;
    return const {
      'mp4',
      'webm',
      'mov',
      'm4v',
      'mkv',
      'avi',
    }.contains(_audioFormatHint(request: request));
  }

  String _rasterFormat(String? mimeType) {
    final normalized = mimeType?.toLowerCase().split(';').first.trim();
    return switch (normalized) {
      'image/jpeg' || 'image/jpg' => 'jpg',
      'image/webp' => 'webp',
      _ => 'png',
    };
  }

  String _fileName(
    MediaProcessingRequest request,
    MediaArtifactKind kind,
    String mimeType,
  ) => sanitizeMediaArtifactFileName(
    request.metadata['sourceFileName'] ?? kind.name,
    kind: kind,
    mimeType: mimeType,
  );

  int _posterPositionMs(MediaProcessingRequest request) {
    final value = int.tryParse(request.metadata['posterPositionMs'] ?? '');
    return value == null || value.isNegative ? 0 : value;
  }

  bool _isPng(Uint8List? bytes) =>
      bytes != null &&
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a;

  bool _isWav(Uint8List? bytes) =>
      bytes != null &&
      bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45;

  bool _isM4a(Uint8List? bytes) =>
      bytes != null &&
      bytes.length >= 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70;

  String _thumbnailSvg(String digest) {
    final bars = List<String>.generate(24, (index) {
      final value = int.parse(digest[(index * 2) % digest.length], radix: 16);
      final height = 18 + (value * 5);
      final x = 16 + index * 12;
      final y = 100 - height;
      return '<rect x="$x" y="$y" width="7" height="$height" rx="2" fill="#7c3aed"/>';
    }).join();
    return '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="180" viewBox="0 0 320 180">'
        '<rect width="320" height="180" fill="#111827"/>'
        '<text x="16" y="32" fill="#f9fafb" font-family="sans-serif" font-size="16">Media preview</text>'
        '<g>$bars</g>'
        '</svg>';
  }

  String _digest(String value) => sha256.convert(utf8.encode(value)).toString();
}

class MediaProcessingCoordinator {
  final MediaProcessingQueue queue;

  MediaProcessingCoordinator({
    MediaProcessingQueue? queue,
    MediaProcessingHandler? handler,
    MediaArtifactStore? artifactStore,
    MediaProcessingCheckpointStore? checkpointStore,
    MediaVideoProxyTranscoder? videoProxyTranscoder,
    VideoArtifactStore? videoArtifactStore,
    MediaArtifactStore? mediaArtifactStore,
  }) : queue =
           queue ??
           MediaProcessingQueue(
             checkpointStore: checkpointStore,
             handler:
                 handler ??
                 DeterministicMediaProcessingWorker(
                   artifactStore: artifactStore,
                   videoProxyTranscoder:
                       videoProxyTranscoder ??
                       const PlatformMediaVideoProxyTranscoder(),
                   videoArtifactStore: videoArtifactStore,
                   mediaArtifactStore: mediaArtifactStore,
                 ).process,
           );

  MediaProcessingJob? enqueueTimeline({
    required String id,
    required String sourceKey,
    required String inputChecksum,
    required MediaTimeline timeline,
    required List<MediaArtifactKind> artifactKinds,
    MediaStoragePolicy storagePolicy = MediaStoragePolicy.cache,
    int maxAttempts = 2,
    String? expectedOutputChecksum,
    Map<String, String> metadata = const {},
  }) {
    final missing =
        artifactKinds
            .where((kind) => !timeline.artifacts.contains(kind))
            .toSet()
            .toList()
          ..sort((left, right) => left.index.compareTo(right.index));
    if (missing.isEmpty) return null;
    return queue.enqueue(
      MediaProcessingRequest(
        id: id,
        sourceKey: sourceKey,
        inputChecksum: inputChecksum,
        artifactKinds: missing,
        storagePolicy: storagePolicy,
        maxAttempts: maxAttempts,
        expectedOutputChecksum: expectedOutputChecksum,
        metadata: {
          ...metadata,
          'timelineJson': jsonEncode(timeline.toJson()),
          'posterPositionMs': '${timeline.posterPositionMs ?? 0}',
        },
      ),
    );
  }

  MediaTimeline applyOutput(
    MediaTimeline timeline,
    MediaProcessingOutput output,
  ) {
    var manifest = timeline.artifacts;
    for (final artifact in output.artifacts.items) {
      manifest = manifest.upsert(artifact);
    }
    return (output.timeline ?? timeline)
        .copyWith(artifacts: manifest)
        .normalized();
  }

  Future<MediaTimeline> processTimeline({
    required String id,
    required String sourceKey,
    required String inputChecksum,
    required MediaTimeline timeline,
    required List<MediaArtifactKind> artifactKinds,
    MediaStoragePolicy storagePolicy = MediaStoragePolicy.cache,
    int maxAttempts = 2,
    String? expectedOutputChecksum,
    Map<String, String> metadata = const {},
  }) async {
    final job = enqueueTimeline(
      id: id,
      sourceKey: sourceKey,
      inputChecksum: inputChecksum,
      timeline: timeline,
      artifactKinds: artifactKinds,
      storagePolicy: storagePolicy,
      maxAttempts: maxAttempts,
      expectedOutputChecksum: expectedOutputChecksum,
      metadata: metadata,
    );
    if (job == null) return timeline;
    await queue.waitForIdle();
    final completed = queue[job.request.id];
    if (completed?.status != MediaProcessingStatus.succeeded ||
        completed?.output == null) {
      throw MediaProcessingException(
        completed?.error ?? 'Media processing did not complete.',
      );
    }
    return applyOutput(timeline, completed!.output!);
  }

  Future<void> dispose() => queue.dispose();
}
