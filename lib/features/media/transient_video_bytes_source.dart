export 'transient_video_bytes_source_stub.dart'
    if (dart.library.io) 'transient_video_bytes_source_io.dart'
    if (dart.library.js_interop) 'transient_video_bytes_source_web.dart';

String transientVideoMimeType(String? source) {
  final raw = source?.split('?').first.split('#').first ?? '';
  final slash = raw.lastIndexOf('/');
  final dot = raw.lastIndexOf('.');
  final extension = dot > slash && dot + 1 < raw.length
      ? raw.substring(dot + 1).toLowerCase()
      : '';
  return switch (extension) {
    'm3u8' => 'application/vnd.apple.mpegurl',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    _ => 'video/mp4',
  };
}

bool transientVideoSourceIsUrl(String source) {
  final scheme = Uri.tryParse(source)?.scheme.toLowerCase();
  return scheme == 'http' ||
      scheme == 'https' ||
      scheme == 'blob' ||
      scheme == 'data';
}
