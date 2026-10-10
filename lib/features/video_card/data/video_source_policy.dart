import 'package:flutter/foundation.dart';

import 'video_source_policy_io.dart'
    if (dart.library.html) 'video_source_policy_web.dart'
    if (dart.library.io) 'video_source_policy_io.dart'
    as platform;

class VideoSourceValidation {
  final bool isValid;
  final String? error;
  final bool isNetwork;

  const VideoSourceValidation._({
    required this.isValid,
    required this.isNetwork,
    this.error,
  });

  const VideoSourceValidation.valid({required bool isNetwork})
    : this._(isValid: true, isNetwork: isNetwork);

  const VideoSourceValidation.invalid(String message)
    : this._(isValid: false, isNetwork: false, error: message);
}

class VideoSourcePolicy {
  static VideoSourceValidation validate({String? path, String? url}) {
    final candidate = (url ?? path)?.trim();
    if (candidate == null || candidate.isEmpty) {
      return const VideoSourceValidation.invalid('Video source is missing.');
    }

    if (url != null || _looksLikeNetwork(candidate)) {
      if (!_isAllowedNetworkUrl(candidate)) {
        return const VideoSourceValidation.invalid(
          'Video URL is invalid or unsupported.',
        );
      }
      return const VideoSourceValidation.valid(isNetwork: true);
    }

    if (kIsWeb) {
      return const VideoSourceValidation.invalid(
        'Web playback requires a video URL.',
      );
    }
    if (candidate.contains('\u0000')) {
      return const VideoSourceValidation.invalid('Video path is invalid.');
    }
    return const VideoSourceValidation.valid(isNetwork: false);
  }

  static bool _looksLikeNetwork(String value) =>
      value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('blob:') ||
      value.startsWith('data:');

  static bool _isAllowedNetworkUrl(String value) {
    if (value.startsWith('blob:') || value.startsWith('data:')) return true;
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    if (uri.userInfo.isNotEmpty || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host == '::1' || host == '127.0.0.1') {
      return false;
    }
    return platform.isPublicVideoHost(host);
  }
}
