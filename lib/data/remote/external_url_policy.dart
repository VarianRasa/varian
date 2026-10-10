/// Shared policy for untrusted HTTP(S) delivery sources.
///
/// This is intentionally a conservative client-side check. It blocks obvious
/// loopback, link-local, private, and local-name destinations and never treats
/// a query-bearing URL as a public durable source. Server-side URL fetchers
/// must enforce their own DNS-pinned SSRF policy as well.
class ExternalUrlPolicy {
  const ExternalUrlPolicy._();

  static Uri? publicUri(String? value) {
    final normalized = value?.trim();
    if (normalized == null ||
        normalized.isEmpty ||
        normalized != value ||
        normalized.codeUnits.any((code) => code <= 0x20 || code == 0x7f)) {
      return null;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !isSecureHttpUri(uri) ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !_isPublicHost(uri.host)) {
      return null;
    }
    return uri;
  }

  static bool isSecureHttpUri(Uri uri) =>
      uri.scheme.toLowerCase() == 'https' &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;

  static bool _isPublicHost(String rawHost) {
    final host = rawHost.toLowerCase().replaceAll('[', '').replaceAll(']', '');
    if (host.isEmpty ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.endsWith('.lan') ||
        host == '0.0.0.0' ||
        host == '::' ||
        host == '::1' ||
        host == '127.0.0.1') {
      return false;
    }

    final ipv4 = _parseIpv4(host);
    if (ipv4 != null) {
      final first = ipv4[0];
      final second = ipv4[1];
      return first != 0 &&
          first != 10 &&
          !(first == 100 && second >= 64 && second <= 127) &&
          !(first == 169 && second == 254) &&
          !(first == 172 && second >= 16 && second <= 31) &&
          !(first == 192 && second == 168);
    }

    // IPv6 unique-local (fc00::/7), link-local (fe80::/10), loopback, and
    // unspecified destinations are not public delivery targets.
    if (host.contains(':')) {
      final compact = host.replaceAll('%25', '%');
      if (compact == '::1' ||
          compact == '::' ||
          compact.startsWith('fc') ||
          compact.startsWith('fd') ||
          compact.startsWith('fe8') ||
          compact.startsWith('fe9') ||
          compact.startsWith('fea') ||
          compact.startsWith('feb')) {
        return false;
      }
    }
    return true;
  }

  static List<int>? _parseIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return null;
    final result = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return null;
      result.add(value);
    }
    return result;
  }
}
