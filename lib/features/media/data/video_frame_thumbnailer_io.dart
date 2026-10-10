import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:media_kit/media_kit.dart';

Future<Uint8List?> createPlatformVideoFrameThumbnail({
  required String sourceKey,
  Uint8List? sourceBytes,
  String? sourceFileName,
  int positionMs = 0,
  int maxDimension = 320,
}) async {
  if (!Platform.isWindows) return null;

  final source = sourceKey.trim();
  if (source.isEmpty) return null;

  File? temporarySource;
  var playableSource = _playableSource(source);
  if (playableSource == null && sourceBytes != null && sourceBytes.isNotEmpty) {
    final directory = Directory.systemTemp;
    temporarySource = File(
      '${directory.path}${Platform.pathSeparator}varian-video-${DateTime.now().microsecondsSinceEpoch}${_extension(sourceFileName)}',
    );
    await temporarySource.writeAsBytes(sourceBytes, flush: true);
    playableSource = temporarySource.path;
  }
  if (playableSource == null) return null;

  Player? player;
  try {
    MediaKit.ensureInitialized();
    player = Player();
    await player.open(Media(playableSource), play: false);
    if (positionMs > 0) {
      await player.seek(Duration(milliseconds: positionMs));
    }
    final screenshot = await player.screenshot(format: 'image/png');
    if (screenshot == null || screenshot.isEmpty) return null;
    return _resizePng(screenshot, maxDimension);
  } catch (_) {
    return null;
  } finally {
    await player?.dispose();
    if (temporarySource != null) {
      try {
        await temporarySource.delete();
      } catch (_) {}
    }
  }
}

String? _playableSource(String source) {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return source;
  }
  final file = File(source);
  return file.existsSync() && file.lengthSync() > 0 ? source : null;
}

String _extension(String? sourceFileName) {
  final value = sourceFileName?.trim() ?? '';
  final match = RegExp(
    r'\.(mp4|webm|mov|m4v|mkv|avi)$',
    caseSensitive: false,
  ).firstMatch(value);
  return match == null ? '.mp4' : '.${match.group(1)!.toLowerCase()}';
}

Uint8List? _resizePng(Uint8List bytes, int maxDimension) {
  final decoded = image.decodeImage(bytes);
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
  return Uint8List.fromList(image.encodePng(resized));
}

const supportsPlatformVideoFrameThumbnail = true;
