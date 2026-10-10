import 'package:video_player/video_player.dart' as vp;

const isWindowsVideoPlayback = false;

Future<bool> isNativeVideoFileMissing(String source) async => false;

vp.VideoPlayerController createNativeVideoController(String source) =>
    throw UnsupportedError('Native file playback is unavailable on Web.');
