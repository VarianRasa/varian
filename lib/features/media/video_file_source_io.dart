import 'dart:io';

import 'package:video_player/video_player.dart' as vp;

final bool isWindowsVideoPlayback = Platform.isWindows;

Future<bool> isNativeVideoFileMissing(String source) async {
  final file = File(source);
  return !await file.exists() || await file.length() == 0;
}

vp.VideoPlayerController createNativeVideoController(String source) =>
    vp.VideoPlayerController.file(File(source));
