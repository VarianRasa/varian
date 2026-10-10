import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/media/transient_video_bytes_source.dart';

void main() {
  test('returns null for empty byte payloads', () async {
    expect(
      await materializeTransientVideoBytes(Uint8List(0), mimeType: 'video/mp4'),
      isNull,
    );
  });

  test('mime helper preserves supported video extensions', () {
    expect(transientVideoMimeType('clip.mp4'), 'video/mp4');
    expect(transientVideoMimeType('clip.webm'), 'video/webm');
    expect(transientVideoMimeType('clip.mov'), 'video/quicktime');
    expect(
      transientVideoMimeType('clip.m3u8'),
      'application/vnd.apple.mpegurl',
    );
  });

  test('mime helper ignores query and fragment values', () {
    expect(
      transientVideoMimeType('https://example.test/clip.webm?token=redacted#x'),
      'video/webm',
    );
  });
}
