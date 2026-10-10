import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:varian/features/link_card/data/link_preview_service.dart';

void main() {
  test('fetches bounded HTML metadata', () async {
    final service = LinkPreviewService(
      client: MockClient(
        (request) async => http.Response(
          '<meta property="og:title" content="Example">',
          200,
          headers: {'content-type': 'text/html'},
          request: request,
        ),
      ),
      ensureDestination: (_) async {},
    );

    final result = await service.fetch('https://example.com');

    expect(result.title, 'Example');
  });

  test('parses metadata from oversized HTML prefix', () async {
    final service = LinkPreviewService(
      maxBodyBytes: 80,
      client: MockClient(
        (request) async => http.Response(
          '<meta property="og:title" content="YouTube">${'x' * 500}',
          200,
          headers: {'content-type': 'text/html'},
          request: request,
        ),
      ),
      ensureDestination: (_) async {},
    );

    final result = await service.fetch('https://www.youtube.com/watch?v=abc');

    expect(result.title, 'YouTube');
  });

  test('supports direct image and PDF links', () async {
    final imageService = LinkPreviewService(
      client: MockClient(
        (request) async => http.Response(
          'image-bytes',
          200,
          headers: {'content-type': 'image/png'},
          request: request,
        ),
      ),
      ensureDestination: (_) async {},
    );
    final image = await imageService.fetch('https://cdn.example.com/photo.png');
    expect(image.mediaType.name, 'image');
    expect(image.imageUri.toString(), 'https://cdn.example.com/photo.png');

    final pdfService = LinkPreviewService(
      client: MockClient(
        (request) async => http.Response(
          'pdf-bytes',
          200,
          headers: {'content-type': 'application/pdf'},
          request: request,
        ),
      ),
      ensureDestination: (_) async {},
    );
    final pdf = await pdfService.fetch('https://example.com/file.pdf');
    expect(pdf.mediaType.name, 'pdf');
  });

  test('supports unknown file responses', () async {
    final service = LinkPreviewService(
      client: MockClient(
        (request) async => http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
      ensureDestination: (_) async {},
    );

    final result = await service.fetch('https://example.com/data');
    expect(result.mediaType.name, 'file');
  });

  test('builds an Edge Function URL for a remote image asset', () {
    expect(
      LinkPreviewProxy.assetUriFor(
        'https://project.supabase.co',
        Uri.parse('https://i.pinimg.com/736x/reference.jpg'),
      ).toString(),
      'https://project.supabase.co/functions/v1/link-preview?asset=https%3A%2F%2Fi.pinimg.com%2F736x%2Freference.jpg',
    );
  });

  test('builds the Supabase Edge Function endpoint', () {
    expect(
      LinkPreviewProxy.endpointFor('https://project.supabase.co').toString(),
      'https://project.supabase.co/functions/v1/link-preview',
    );
    expect(LinkPreviewProxy.endpointFor('not-a-url'), isNull);
  });

  test('normalizes persisted legacy asset URLs', () {
    expect(
      normalizeLinkPreviewAssetUri(
        'http://project.supabase.co/link-preview?asset=abc',
      ).toString(),
      'https://project.supabase.co/functions/v1/link-preview?asset=abc',
    );
  });

  test('normalizes legacy HTTP asset URLs from the Edge Function', () async {
    const source = 'https://cdn.example.com/reference.jpg';
    final proxy = LinkPreviewProxy(
      endpoint: Uri.parse(
        'https://project.supabase.co/functions/v1/link-preview',
      ),
      anonKey: 'anon',
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'url': source,
            'finalUrl': source,
            'mediaType': 'image',
            'title': 'image.jpg',
            'siteName': 'i.pinimg.com',
            'imageUrl': 'http://project.supabase.co/link-preview?asset=abc',
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );

    final result = await proxy.fetch(source);

    expect(
      result.imageUri.toString(),
      'https://project.supabase.co/functions/v1/link-preview?asset=abc',
    );
  });

  test('fetches metadata and proxied assets through the Edge Function', () async {
    const source = 'https://cdn.example.com/reference.jpg';
    final proxy = LinkPreviewProxy(
      endpoint: Uri.parse(
        'https://project.supabase.co/functions/v1/link-preview',
      ),
      anonKey: 'anon',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.headers['apikey'], 'anon');
        expect(request.headers['authorization'], ['Bearer', 'anon'].join(' '));
        expect(jsonDecode(request.body), {'url': source});
        return http.Response(
          jsonEncode({
            'url': source,
            'finalUrl': source,
            'mediaType': 'image',
            'title': 'reference.jpg',
            'siteName': 'i.pinimg.com',
            'imageUrl':
                'https://project.supabase.co/functions/v1/link-preview?asset=abc',
            'faviconUrl':
                'https://project.supabase.co/functions/v1/link-preview?asset=favicon',
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );

    final result = await proxy.fetch(source);

    expect(result.mediaType.name, 'image');
    expect(result.imageUri.toString(), contains('asset=abc'));
    expect(result.faviconUri.toString(), contains('asset=favicon'));
  });
}
