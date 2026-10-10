import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

class VideoThumbnailService {
  Future<String?> createLocalThumbnail(String source) async {
    if (!Platform.isWindows || source.trim().isEmpty) return null;
    final player = Player();
    try {
      await player.open(Media(source), play: false);
      final bytes = await player.screenshot();
      if (bytes == null || bytes.isEmpty) return null;
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}video-thumb-${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }
}
