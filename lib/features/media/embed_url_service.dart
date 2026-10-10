import 'package:varian/features/link_card/domain/link_url_policy.dart';

enum EmbedProvider { youtube, vimeo, spotify, googleMaps, figma, website }

class EmbedUrlInfo {
  final EmbedProvider provider;
  final Uri url;
  final Uri launchUrl;

  const EmbedUrlInfo({
    required this.provider,
    required this.url,
    required this.launchUrl,
  });

  String get providerLabel => switch (provider) {
    EmbedProvider.youtube => 'YouTube',
    EmbedProvider.vimeo => 'Vimeo',
    EmbedProvider.spotify => 'Spotify',
    EmbedProvider.googleMaps => 'Google Maps',
    EmbedProvider.figma => 'Figma',
    EmbedProvider.website => 'Website',
  };
}

EmbedUrlInfo parseEmbedUrl(String input) {
  final url = normalizeLinkUrl(input);
  final host = url.host.toLowerCase().replaceFirst(RegExp(r'^www\\.'), '');
  if (host == 'youtube.com' || host == 'youtu.be') {
    return EmbedUrlInfo(
      provider: EmbedProvider.youtube,
      url: url,
      launchUrl: _youtubeEmbed(url),
    );
  }
  if (host == 'vimeo.com' || host == 'player.vimeo.com') {
    return EmbedUrlInfo(
      provider: EmbedProvider.vimeo,
      url: url,
      launchUrl: _vimeoEmbed(url),
    );
  }
  if (host == 'open.spotify.com') {
    return EmbedUrlInfo(
      provider: EmbedProvider.spotify,
      url: url,
      launchUrl: _spotifyEmbed(url),
    );
  }
  if (host == 'google.com' && url.path.startsWith('/maps') ||
      host == 'maps.google.com') {
    return EmbedUrlInfo(
      provider: EmbedProvider.googleMaps,
      url: url,
      launchUrl: url,
    );
  }
  if (host == 'figma.com' || host == 'www.figma.com') {
    return EmbedUrlInfo(
      provider: EmbedProvider.figma,
      url: url,
      launchUrl: Uri.parse(
        'https://www.figma.com/embed?embed_host=share&url=${Uri.encodeComponent(url.toString())}',
      ),
    );
  }
  return EmbedUrlInfo(
    provider: EmbedProvider.website,
    url: url,
    launchUrl: url,
  );
}

Uri _youtubeEmbed(Uri url) {
  String? id = url.host.contains('youtu.be')
      ? url.pathSegments.firstOrNull
      : url.queryParameters['v'];
  if (id == null &&
      url.pathSegments.length >= 2 &&
      url.pathSegments.first == 'embed') {
    id = url.pathSegments[1];
  }
  return id == null ? url : Uri.parse('https://www.youtube.com/embed/$id');
}

Uri _vimeoEmbed(Uri url) {
  final id = url.pathSegments
      .where((part) => int.tryParse(part) != null)
      .lastOrNull;
  return id == null ? url : Uri.parse('https://player.vimeo.com/video/$id');
}

Uri _spotifyEmbed(Uri url) {
  final segments = url.pathSegments;
  return segments.length >= 2
      ? Uri.parse(
          'https://open.spotify.com/embed/${segments[0]}/${segments[1]}',
        )
      : url;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}
