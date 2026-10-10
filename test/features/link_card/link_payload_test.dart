import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';

void main() {
  test(
    'LinkPayload persists preview metadata and preserves it in copyWith',
    () {
      final payload = LinkPayload(
        title: 'Example',
        url: 'https://example.com/article',
        description: 'Description',
        faviconUrl: 'https://example.com/favicon.ico',
        imageUrl: 'https://cdn.example.com/card.jpg',
        siteName: 'Example Site',
        fetchedAt: DateTime.utc(2026, 8, 20),
        previewStatus: LinkPreviewStatus.ready,
      );

      final restored = LinkPayload.fromJson(payload.toJson());

      expect(restored.title, payload.title);
      expect(restored.url, payload.url);
      expect(restored.description, payload.description);
      expect(restored.faviconUrl, payload.faviconUrl);
      expect(restored.imageUrl, payload.imageUrl);
      expect(restored.siteName, payload.siteName);
      expect(restored.fetchedAt, payload.fetchedAt);
      expect(restored.previewStatus, LinkPreviewStatus.ready);
      expect(restored.copyWith(title: 'Manual').faviconUrl, payload.faviconUrl);
      expect(restored.clone().imageUrl, payload.imageUrl);
    },
  );

  test('LinkPayload loads legacy and interrupted previews as idle', () {
    final legacy = LinkPayload.fromJson({
      'title': 'Legacy',
      'url': 'https://example.com',
    });
    final interrupted = LinkPayload.fromJson({
      'url': 'https://example.com',
      'previewStatus': 'loading',
    });

    expect(legacy.previewStatus, LinkPreviewStatus.idle);
    expect(interrupted.previewStatus, LinkPreviewStatus.idle);
  });

  test('clearPreview keeps new URL and removes fetched fields', () {
    final cleared = LinkPayload(
      title: 'Old',
      url: 'https://old.example',
      description: 'Old description',
      faviconUrl: 'https://old.example/icon',
      imageUrl: 'https://old.example/image',
      siteName: 'Old',
      fetchedAt: DateTime.utc(2026),
      previewStatus: LinkPreviewStatus.ready,
      previewError: 'Old error',
    ).clearPreview(url: 'https://new.example');

    expect(cleared.url, 'https://new.example');
    expect(cleared.title, isEmpty);
    expect(cleared.description, isNull);
    expect(cleared.imageUrl, isNull);
    expect(cleared.previewStatus, LinkPreviewStatus.idle);
    expect(cleared.previewError, isNull);
  });
}
