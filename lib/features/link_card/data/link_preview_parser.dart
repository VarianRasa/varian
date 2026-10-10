enum LinkPreviewMediaType { webpage, image, video, audio, pdf, file }

class LinkPreviewMetadata {
  final Uri finalUri;
  final LinkPreviewMediaType mediaType;
  final String title;
  final String? description;
  final Uri? faviconUri;
  final Uri? imageUri;
  final String siteName;

  const LinkPreviewMetadata({
    required this.finalUri,
    required this.mediaType,
    required this.title,
    required this.siteName,
    this.description,
    this.faviconUri,
    this.imageUri,
  });
}

LinkPreviewMetadata parseLinkPreviewHtml({
  required String html,
  required Uri finalUri,
}) {
  final metas = <String, String>{};
  for (final match in RegExp(
    r'<meta\b[^>]*>',
    caseSensitive: false,
  ).allMatches(html)) {
    final attributes = _attributes(match.group(0)!);
    final key = (attributes['property'] ?? attributes['name'])?.toLowerCase();
    final content = attributes['content'];
    if (key != null && content != null && content.trim().isNotEmpty) {
      metas.putIfAbsent(key, () => _clean(content));
    }
  }
  Uri baseUri = finalUri;
  final baseMatch = RegExp(
    r'<base\b[^>]*>',
    caseSensitive: false,
  ).firstMatch(html);
  final baseHref = baseMatch == null
      ? null
      : _attributes(baseMatch.group(0)!)['href'];
  if (baseHref != null) {
    baseUri = finalUri.resolve(baseHref);
  }
  Uri? resolve(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final resolved = baseUri.resolve(_decode(value.trim()));
    return resolved.scheme == 'http' || resolved.scheme == 'https'
        ? resolved
        : null;
  }

  Uri? favicon;
  for (final match in RegExp(
    r'<link\b[^>]*>',
    caseSensitive: false,
  ).allMatches(html)) {
    final attributes = _attributes(match.group(0)!);
    final rel = attributes['rel']?.toLowerCase().split(RegExp(r'\s+')) ?? [];
    if (rel.any((value) => value == 'icon' || value == 'shortcut icon')) {
      favicon = resolve(attributes['href']);
      if (favicon != null) break;
    }
  }
  favicon ??= finalUri.resolve('/favicon.ico');
  final titleTag = RegExp(
    r'<title\b[^>]*>([\s\S]*?)</title\s*>',
    caseSensitive: false,
  ).firstMatch(html)?.group(1);
  final title = _first([
    metas['og:title'],
    titleTag == null ? null : _clean(titleTag),
    finalUri.host,
  ])!;
  final description = _first([metas['og:description'], metas['description']]);
  final siteName = _first([metas['og:site_name'], finalUri.host])!;

  return LinkPreviewMetadata(
    finalUri: finalUri,
    mediaType: LinkPreviewMediaType.webpage,
    title: title,
    description: description,
    faviconUri: favicon,
    imageUri: resolve(metas['og:image'] ?? metas['twitter:image']),
    siteName: siteName,
  );
}

Map<String, String> _attributes(String tag) {
  final result = <String, String>{};
  final expression = RegExp(
    r'''([:\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
    caseSensitive: false,
  );
  for (final match in expression.allMatches(tag)) {
    result[match.group(1)!.toLowerCase()] =
        match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
  }
  return result;
}

String? _first(List<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String _clean(String value) => _decode(
  value.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' '),
).trim();

String _decode(String value) => value.replaceAllMapped(
  RegExp(r'&(#x[0-9a-f]+|#\d+|amp|quot|apos|lt|gt);', caseSensitive: false),
  (match) {
    final entity = match.group(1)!.toLowerCase();
    if (entity.startsWith('#x')) {
      return String.fromCharCode(int.parse(entity.substring(2), radix: 16));
    }
    if (entity.startsWith('#')) {
      return String.fromCharCode(int.parse(entity.substring(1)));
    }
    return const {
      'amp': '&',
      'quot': '"',
      'apos': "'",
      'lt': '<',
      'gt': '>',
    }[entity]!;
  },
);
