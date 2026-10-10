import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/media_timeline.dart';

void main() {
  test('normalizes duration, waveform, markers, and subtitle cues', () {
    final timeline = const MediaTimeline(
      sourceDurationMs: 10_000,
      waveformSamples: [-1, 0.25, 2, double.nan],
      markers: [MediaMarker(id: 'm', positionMs: 20_000)],
      subtitleTracks: [
        MediaSubtitleTrack(
          id: 'en',
          cues: [
            MediaSubtitleCue(
              id: 'c',
              startMs: -100,
              endMs: 5_000,
              text: 'Hello',
            ),
          ],
        ),
      ],
    ).normalized();

    expect(timeline.waveformSamples, [0.0, 0.25, 1.0]);
    expect(timeline.markers.single.positionMs, 10_000);
    expect(timeline.subtitleTracks.single.cues.single.startMs, 0);
  });

  test('trim and split preserve non-destructive clip ranges', () {
    final timeline = const MediaTimeline(
      sourceDurationMs: 12_000,
    ).trim(startMs: 1_000, endMs: 10_000).splitAt(3_000);

    expect(timeline.durationMs, 9_000);
    expect(timeline.normalizedClips, hasLength(2));
    expect(timeline.normalizedClips.first.startMs, 1_000);
    expect(timeline.normalizedClips.first.endMs, 4_000);
    expect(timeline.normalizedClips.last.startMs, 4_000);
    expect(timeline.normalizedClips.last.endMs, 10_000);
  });

  test('round trips timeline and durable artifact manifest', () {
    const original = MediaTimeline(
      sourceDurationMs: 8_000,
      clips: [MediaClip(id: 'a', startMs: 500, endMs: 7_000)],
      posterPositionMs: 2_000,
      playbackSpeed: 1.5,
      volume: 0.6,
      muted: true,
      artifacts: MediaArtifactManifest(
        items: [
          MediaArtifact(
            kind: MediaArtifactKind.proxy,
            reference: 'varian-media://cache/sha256-proxy/proxy',
            checksum: 'sha256:proxy',
          ),
        ],
      ),
    );

    final restored = MediaTimeline.fromJson(original.toJson());

    expect(restored.sourceDurationMs, 8_000);
    expect(restored.normalizedClips.single.startMs, 500);
    expect(restored.posterPositionMs, 2_000);
    expect(restored.playbackSpeed, 1.5);
    expect(restored.volume, 0.6);
    expect(restored.muted, isTrue);
    expect(restored.hasProxy, isTrue);
    expect(
      restored.artifacts.find(MediaArtifactKind.proxy)!.reference,
      'varian-media://cache/sha256-proxy/proxy',
    );
  });

  test('drops runtime artifact paths, signed URLs, and unsafe references', () {
    final json = <String, dynamic>{
      'kind': 'proxy',
      'path': r'C:\runtime\proxy.mp4',
      'url': 'https://storage.example/proxy.mp4?token=secret',
      'reference': 'blob:https://example.test/runtime',
      'mimeType': 'video/mp4',
      'sizeBytes': 42,
      'checksum': 'sha256:proxy',
    };

    final artifact = MediaArtifact.fromJson(json);
    final encoded = artifact.toJson();

    expect(artifact.path, isNull);
    expect(artifact.url, isNull);
    expect(artifact.reference, isNull);
    expect(encoded, isNot(contains('path')));
    expect(encoded, isNot(contains('url')));
    expect(encoded.toString(), isNot(contains('token=secret')));
  });

  test('migrates the legacy logical url reference without exposing it', () {
    final artifact = MediaArtifact.fromJson({
      'kind': 'proxy',
      'url': 'varian-media://cache/checksum/proxy',
      'mimeType': 'video/mp4',
    });

    expect(artifact.reference, 'varian-media://cache/checksum/proxy');
    expect(artifact.url, isNull);
    expect(
      artifact.toJson()['reference'],
      'varian-media://cache/checksum/proxy',
    );
  });

  test('parses and formats media durations', () {
    expect(parseMediaDurationMs('01:02.5'), 62_500);
    expect(parseMediaDurationMs('1:02:03'), 3_723_000);
    expect(formatMediaDurationMs(3_723_000), '01:02:03');
  });
}
