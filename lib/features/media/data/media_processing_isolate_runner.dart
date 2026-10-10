import 'dart:async';
import 'dart:typed_data';
import 'dart:isolate';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as image;
import 'package:varian/domain/models/media_timeline.dart';

import 'waveform_decoder.dart';

class MediaProcessingIsolateRunner {
  final bool enabled;

  const MediaProcessingIsolateRunner({this.enabled = true});

  Future<List<double>?> decodeWaveform(
    Uint8List sourceBytes, {
    required int sampleCount,
    bool Function()? isCancelled,
  }) {
    final message = <String, Object?>{
      'bytes': sourceBytes,
      'sampleCount': sampleCount,
    };
    if (!enabled) {
      if (isCancelled?.call() == true) return Future.value(null);
      return Future.value(_decodeWaveform(message));
    }
    if (isCancelled != null) {
      return _runCancellable<List<double>>(
        task: 'waveform',
        payload: message,
        isCancelled: isCancelled,
        debugLabel: 'varian-media-waveform',
      );
    }
    return compute(
      _decodeWaveform,
      message,
      debugLabel: 'varian-media-waveform',
    );
  }

  Future<List<double>?> decodeCompressedWaveform(
    Uint8List sourceBytes, {
    required int sampleCount,
    required String formatHint,
  }) async {
    final targetCount = sampleCount.clamp(16, 2048).toInt();
    try {
      final samples = await AudioDecoder.getWaveformBytes(
        sourceBytes,
        formatHint: formatHint,
        numberOfSamples: targetCount,
      );
      return _normalizeWaveform(samples, targetCount);
    } on Object {
      return null;
    }
  }

  Future<Uint8List?> trimAudio(
    Uint8List sourceBytes, {
    required String formatHint,
    required int startMs,
    required int endMs,
    String outputFormat = 'wav',
  }) async {
    if (startMs < 0 || endMs <= startMs) return null;
    try {
      final trimmed = await AudioDecoder.trimAudioBytes(
        sourceBytes,
        formatHint: formatHint,
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: endMs),
        outputFormat: outputFormat == 'm4a' ? 'm4a' : 'wav',
      );
      return trimmed.isEmpty ? null : trimmed;
    } on Object {
      return null;
    }
  }

  Future<Uint8List?> transcodeAudio(
    Uint8List sourceBytes, {
    required String formatHint,
    String outputFormat = 'wav',
  }) async {
    try {
      final transcoded = outputFormat == 'm4a'
          ? await AudioDecoder.convertToM4aBytes(
              sourceBytes,
              formatHint: formatHint,
            )
          : await AudioDecoder.convertToWavBytes(
              sourceBytes,
              formatHint: formatHint,
            );
      return transcoded.isEmpty ? null : transcoded;
    } on Object {
      return null;
    }
  }

  Future<Uint8List?> concatenateAudio(
    Uint8List sourceBytes, {
    required String formatHint,
    required List<MediaClip> clips,
    String outputFormat = 'wav',
  }) async {
    final enabledClips = clips
        .where((clip) => clip.enabled && clip.durationMs > 0)
        .toList(growable: false);
    if (enabledClips.isEmpty) return null;

    final trimmed = <Uint8List>[];
    for (final clip in enabledClips) {
      final bytes = await trimAudio(
        sourceBytes,
        formatHint: formatHint,
        startMs: clip.startMs,
        endMs: clip.endMs,
        outputFormat: 'wav',
      );
      if (bytes == null) return null;
      trimmed.add(bytes);
    }

    final wav = await concatenatePcmWav(trimmed);
    if (wav == null) return null;
    if (outputFormat == 'm4a') {
      return transcodeAudio(wav, formatHint: 'wav', outputFormat: 'm4a');
    }
    return wav;
  }

  Future<Uint8List?> concatenatePcmWav(List<Uint8List> chunks) {
    final message = <String, Object?>{'chunks': chunks};
    if (!enabled) return Future.value(_concatenatePcmWav(message));
    return compute(
      _concatenatePcmWav,
      message,
      debugLabel: 'varian-media-wav-concat',
    );
  }

  Future<Uint8List?> rasterizeImage(
    Uint8List sourceBytes, {
    required int maxDimension,
    required String outputFormat,
    bool Function()? isCancelled,
  }) {
    final message = <String, Object?>{
      'bytes': sourceBytes,
      'maxDimension': maxDimension,
      'outputFormat': outputFormat,
    };
    if (!enabled) {
      if (isCancelled?.call() == true) return Future.value(null);
      return Future.value(_rasterizeImage(message));
    }
    if (isCancelled != null) {
      return _runCancellable<Uint8List>(
        task: 'raster',
        payload: message,
        isCancelled: isCancelled,
        debugLabel: 'varian-media-raster',
      );
    }
    return compute(_rasterizeImage, message, debugLabel: 'varian-media-raster');
  }
}

Future<T?> _runCancellable<T>({
  required String task,
  required Map<String, Object?> payload,
  required bool Function() isCancelled,
  required String debugLabel,
}) async {
  if (isCancelled()) return null;

  final resultPort = ReceivePort();
  final errorPort = ReceivePort();
  final exitPort = ReceivePort();
  final completer = Completer<Object?>();
  Isolate? isolate;
  Timer? cancellationTimer;

  void complete(Object? value) {
    if (completer.isCompleted) return;
    completer.complete(value);
  }

  resultPort.listen((message) {
    if (message is! Map) {
      complete(null);
      return;
    }
    if (message['ok'] == true) {
      complete(message['value']);
      return;
    }
    complete(
      StateError(message['error']?.toString() ?? 'Media worker failed.'),
    );
  });
  errorPort.listen((message) {
    final details = message is List && message.isNotEmpty
        ? message.first.toString()
        : message.toString();
    complete(StateError('Media worker error: $details'));
  });
  exitPort.listen((_) => complete(null));

  try {
    isolate = await Isolate.spawn<Map<String, Object?>>(
      _cancellableMediaWorkerEntry,
      <String, Object?>{
        'sendPort': resultPort.sendPort,
        'task': task,
        'payload': payload,
      },
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
      debugName: debugLabel,
    );
    cancellationTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!isCancelled()) return;
      isolate?.kill(priority: Isolate.immediate);
      complete(null);
    });
    final result = await completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        isolate?.kill(priority: Isolate.immediate);
        return null;
      },
    );
    if (result is StateError) throw result;
    if (isCancelled()) return null;
    return result as T?;
  } finally {
    cancellationTimer?.cancel();
    isolate?.kill(priority: Isolate.immediate);
    resultPort.close();
    errorPort.close();
    exitPort.close();
  }
}

void _cancellableMediaWorkerEntry(Map<String, Object?> message) {
  final sendPort = message['sendPort'];
  final task = message['task'];
  final payload = message['payload'];
  if (sendPort is! SendPort || task is! String || payload is! Map) return;
  try {
    final normalized = Map<String, Object?>.from(payload);
    final value = switch (task) {
      'waveform' => _decodeWaveform(normalized),
      'raster' => _rasterizeImage(normalized),
      _ => throw ArgumentError('Unknown media worker task: $task'),
    };
    sendPort.send({'ok': true, 'value': value});
  } catch (error, stackTrace) {
    sendPort.send({'ok': false, 'error': '$error\n$stackTrace'});
  }
}

List<double>? _decodeWaveform(Map<String, Object?> message) {
  final bytes = _readBytes(message['bytes']);
  final sampleCount = message['sampleCount'];
  if (bytes == null || sampleCount is! int) return null;
  return decodePcmWaveform(bytes, sampleCount: sampleCount);
}

Uint8List? _rasterizeImage(Map<String, Object?> message) {
  final sourceBytes = _readBytes(message['bytes']);
  final maxDimension = message['maxDimension'];
  final outputFormat = message['outputFormat'];
  if (sourceBytes == null || maxDimension is! int || outputFormat is! String) {
    return null;
  }

  final decoded = image.decodeImage(sourceBytes);
  if (decoded == null) return null;
  final longestSide = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  final resized = longestSide > maxDimension
      ? image.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxDimension : null,
          height: decoded.height > decoded.width ? maxDimension : null,
          interpolation: image.Interpolation.average,
        )
      : decoded;
  return switch (outputFormat) {
    'jpg' => Uint8List.fromList(image.encodeJpg(resized, quality: 88)),
    'webp' => Uint8List.fromList(image.encodeWebP(resized)),
    _ => Uint8List.fromList(image.encodePng(resized)),
  };
}

Uint8List? _concatenatePcmWav(Map<String, Object?> message) {
  final rawChunks = message['chunks'];
  if (rawChunks is! List) return null;

  final chunks = <_PcmWav>[];
  for (final rawChunk in rawChunks) {
    final bytes = _readBytes(rawChunk);
    if (bytes == null) return null;
    final parsed = _parsePcmWav(bytes);
    if (parsed == null || parsed.data.isEmpty) return null;
    chunks.add(parsed);
  }
  if (chunks.isEmpty) return null;

  final reference = chunks.first;
  if (chunks.skip(1).any((chunk) => !chunk.hasSameFormat(reference))) {
    return null;
  }

  final dataSize = chunks.fold<int>(
    0,
    (total, chunk) => total + chunk.data.length,
  );
  if (dataSize > 0xffffffff - 36) return null;
  final output = ByteData(44 + dataSize);
  final bytes = output.buffer.asUint8List();
  bytes.setRange(0, 4, const [0x52, 0x49, 0x46, 0x46]);
  output.setUint32(4, 36 + dataSize, Endian.little);
  bytes.setRange(8, 12, const [0x57, 0x41, 0x56, 0x45]);
  bytes.setRange(12, 16, const [0x66, 0x6d, 0x74, 0x20]);
  output.setUint32(16, 16, Endian.little);
  output.setUint16(20, 1, Endian.little);
  output.setUint16(22, reference.channels, Endian.little);
  output.setUint32(24, reference.sampleRate, Endian.little);
  output.setUint32(28, reference.byteRate, Endian.little);
  output.setUint16(32, reference.blockAlign, Endian.little);
  output.setUint16(34, reference.bitsPerSample, Endian.little);
  bytes.setRange(36, 40, const [0x64, 0x61, 0x74, 0x61]);
  output.setUint32(40, dataSize, Endian.little);

  var offset = 44;
  for (final chunk in chunks) {
    bytes.setRange(offset, offset + chunk.data.length, chunk.data);
    offset += chunk.data.length;
  }
  return bytes;
}

_PcmWav? _parsePcmWav(Uint8List bytes) {
  if (bytes.length < 12 ||
      !_hasAscii(bytes, 0, 'RIFF') ||
      !_hasAscii(bytes, 8, 'WAVE')) {
    return null;
  }

  int? audioFormat;
  int? channels;
  int? sampleRate;
  int? byteRate;
  int? blockAlign;
  int? bitsPerSample;
  final dataChunks = <Uint8List>[];
  final view = ByteData.sublistView(bytes);
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkSize = view.getUint32(offset + 4, Endian.little);
    final payloadStart = offset + 8;
    final payloadEnd = payloadStart + chunkSize;
    if (payloadEnd > bytes.length) return null;

    if (_hasAscii(bytes, offset, 'fmt ')) {
      if (chunkSize < 16 || audioFormat != null) return null;
      audioFormat = view.getUint16(payloadStart, Endian.little);
      channels = view.getUint16(payloadStart + 2, Endian.little);
      sampleRate = view.getUint32(payloadStart + 4, Endian.little);
      byteRate = view.getUint32(payloadStart + 8, Endian.little);
      blockAlign = view.getUint16(payloadStart + 12, Endian.little);
      bitsPerSample = view.getUint16(payloadStart + 14, Endian.little);
    } else if (_hasAscii(bytes, offset, 'data')) {
      dataChunks.add(
        Uint8List.fromList(bytes.sublist(payloadStart, payloadEnd)),
      );
    }

    offset = payloadEnd + (chunkSize.isOdd ? 1 : 0);
    if (offset > bytes.length) return null;
  }

  if (audioFormat != 1 ||
      channels == null ||
      channels <= 0 ||
      sampleRate == null ||
      sampleRate <= 0 ||
      byteRate == null ||
      byteRate <= 0 ||
      blockAlign == null ||
      blockAlign <= 0 ||
      bitsPerSample == null ||
      !const [8, 16, 24, 32].contains(bitsPerSample)) {
    return null;
  }
  final expectedBlockAlign = channels * ((bitsPerSample + 7) ~/ 8);
  if (blockAlign != expectedBlockAlign || byteRate != sampleRate * blockAlign) {
    return null;
  }

  final dataSize = dataChunks.fold<int>(
    0,
    (total, chunk) => total + chunk.length,
  );
  if (dataSize == 0 || dataSize % blockAlign != 0) return null;
  final data = Uint8List(dataSize);
  offset = 0;
  for (final chunk in dataChunks) {
    data.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return _PcmWav(
    channels: channels,
    sampleRate: sampleRate,
    byteRate: byteRate,
    blockAlign: blockAlign,
    bitsPerSample: bitsPerSample,
    data: data,
  );
}

bool _hasAscii(Uint8List bytes, int offset, String value) {
  if (offset < 0 || offset + value.length > bytes.length) return false;
  for (var index = 0; index < value.length; index++) {
    if (bytes[offset + index] != value.codeUnitAt(index)) return false;
  }
  return true;
}

final class _PcmWav {
  final int channels;
  final int sampleRate;
  final int byteRate;
  final int blockAlign;
  final int bitsPerSample;
  final Uint8List data;

  const _PcmWav({
    required this.channels,
    required this.sampleRate,
    required this.byteRate,
    required this.blockAlign,
    required this.bitsPerSample,
    required this.data,
  });

  bool hasSameFormat(_PcmWav other) =>
      channels == other.channels &&
      sampleRate == other.sampleRate &&
      byteRate == other.byteRate &&
      blockAlign == other.blockAlign &&
      bitsPerSample == other.bitsPerSample;
}

List<double>? _normalizeWaveform(List<double> samples, int targetCount) {
  if (samples.isEmpty) return null;
  final sanitized = samples
      .map(
        (sample) => sample.isFinite ? sample.clamp(0.0, 1.0).toDouble() : 0.0,
      )
      .toList(growable: false);
  if (sanitized.length == targetCount) return sanitized;
  if (targetCount == 1) return [sanitized.first];
  return List<double>.generate(targetCount, (index) {
    final position = index * (sanitized.length - 1) / (targetCount - 1);
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sanitized[lower];
    final fraction = position - lower;
    return sanitized[lower] * (1 - fraction) + sanitized[upper] * fraction;
  }, growable: false);
}

Uint8List? _readBytes(Object? value) {
  if (value is Uint8List) return value;
  if (value is List<int>) return Uint8List.fromList(value);
  return null;
}
