bool isPublicVideoHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' || normalized == '127.0.0.1') return false;
  if (normalized == '::1') return false;

  final ipv4 = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$').firstMatch(normalized);
  if (ipv4 != null) {
    final octets = [
      for (var index = 1; index <= 4; index++) int.parse(ipv4.group(index)!),
    ];
    final first = octets[0];
    final second = octets[1];
    return first != 10 &&
        first != 127 &&
        !(first == 172 && second >= 16 && second <= 31) &&
        !(first == 192 && second == 168) &&
        !(first == 169 && second == 254);
  }

  final compactIpv6 = normalized.replaceAll('[', '').replaceAll(']', '');
  if (compactIpv6.contains(':')) {
    final firstGroup = int.tryParse(compactIpv6.split(':').first, radix: 16);
    if (firstGroup != null) {
      final isUniqueLocal = (firstGroup & 0xfe00) == 0xfc00;
      final isLinkLocal = (firstGroup & 0xffc0) == 0xfe80;
      final isUnspecifiedOrLoopback =
          compactIpv6 == '0:0:0:0:0:0:0:0' || compactIpv6 == '::';
      if (isUniqueLocal || isLinkLocal || isUnspecifiedOrLoopback) return false;
    }
  }

  return true;
}
