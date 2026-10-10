import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/link_card/data/link_preview_parser.dart';

void main() {
  test('parses Open Graph fields and relative assets', () {
    final result = parseLinkPreviewHtml(
      html: '''
        <html><head>
          <meta content="OG &amp; Title" property="og:title">
          <meta name='description' content='Fallback description'>
          <meta property='og:description' content='OG description'>
          <meta property='og:image' content='/preview.jpg'>
          <meta property='og:site_name' content='Example Site'>
          <link href="icons/site.png" rel="icon">
        </head></html>
      ''',
      finalUri: Uri.parse('https://example.com/articles/1'),
    );

    expect(result.title, 'OG & Title');
    expect(result.description, 'OG description');
    expect(result.siteName, 'Example Site');
    expect(result.imageUri.toString(), 'https://example.com/preview.jpg');
    expect(
      result.faviconUri.toString(),
      'https://example.com/articles/icons/site.png',
    );
  });

  test('falls back to title, twitter image, hostname, and favicon', () {
    final result = parseLinkPreviewHtml(
      html: '''
        <html><head>
          <base href="https://cdn.example.com/assets/">
          <title>Page &#38; Docs</title>
          <meta name="twitter:image" content="card.png">
        </head></html>
      ''',
      finalUri: Uri.parse('https://example.com/page'),
    );

    expect(result.title, 'Page & Docs');
    expect(result.siteName, 'example.com');
    expect(
      result.imageUri.toString(),
      'https://cdn.example.com/assets/card.png',
    );
    expect(result.faviconUri.toString(), 'https://example.com/favicon.ico');
  });
}
