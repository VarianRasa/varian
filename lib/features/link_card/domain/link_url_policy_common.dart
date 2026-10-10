class LinkUrlValidationException implements Exception {
  final String message;

  const LinkUrlValidationException(this.message);

  @override
  String toString() => message;
}

Uri normalizeLinkUrl(String input) {
  final trimmed = input.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.isAbsolute ||
      (uri.scheme.toLowerCase() != 'http' &&
          uri.scheme.toLowerCase() != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const LinkUrlValidationException(
      'Masukkan URL HTTP atau HTTPS yang valid.',
    );
  }
  final host = uri.host.toLowerCase();
  if (host == 'localhost' || host.endsWith('.localhost')) {
    throw const LinkUrlValidationException('Alamat lokal tidak didukung.');
  }
  final normalized = uri.replace(scheme: uri.scheme.toLowerCase(), host: host);
  if (isPrivateLiteralHost(host)) {
    throw const LinkUrlValidationException(
      'Alamat jaringan privat tidak didukung.',
    );
  }
  return normalized;
}

bool isDirectImageUrl(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  return RegExp(
    r'\.(?:apng|avif|gif|jpe?g|png|webp)$',
  ).hasMatch(uri.path.toLowerCase());
}

bool isPrivateLiteralHost(String host) {
  final ipv4 = RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').firstMatch(host);
  if (ipv4 != null) {
    final octets = host.split('.').map(int.parse).toList();
    if (octets.any((octet) => octet > 255)) return false;
    final a = octets[0];
    final b = octets[1];
    return a == 0 ||
        a == 10 ||
        a == 127 ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        a >= 224;
  }

  if (!host.contains(':')) return false;
  final normalized = host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;
  if (!RegExp(r'^[0-9a-f:]+$', caseSensitive: false).hasMatch(normalized)) {
    return false;
  }
  final groups = normalized.split(':');
  if (groups.where((group) => group.length > 4).isNotEmpty) return false;
  final expanded = expandIpv6(normalized);
  if (expanded.length != 8) return false;
  final values = <int>[];
  for (final group in expanded) {
    final value = int.tryParse(group, radix: 16);
    if (value == null) return false;
    values.add(value);
  }

  final first = values.first;
  return values.every((value) => value == 0) ||
      (values.take(7).every((value) => value == 0) && values.last == 1) ||
      (first & 0xffc0) == 0xfe80 ||
      (first & 0xfe00) == 0xfc00 ||
      (first & 0xff00) == 0xff00;
}

List<String> expandIpv6(String value) {
  if (value.contains('::')) {
    if (value.indexOf('::') != value.lastIndexOf('::')) return const [];
    final halves = value.split('::');
    if (halves.length != 2) return const [];
    final left = halves[0].isEmpty ? const <String>[] : halves[0].split(':');
    final right = halves[1].isEmpty ? const <String>[] : halves[1].split(':');
    final missing = 8 - left.length - right.length;
    if (missing < 1) return const [];
    return [...left, ...List.filled(missing, '0'), ...right];
  }
  final groups = value.split(':');
  return groups.length == 8 ? groups : const [];
}
